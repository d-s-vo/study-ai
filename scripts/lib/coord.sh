#!/usr/bin/env bash
# coord.sh — библиотека координационного слоя мульти-агентной работы.
# Агенты работают под РАЗНЫМИ аккаунтами Claude Code (разные CLAUDE_CONFIG_DIR);
# общее у них — только файловая система workspace. Поэтому вся координация — через
# файлы в ai/coord/ и mkdir-мьютексы. Никаких зависимостей от внутренних механизмов
# Claude Code, кроме проектных хуков (.claude/settings.json).
#
# MUST-HAVE ЯДРО шаблона: перенесено ДОСЛОВНО (mkdir-мьютексы, realm, реентрантность,
# toucher/heartbeat, атомарные записи tmp+mv). Единственная привязка — путь ai/coord/
# через COORD_DIR (переопределяем env). Защищён githooks/guard-write.sh от перезаписи агентом.
#
# bash 3.2-совместимо: без mapfile, без ассоциативных массивов, без grep -P.
# JSON пишем printf'ом (поля фиксированы), читаем jq.
#
# Публичные функции:
#   coord_lock <имя> [max_sec] [progress_sec]   — захват mkdir-мьютекса (trap-освобождение — на вызывающем!)
#   coord_unlock <имя>                          — освобождение мьютекса
#   coord_reap                                  — вычистка мёртвых записей присутствия
#   coord_session                               — идентификатор своей сессии
#   coord_session_file                          — путь своего файла присутствия
#   coord_account                               — имя аккаунта (basename CLAUDE_CONFIG_DIR|default)
#   coord_now                                   — метка времени UTC ISO-8601
#   coord_pid_alive <pid>                       — 0 если процесс жив

# --- определение корня относительно самого себя ---
_coord_src="${BASH_SOURCE[0]:-$0}"
COORD_LIB_DIR="$(cd "$(dirname "$_coord_src")" && pwd)"
COORD_SCRIPTS_DIR="$(dirname "$COORD_LIB_DIR")"
: "${WS_ROOT:=$(dirname "$COORD_SCRIPTS_DIR")}"
: "${COORD_DIR:=$WS_ROOT/ai/coord}"
COORD_AGENTS="$COORD_DIR/agents"
COORD_BOOKINGS="$COORD_DIR/bookings"
COORD_LOCKS="$COORD_DIR/locks"
COORD_ARCHIVE="$COORD_DIR/archive"

# Порог протухания heartbeat (секунд) — записи старше считаются мёртвыми.
: "${COORD_STALE_SEC:=1800}"   # 30 минут

# Порог протухания lock-level heartbeat (owner-mtime, секунд). Держатель длинной секции
# фоново освежает mtime owner-файла (coord_lock_toucher); owner-mtime старше этого порога ⇒
# лок протух ДАЖЕ при живом session-heartbeat (держатель убит SIGKILL — toucher умер с ним).
: "${COORD_LOCK_MTIME_STALE:=300}"   # 5 минут

# --- цвета (только для терминала) ---
if [ -t 2 ]; then
    _C_RED="$(printf '\033[31m')"; _C_YEL="$(printf '\033[33m')"
    _C_GRN="$(printf '\033[32m')"; _C_DIM="$(printf '\033[2m')"; _C_RST="$(printf '\033[0m')"
else
    _C_RED=""; _C_YEL=""; _C_GRN=""; _C_DIM=""; _C_RST=""
fi

coord_now() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
coord_epoch() { date -u '+%s'; }

# coord_account — имя аккаунта Claude Code, иначе 'default'.
# Обычно = basename CLAUDE_CONFIG_DIR (контейнерная схема /home/agent/.claude-accounts/<name>).
# ВЫРАВНИВАНИЕ: на хосте схема — claude-control/accounts/<name>/config-dir, т.е. basename =
# литерал 'config-dir' для ЛЮБОГО аккаунта → аккаунты были бы неразличимы на доске.
# Если basename == 'config-dir' — имя аккаунта берём из РОДИТЕЛЬСКОЙ папки (hostная схема).
coord_account() {
    if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
        _ca_b="$(basename "$CLAUDE_CONFIG_DIR")"
        if [ "$_ca_b" = "config-dir" ]; then
            basename "$(dirname "$CLAUDE_CONFIG_DIR")"
        else
            printf '%s\n' "$_ca_b"
        fi
    else
        printf 'default\n'
    fi
}

# coord_session — идентификатор своей сессии.
#   COORD_SESSION — явно передан (хуками через env или вызывающим); иначе fallback
#   для запуска из терминала: "manual-<pid родителя>".
coord_session() {
    if [ -n "${COORD_SESSION:-}" ]; then
        printf '%s\n' "$COORD_SESSION"
    else
        printf 'manual-%s\n' "${PPID:-0}"
    fi
}

# coord_session_file — путь файла присутствия своей сессии.
coord_session_file() {
    printf '%s/%s.json\n' "$COORD_AGENTS" "$(coord_session)"
}

# coord_pid_alive <pid> — 0 если процесс жив (kill -0). Пустой/нечисловой pid → мёртв.
coord_pid_alive() {
    case "${1:-}" in
        ''|*[!0-9]*) return 1 ;;
    esac
    kill -0 "$1" 2>/dev/null
}

# coord_realm — токен realm (PID-namespace/ядро стороны). Только [a-zA-Z0-9._-].
# N инстансов в одном контейнере делят /proc/self/ns/pid ⇒ один realm ⇒ kill -0 между ними
# валиден; разные контейнеры/хост дают разные inode. macOS-хост нет /proc → host-<hostname>.
# COORD_REALM — escape hatch для тестов. (K-live: kill -0 доверяем только в своём realm.)
coord_realm() {
    if [ -n "${COORD_REALM:-}" ]; then
        printf '%s\n' "$COORD_REALM" | LC_ALL=C tr -cd 'a-zA-Z0-9._-'; return
    fi
    if [ -r /proc/self/ns/pid ]; then
        _r="$(readlink /proc/self/ns/pid 2>/dev/null)"   # pid:[4026532...]
        _r="${_r##*[}"; _r="${_r%]}"
        printf 'ns-%s\n' "$_r"
    else
        printf 'host-%s\n' "$(hostname 2>/dev/null | LC_ALL=C tr -cd 'a-zA-Z0-9._-' || echo unknown)"
    fi
}

# coord_mtime <path> — mtime файла в epoch-секундах (BSD и GNU stat). Пусто, если файла нет.
# ВАЖНО (кросс-граница): GNU-форму (-c) пробуем ПЕРВОЙ. На Linux `stat -f` = --file-system и
# печатает статистику ФС (мусор) с кодом 0 — BSD-first дал бы неверный mtime в контейнере.
# BSD (macOS) `stat -c` падает «illegal option» → фолбэк на `stat -f %m`.
coord_mtime() {
    [ -e "$1" ] || { printf ''; return 0; }
    stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || printf ''
}

# --- реентрантность локов -----------------------------------------------------
# COORD_HELD_LOCKS  — ЭКСПОРТИРУЕТСЯ: имена локов, которые держит это дерево процессов
#                     (наследуется детьми через env).
# _COORD_OWN_LOCKS  — НЕ экспортируется: имена, захваченные ИМЕННО этим процессом
#                     (только он их и снимает). Ребёнок видит имя в COORD_HELD_LOCKS,
#                     но НЕ в своём _COORD_OWN_LOCKS ⇒ его coord_unlock — no-op (шаг 0).
#
# _coord_name_in <имя> <список> — 0, если имя присутствует в space-списке.
_coord_name_in() {
    case " ${2:-} " in
        *" $1 "*) return 0 ;;
        *) return 1 ;;
    esac
}
# _coord_list_add <имя> <список> — печатает список с добавленным именем (без дублей).
_coord_list_add() {
    if _coord_name_in "$1" "${2:-}"; then
        printf '%s' "${2:-}"
    else
        printf '%s' "${2:+$2 }$1"
    fi
}
# _coord_list_del <имя> <список> — печатает список без указанного имени.
_coord_list_del() {
    _cld_out=""
    for _cld_x in ${2:-}; do
        [ "$_cld_x" = "$1" ] && continue
        _cld_out="${_cld_out:+$_cld_out }$_cld_x"
    done
    printf '%s' "$_cld_out"
}
# _coord_own_forget <имя> — забыть имя в обоих наборах (после снятия своего лока).
_coord_own_forget() {
    _COORD_OWN_LOCKS="$(_coord_list_del "$1" "${_COORD_OWN_LOCKS:-}")"
    COORD_HELD_LOCKS="$(_coord_list_del "$1" "${COORD_HELD_LOCKS:-}")"
    export COORD_HELD_LOCKS
}
# _coord_is_ancestor <pid> — 0, если <pid> в цепочке предков ТЕКУЩЕГО процесса
# (walk по PPID от $$ вверх до pid 1). Защита от битого/зацикленного ppid — счётчик.
# kill/ppid-walk валиден только в СВОЁМ realm (проверяется вызывающим).
_coord_is_ancestor() {
    _cia_target="$1"
    case "$_cia_target" in ''|*[!0-9]*) return 1 ;; esac
    _cia_p="$$"
    _cia_guard=0
    while [ -n "$_cia_p" ] && [ "$_cia_p" != "0" ]; do
        [ "$_cia_p" = "$_cia_target" ] && return 0
        [ "$_cia_p" = "1" ] && break
        _cia_p="$(ps -o ppid= -p "$_cia_p" 2>/dev/null | tr -d ' ')"
        _cia_guard=$(( _cia_guard + 1 ))
        [ "$_cia_guard" -gt 64 ] && break
    done
    return 1
}
# _coord_reentrant_valid <имя> — 0, если лок <имя> РЕАЛЬНО держит этот процесс или его
# предок: каталог существует И owner непуст И realm(owner)==coord_realm (или owner
# v1 без realm) И ( owner-pid == $$ ИЛИ owner-pid ∈ цепочке предков ). Живость owner-pid
# НЕДОСТАТОЧНА — лок мог перехватить живой ТРЕТИЙ процесс того же realm (не предок).
_coord_reentrant_valid() {
    _crv_owner="$COORD_LOCKS/$1.lock/owner"
    [ -d "$COORD_LOCKS/$1.lock" ] || return 1
    [ -s "$_crv_owner" ] || return 1
    _crv_opid="$(awk '{print $1}' "$_crv_owner" 2>/dev/null)"
    _crv_orealm="$(awk '{print $4}' "$_crv_owner" 2>/dev/null)"
    [ -n "$_crv_opid" ] || return 1
    if [ -n "$_crv_orealm" ] && [ "$_crv_orealm" != "$(coord_realm)" ]; then
        return 1   # чужой realm: ppid/kill неприменимы → не реентрантный
    fi
    [ "$_crv_opid" = "$$" ] && return 0
    _coord_is_ancestor "$_crv_opid" && return 0
    return 1
}

# --- мьютекс на mkdir --------------------------------------------------------
# coord_lock <имя> [max_sec] [progress_sec]
#   Захватывает каталог-мьютекс ai/coord/locks/<имя>.lock.
#   Ожидание до max_sec (по умолчанию 30) шагом 0.5с. progress_sec>0 — печатать
#   прогресс раз в progress_sec секунд ожидания (для долгих гейтов).
#   При занятом локе проверяет владельца (kill -0): мёртвый → перехват с предупреждением.
#   ВНИМАНИЕ: trap-освобождение обязан ставить вызывающий скрипт:
#       coord_lock foo || exit 1
#       trap 'coord_unlock foo' EXIT INT TERM
coord_lock() {
    _cl_name="$1"
    _cl_max="${2:-30}"
    _cl_prog="${3:-0}"
    [ -n "$_cl_name" ] || { printf 'coord_lock: имя лока обязательно\n' >&2; return 2; }
    # --- реентрантность: имя уже в дереве? Ре-валидация владения ---
    # no-op ТОЛЬКО если лок реально держит этот процесс или его предок; иначе
    # (каталога нет / owner чужого realm / перехвачен живым третьим) — унаследованный
    # маркер неактуален: убираем его и идём в ЧЕСТНЫЙ захват штатной mkdir-механикой.
    if _coord_name_in "$_cl_name" "${COORD_HELD_LOCKS:-}"; then
        if _coord_reentrant_valid "$_cl_name"; then
            return 0
        fi
        COORD_HELD_LOCKS="$(_coord_list_del "$_cl_name" "${COORD_HELD_LOCKS:-}")"
        export COORD_HELD_LOCKS
    fi
    mkdir -p "$COORD_LOCKS" 2>/dev/null || true
    _cl_dir="$COORD_LOCKS/$_cl_name.lock"
    _cl_owner="$_cl_dir/owner"
    _cl_waited=0
    # 0.5с * 2 = 1с; итераций = max_sec * 2
    _cl_iter_max=$(( _cl_max * 2 ))
    _cl_i=0
    _cl_noowner=0   # счётчик итераций, когда каталог есть, а owner-файла нет/пуст
    while :; do
        if mkdir "$_cl_dir" 2>/dev/null; then
            # захвачено — пишем владельца АТОМАРНО: во временный файл ВНУТРИ lock-каталога
            # одним printf, затем mv в owner (не «создать пустой → дописать»).
            # owner-файл v2: <pid> <session> <timestamp-iso> <realm> (4 поля).
            # 4-е поле realm — токен PID-namespace/стороны: kill -0 доверяем только в своём realm.
            _cl_tmp="$_cl_dir/.owner.$$"
            printf '%s %s %s %s\n' "$$" "$(coord_session)" "$(coord_now)" "$(coord_realm)" > "$_cl_tmp" 2>/dev/null
            mv "$_cl_tmp" "$_cl_owner" 2>/dev/null || rm -f "$_cl_tmp" 2>/dev/null
            # реентрантный учёт: это МОЙ захват — веду оба набора.
            _COORD_OWN_LOCKS="$(_coord_list_add "$_cl_name" "${_COORD_OWN_LOCKS:-}")"
            COORD_HELD_LOCKS="$(_coord_list_add "$_cl_name" "${COORD_HELD_LOCKS:-}")"
            export COORD_HELD_LOCKS
            return 0
        fi
        # занято — судим протухание по heartbeat session-владельца и owner-mtime (K-live).
        # kill -0 по pid валиден ТОЛЬКО в пределах своего realm (4-е поле owner):
        # через границу PID-namespace он даёт ложные вердикты (перехват живого лока).
        # Перехват ТОЛЬКО если owner-файл непустой (-s).
        if [ -s "$_cl_owner" ]; then
            _cl_noowner=0
            _cl_opid="$(awk '{print $1}' "$_cl_owner" 2>/dev/null)"
            _cl_osess="$(awk '{print $2}' "$_cl_owner" 2>/dev/null)"
            _cl_orealm="$(awk '{print $4}' "$_cl_owner" 2>/dev/null)"   # пусто для owner v1
            _cl_dead=0
            _cl_why=""
            # (0) lock-level heartbeat: owner-mtime старше COORD_LOCK_MTIME_STALE ⇒ протух
            #     ДАЖЕ при живой сессии (держатель убит SIGKILL, toucher умер с ним).
            _cl_omt="$(coord_mtime "$_cl_owner")"
            if [ -n "$_cl_omt" ]; then
                _cl_mtage=$(( $(coord_epoch) - _cl_omt ))
                if [ "$_cl_mtage" -gt "$COORD_LOCK_MTIME_STALE" ]; then
                    _cl_dead=1; _cl_why="owner-mtime старше ${COORD_LOCK_MTIME_STALE}с (lock-heartbeat протух)"
                fi
            fi
            if [ "$_cl_dead" -eq 0 ]; then
                # владелец ЖИВ, если (1) присутствие session живо (namespace-безопасно, первично)
                # ИЛИ (2) свой realm И pid жив (оптимизация; покрывает manual-сессии без presence).
                if coord_presence_alive "$_cl_osess"; then
                    :
                elif [ -n "$_cl_orealm" ] && [ "$_cl_orealm" = "$(coord_realm)" ] \
                     && coord_pid_alive "$_cl_opid"; then
                    :
                else
                    _cl_dead=1; _cl_why="session мертва"
                    if [ -n "$_cl_orealm" ] && [ "$_cl_orealm" != "$(coord_realm)" ]; then
                        _cl_why="session мертва, кросс-realm (kill -0 неприменим)"
                    fi
                fi
            fi
            if [ "$_cl_dead" -eq 1 ]; then
                printf '%scoord: перехват протухшего лока %s (%s; pid=%s session=%s realm=%s)%s\n' \
                    "$_C_YEL" "$_cl_name" "$_cl_why" "${_cl_opid:-?}" "${_cl_osess:-?}" "${_cl_orealm:-—}" "$_C_RST" >&2
                rm -rf "$_cl_dir" 2>/dev/null
                continue
            fi
        else
            # каталог есть, а owner-файла нет (или пуст): либо гонка захвата (кто-то между
            # mkdir и mv), либо мусор от аварийно упавшего процесса (голый mkdir-лок).
            # Даём ~5с (10 итераций по 0.5с) на появление owner; если так и не появился —
            # считаем мусором, чистим с предупреждением и продолжаем.
            _cl_noowner=$(( _cl_noowner + 1 ))
            if [ "$_cl_noowner" -ge 10 ]; then
                printf '%scoord: лок %s без владельца >5с — считаю мусором, очищаю%s\n' \
                    "$_C_YEL" "$_cl_name" "$_C_RST" >&2
                rm -rf "$_cl_dir" 2>/dev/null
                _cl_noowner=0
                continue
            fi
        fi
        _cl_i=$(( _cl_i + 1 ))
        if [ "$_cl_i" -ge "$_cl_iter_max" ]; then
            printf '%scoord: не удалось захватить лок %s за %sс (держит session=%s pid=%s)%s\n' \
                "$_C_RED" "$_cl_name" "$_cl_max" "${_cl_osess:-?}" "${_cl_opid:-?}" "$_C_RST" >&2
            return 1
        fi
        sleep 0.5
        _cl_waited=$(( _cl_waited + 1 ))
        if [ "$_cl_prog" -gt 0 ]; then
            # каждые progress_sec секунд (шаг 0.5с → prog*2 итераций)
            if [ "$(( _cl_waited % (_cl_prog * 2) ))" -eq 0 ]; then
                printf '%scoord: жду лок %s… (%sс, держит session=%s)%s\n' \
                    "$_C_DIM" "$_cl_name" "$(( _cl_waited / 2 ))" "${_cl_osess:-?}" "$_C_RST" >&2
            fi
        fi
    done
}

# coord_lock_toucher <имя> — фоновый цикл: пока родитель (вызвавший процесс) жив, освежать
# mtime owner-файла (lock-level heartbeat). Запуск ПОСЛЕ успешного coord_lock:
#   coord_lock foo || exit 1
#   coord_lock_toucher foo & _t=$!
#   trap 'kill "$_t" 2>/dev/null; coord_unlock foo' EXIT INT TERM
# Умирает с родителем, в т.ч. при SIGKILL (kill -0 родителя перестаёт проходить) → mtime
# протухает → конкурент перехватывает лок по сигналу (0) матрицы. $$ в фоновом subshell'е bash
# остаётся pid'ом ВЫЗЫВАЮЩЕГО (не subshell'а) — это и есть наблюдаемый родитель.
# Осиротевший toucher, переживший перехват на долю интервала, может разово коснуться owner
# НОВОГО владельца — безвредно: владение определяется СОДЕРЖИМЫМ owner (pid/session/realm),
# а не mtime; освежение лишь продлит свежесть. Хвост перехвата ≤ COORD_LOCK_MTIME_STALE+30с.
coord_lock_toucher() {
    _lt_owner="$COORD_LOCKS/$1.lock/owner"; _lt_parent="$$"
    while kill -0 "$_lt_parent" 2>/dev/null; do
        touch "$_lt_owner" 2>/dev/null
        sleep 30
    done
}

# coord_unlock <имя> — освободить мьютекс. Снимаем ТОЛЬКО свой лок — opid == $$ И realm
# совпадает (или owner v1 без realm). Кросс-realm pid-коллизия (чужой живой pid == нашему $$
# в другом namespace) НЕ должна снять чужой лок. Унаследованный от предка лок (в
# COORD_HELD_LOCKS, но не в _COORD_OWN_LOCKS) — no-op: его снимет только процесс-владелец захвата.
#   0) имя ∈ COORD_HELD_LOCKS И имя ∉ _COORD_OWN_LOCKS → return 0 (унаследован от предка)
#   1) lock-каталога нет → return 0
#   2) opid пуст → мусор без владельца → rm; return 0
#   3) opid == $$ И (orealm пуст ИЛИ orealm == coord_realm) → мой лок → rm + забыть; return 0
#   4) иначе → чужой лок, не трогаем → return 0
coord_unlock() {
    _cu_name="$1"
    [ -n "$_cu_name" ] || return 0
    if _coord_name_in "$_cu_name" "${COORD_HELD_LOCKS:-}" \
       && ! _coord_name_in "$_cu_name" "${_COORD_OWN_LOCKS:-}"; then
        return 0
    fi
    _cu_dir="$COORD_LOCKS/$_cu_name.lock"
    [ -d "$_cu_dir" ] || return 0
    _cu_opid="$(awk '{print $1}' "$_cu_dir/owner" 2>/dev/null)"
    _cu_orealm="$(awk '{print $4}' "$_cu_dir/owner" 2>/dev/null)"
    if [ -z "$_cu_opid" ]; then
        rm -rf "$_cu_dir" 2>/dev/null
    elif [ "$_cu_opid" = "$$" ] && { [ -z "$_cu_orealm" ] || [ "$_cu_orealm" = "$(coord_realm)" ]; }; then
        rm -rf "$_cu_dir" 2>/dev/null
        _coord_own_forget "$_cu_name"
    fi
    return 0
}

# --- вычистка мёртвых записей присутствия ------------------------------------
# coord_reap — вычистка протухших записей ai/coord/agents/*.json.
# Правило живости — HEARTBEAT: запись с heartbeat старше COORD_STALE_SEC (или в будущем
# больше чем на 300с — рассинхрон часов / битая метка) считается протухшей и вычищается,
# ДАЖЕ если её PID ещё жив: PID мог быть переиспользован другим процессом, поэтому «PID жив»
# сам по себе не доказывает, что сессия жива. Мёртвый PID лишь УСКОРЯЕТ реап (не ждём
# протухания heartbeat). Битый JSON (не проходит jq -e .) — вычищается как мусор.
# Живая сессия восстановит своё присутствие следующим heartbeat-хуком (coord-heartbeat.sh
# пересоздаёт файл, source=heartbeat-recreate). Вызывается coord.sh/status.sh/sync.sh.
coord_reap() {
    [ -d "$COORD_AGENTS" ] || return 0
    _cr_now="$(coord_epoch)"
    for _cr_f in "$COORD_AGENTS"/*.json; do
        [ -f "$_cr_f" ] || continue
        # битый JSON — сразу мусор
        if ! jq -e . "$_cr_f" >/dev/null 2>&1; then
            rm -f "$_cr_f" 2>/dev/null
            printf '%scoord: убран битый файл присутствия %s (не проходит jq)%s\n' \
                "$_C_DIM" "$(basename "$_cr_f")" "$_C_RST" >&2
            continue
        fi
        _cr_pid="$(jq -r '.pid // empty' "$_cr_f" 2>/dev/null)"
        _cr_sess="$(jq -r '.session_id // empty' "$_cr_f" 2>/dev/null)"
        _cr_hb="$(jq -r '.heartbeat // empty' "$_cr_f" 2>/dev/null)"
        _cr_realm="$(jq -r '.realm // empty' "$_cr_f" 2>/dev/null)"
        _cr_dead=0
        _cr_why=""
        # 1) heartbeat — основное правило живости
        if [ -n "$_cr_hb" ]; then
            _cr_hb_epoch="$(_coord_iso_to_epoch "$_cr_hb")"
            if [ -n "$_cr_hb_epoch" ]; then
                _cr_age=$(( _cr_now - _cr_hb_epoch ))
                if [ "$_cr_age" -gt "$COORD_STALE_SEC" ]; then
                    _cr_dead=1; _cr_why="heartbeat старше $(( COORD_STALE_SEC / 60 ))мин"
                elif [ "$_cr_age" -lt -300 ]; then
                    _cr_dead=1; _cr_why="heartbeat в будущем >300с (битая метка/рассинхрон часов)"
                fi
            fi
        fi
        # 2) мёртвый PID — лишь ускоряет реап, и ТОЛЬКО в СВОЁМ realm (K-live):
        # pid чужого PID-namespace через границу даёт ложный вердикт → удалили бы живую
        # контейнерную сессию. Записи без realm (v1) или чужого realm → только heartbeat-правило.
        if [ "$_cr_dead" -eq 0 ] && [ -n "$_cr_realm" ] && [ "$_cr_realm" = "$(coord_realm)" ] \
           && [ -n "$_cr_pid" ] && ! coord_pid_alive "$_cr_pid"; then
            _cr_dead=1; _cr_why="мёртвый pid=$_cr_pid (свой realm)"
        fi
        if [ "$_cr_dead" -eq 1 ]; then
            rm -f "$_cr_f" 2>/dev/null
            printf '%scoord: убрана протухшая сессия %s (%s)%s\n' \
                "$_C_DIM" "${_cr_sess:-$(basename "$_cr_f" .json)}" "$_cr_why" "$_C_RST" >&2
        fi
    done
    return 0
}

# coord_presence_alive <session> — 0 если файл присутствия сессии существует, валиден и НЕ
# протух (то же правило живости, что coord_reap: heartbeat в пределах COORD_STALE_SEC и не
# в будущем более чем на 300с). Используется unbook для защиты чужой активной брони.
coord_presence_alive() {
    _pa_f="$COORD_AGENTS/$1.json"
    [ -n "${1:-}" ] || return 1
    [ -f "$_pa_f" ] || return 1
    jq -e . "$_pa_f" >/dev/null 2>&1 || return 1
    _pa_hb="$(jq -r '.heartbeat // empty' "$_pa_f" 2>/dev/null)"
    [ -n "$_pa_hb" ] || return 1
    _pa_e="$(_coord_iso_to_epoch "$_pa_hb")"
    [ -n "$_pa_e" ] || return 1
    _pa_age=$(( $(coord_epoch) - _pa_e ))
    [ "$_pa_age" -lt -300 ] && return 1
    [ "$_pa_age" -le "$COORD_STALE_SEC" ] && return 0
    return 1
}

# _coord_iso_to_epoch <iso8601> — конвертация UTC ISO-8601 в epoch (BSD и GNU date).
_coord_iso_to_epoch() {
    _ci="$1"
    [ -n "$_ci" ] || { printf ''; return 0; }
    # BSD date (macOS)
    _out="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$_ci" '+%s' 2>/dev/null)"
    if [ -z "$_out" ]; then
        # GNU date
        _out="$(date -u -d "$_ci" '+%s' 2>/dev/null)"
    fi
    printf '%s' "$_out"
}
