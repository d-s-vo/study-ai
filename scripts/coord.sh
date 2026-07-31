#!/usr/bin/env bash
# coord.sh — интерфейс координационного слоя мульти-агентной работы.
# Присутствие агентов, брони фич (slug↔FEAT↔ADR↔репо↔ветка↔порты), статусы.
# Правила и жизненный цикл — ai/guides/coordination.md.
#
# GENERIC-КОПИЯ. Механика (атомарность tmp+mv, локи, санитизация, валидация по repos.conf) —
# перенесена дословно; ЗНАЧЕНИЯ схемы портов/лимитов/дефолт-репы — параметры (см. блок ADAPT).
# ⚠ ИСТОЧНИК ИСТИНЫ схемы портов — ЗДЕСЬ (coordination.md/stack-specifics.md лишь ссылаются).
#
# Использование:
#   coord.sh agents                    # живые сессии
#   coord.sh board                     # доска броней
#   coord.sh book <slug> [--repo <имя>] [--adr]
#   coord.sh update <slug> --status <planned|spec|impl|verify|delivered|merged>
#   coord.sh unbook <slug> [--force]
#   coord.sh reap                      # явная вычистка мёртвых сессий
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
: "${WS_ROOT:=$(dirname "$SCRIPT_DIR")}"
. "$SCRIPT_DIR/lib/coord.sh"
. "$WS_ROOT/githooks/lib/scan.sh"

STATUSES="planned spec impl verify delivered merged"

# --- ADAPT: параметры схемы окружения задачи (см. ai/guides/stack-specifics.md) ---------------
# Базы портов сервисов: порт задачи = база + index_брони * PORT_STRIDE. Добавьте/уберите
# сервисы под свой стек (backend/frontend — образец; напр. admin/help — по аналогии).
PORT_BASE_BACKEND="${PORT_BASE_BACKEND:-8100}"
PORT_BASE_FRONTEND="${PORT_BASE_FRONTEND:-5173}"
PORT_BASE_AUX="${PORT_BASE_AUX:-3100}"        # доп. сервис (help/admin/…); уберите, если не нужен
PORT_STRIDE="${PORT_STRIDE:-10}"
INDEX_LIMIT="${INDEX_LIMIT:-9}"               # лимит параллельных броней (индексы 1..INDEX_LIMIT)
# redis-db пул для изоляции задач: db = REDIS_BASE_DB + index, с пропуском REDIS_SKIP_DB
# (номер, зарезервированный под общий брокер очередей). Если redis не используется — поле игнор.
REDIS_BASE_DB="${REDIS_BASE_DB:-4}"
REDIS_SKIP_DB="${REDIS_SKIP_DB:-10}"
# cbook — репа по умолчанию для book (из repos.conf), когда --repo не задан.
DEFAULT_REPO="cbook"
# ---------------------------------------------------------------------------------------------

die() { printf '%sОШИБКА: %s%s\n' "$_C_RED" "$*" "$_C_RST" >&2; exit 1; }
say() { printf '%s\n' "$*"; }

# --- аллокаторы номеров -------------------------------------------------------

# _feat_max — максимальный FEAT-номер из ТАБЛИЦЫ features/README.md + всех броней/архива.
# Из README считаются ТОЛЬКО строки markdown-таблицы (начинающиеся с |); проза НЕ учитывается.
# Если в таблице номеров нет, но в файле FEAT-NNN всё же присутствуют — таблица сломана:
# возвращаем код 3 (громкий отказ book). Сравнения через 10# (ведущие нули — не octal).
_feat_max() {
    _fm=0
    _readme="$WS_ROOT/ai/devlog/features/README.md"
    if [ -f "$_readme" ]; then
        _fm_rows="$(grep -E '^[[:space:]]*\|' "$_readme" 2>/dev/null | grep -oE 'FEAT-[0-9]+' | sed 's/FEAT-//')"
        if [ -n "$_fm_rows" ]; then
            for _n in $_fm_rows; do
                case "$_n" in ''|*[!0-9]*) continue ;; esac
                _n=$(( 10#$_n ))
                [ "$_n" -gt "$_fm" ] && _fm="$_n"
            done
        elif grep -qE 'FEAT-[0-9]+' "$_readme" 2>/dev/null; then
            printf '%sОШИБКА: не удалось извлечь ни одного FEAT-номера из таблицы в\n  %s,\n  хотя FEAT-NNN в файле присутствуют — таблица features/README.md, похоже, сломана.\n  Почините формат (строки данных должны начинаться с | и содержать FEAT-NNN) и повторите.%s\n' \
                "$_C_RED" "$_readme" "$_C_RST" >&2
            return 3
        fi
    fi
    for _d in "$COORD_BOOKINGS" "$COORD_ARCHIVE"; do
        for _f in "$_d"/*.json; do
            [ -f "$_f" ] || continue
            _n="$(jq -r '.feat // empty' "$_f" 2>/dev/null | sed 's/FEAT-//')"
            case "$_n" in ''|*[!0-9]*) continue ;; esac
            _n=$(( 10#$_n ))
            [ "$_n" -gt "$_fm" ] && _fm="$_n"
        done
    done
    printf '%s\n' "$_fm"
}

# _feat_dirs_max — максимальный FEAT-номер по ФАКТУ: папки ai/devlog/features/FEAT-NNN-*.
# Независимый от реестров источник (папку создаёт spec-фаза фичи). Используется как
# кросс-проверка в book: реестры (таблица+брони) не могут отставать от факта.
_feat_dirs_max() {
    _fdm=0
    for _d in "$WS_ROOT/ai/devlog/features"/FEAT-[0-9]*; do
        [ -d "$_d" ] || continue
        _n="$(basename "$_d" | sed -E 's/^FEAT-0*([0-9]+).*/\1/')"
        case "$_n" in ''|*[!0-9]*) continue ;; esac
        _n=$(( 10#$_n ))
        [ "$_n" -gt "$_fdm" ] && _fdm="$_n"
    done
    printf '%s\n' "$_fdm"
}

# _adr_max — максимальный ADR-номер из ai/adr/*.md + всех броней/архива.
_adr_max() {
    _am=0
    for _f in "$WS_ROOT/ai/adr"/[0-9]*.md; do
        [ -f "$_f" ] || continue
        _n="$(basename "$_f" | sed -E 's/^0*([0-9]+).*/\1/')"
        case "$_n" in ''|*[!0-9]*) continue ;; esac
        _n=$(( 10#$_n ))
        [ "$_n" -gt "$_am" ] && _am="$_n"
    done
    for _d in "$COORD_BOOKINGS" "$COORD_ARCHIVE"; do
        for _f in "$_d"/*.json; do
            [ -f "$_f" ] || continue
            _n="$(jq -r '.adr // empty' "$_f" 2>/dev/null | sed 's/ADR-//')"
            case "$_n" in ''|*[!0-9]*) continue ;; esac
            _n=$(( 10#$_n ))
            [ "$_n" -gt "$_am" ] && _am="$_n"
        done
    done
    printf '%s\n' "$_am"
}

# _index_used — печатает занятые индексы из активных броней (по строке на индекс).
_index_used() {
    for _f in "$COORD_BOOKINGS"/*.json; do
        [ -f "$_f" ] || continue
        jq -r '.index // empty' "$_f" 2>/dev/null
    done
}

# _index_free — минимальный свободный индекс 1..INDEX_LIMIT по активным броням; пусто если нет.
_index_free() {
    _used="$(_index_used)"
    _i=1
    while [ "$_i" -le "$INDEX_LIMIT" ]; do
        if ! printf '%s\n' "$_used" | grep -qx "$_i"; then
            printf '%s\n' "$_i"; return 0
        fi
        _i=$(( _i + 1 ))
    done
    printf ''
}

# _booking_path <slug> — путь брони (bookings), пусто если нет.
_booking_path() {
    [ -f "$COORD_BOOKINGS/$1.json" ] && printf '%s\n' "$COORD_BOOKINGS/$1.json"
}

# _slug_taken <slug> — 0 если slug есть в bookings ИЛИ archive.
_slug_taken() {
    [ -f "$COORD_BOOKINGS/$1.json" ] && return 0
    [ -f "$COORD_ARCHIVE/$1.json" ] && return 0
    return 1
}

# _validate_slug <slug> — [a-z0-9-]+ и без стоп-слов (тот же сканер, что task.sh).
_validate_slug() {
    _sl="$1"
    printf '%s' "$_sl" | grep -qE '^[a-z0-9-]+$' \
        || die "недопустимый slug '$_sl': разрешены только [a-z0-9-]."
    _rep="$(scan_string "$_sl" || true)"
    [ -z "$_rep" ] || { printf '%s\n' "$_rep" >&2; die "slug '$_sl' содержит стоп-слово."; }
}

# _validate_repo <repo> — репа обязана быть в реестре scripts/repos.conf.
# Неизвестная репа → отказ (защита от инъекции произвольного значения в бронь, которая
# коммитится и приходит другим агентам). Формат имени ограничиваем [a-z0-9-] до сверки.
_validate_repo() {
    _rp="$1"
    printf '%s' "$_rp" | grep -qE '^[a-z0-9-]+$' \
        || die "недопустимое имя репы '$_rp': разрешены только [a-z0-9-]."
    _conf="$SCRIPT_DIR/repos.conf"
    [ -f "$_conf" ] || die "реестр реп не найден: $_conf"
    # первое поле каждой не-комментарной строки — имя репы
    _known="$(grep -vE '^[[:space:]]*#' "$_conf" 2>/dev/null \
                | awk -F'|' 'NF>=2 {gsub(/^[ \t]+|[ \t]+$/,"",$1); if($1!="") print $1}')"
    if ! printf '%s\n' "$_known" | grep -qxF -- "$_rp"; then
        die "неизвестная репа '$_rp'. Допустимые (repos.conf): $(printf '%s' "$_known" | tr '\n' ' ')"
    fi
}

# _hb_age <iso> — человекочитаемый возраст heartbeat (сейчас минус iso).
_hb_age() {
    _e="$(_coord_iso_to_epoch "$1")"
    [ -n "$_e" ] || { printf '?'; return; }
    _d=$(( $(coord_epoch) - _e ))
    if [ "$_d" -lt 60 ]; then printf '%sс' "$_d"
    elif [ "$_d" -lt 3600 ]; then printf '%sм' "$(( _d / 60 ))"
    else printf '%sч' "$(( _d / 3600 ))"; fi
}

# --- команды ------------------------------------------------------------------

cmd_agents() {
    coord_reap
    printf '%s== АГЕНТЫ ОНЛАЙН ==%s\n' "$_C_GRN" "$_C_RST"
    _fmt='  %-20s %-14s %-8s %-8s %s\n'
    # shellcheck disable=SC2059
    printf "$_fmt" "СЕССИЯ" "АККАУНТ" "PID" "HB" "БРОНЬ"
    printf '%s\n' "------------------------------------------------------------------------"
    _any=0
    for _f in "$COORD_AGENTS"/*.json; do
        [ -f "$_f" ] || continue
        _any=1
        _sess="$(jq -r '.session_id // "?"' "$_f")"
        _acc="$(jq -r '.account // "?"' "$_f")"
        _pid="$(jq -r '.pid // "?"' "$_f")"
        _hb="$(jq -r '.heartbeat // empty' "$_f")"
        _short="$(printf '%s' "$_sess" | cut -c1-18)"
        # бронь этой сессии
        _book="-"
        for _b in "$COORD_BOOKINGS"/*.json; do
            [ -f "$_b" ] || continue
            if [ "$(jq -r '.agent // empty' "$_b")" = "$_sess" ]; then
                _book="$(jq -r '.slug + " (" + .status + ")"' "$_b")"; break
            fi
        done
        # shellcheck disable=SC2059
        printf "$_fmt" "$_short" "$_acc" "$_pid" "$(_hb_age "$_hb")" "$_book"
    done
    [ "$_any" -eq 0 ] && printf '  (живых сессий нет)\n'
}

cmd_board() {
    coord_reap
    printf '%s== БРОНИ ==%s\n' "$_C_GRN" "$_C_RST"
    _fmt='  %-20s %-9s %-8s %-16s %-24s %-10s %-16s %-3s %s\n'
    # shellcheck disable=SC2059
    printf "$_fmt" "SLUG" "FEAT" "ADR" "РЕПО" "ВЕТКА" "СТАТУС" "АГЕНТ" "IDX" "ОБНОВЛЕНО"
    printf '%s\n' "--------------------------------------------------------------------------------------------------------------------"
    _any=0
    for _f in "$COORD_BOOKINGS"/*.json; do
        [ -f "$_f" ] || continue
        _any=1
        _row="$(jq -r '[.slug, .feat, (.adr // "-"), .repo, .branch, .status, (.agent // "-"), (.index|tostring), .updated] | @tsv' "$_f")"
        _slug="$(printf '%s' "$_row" | cut -f1)"
        _feat="$(printf '%s' "$_row" | cut -f2)"
        _adr="$(printf '%s' "$_row" | cut -f3)"
        _repo="$(printf '%s' "$_row" | cut -f4)"
        _branch="$(printf '%s' "$_row" | cut -f5)"
        _st="$(printf '%s' "$_row" | cut -f6)"
        _agent="$(printf '%s' "$_row" | cut -f7 | cut -c1-14)"
        _idx="$(printf '%s' "$_row" | cut -f8)"
        _upd="$(printf '%s' "$_row" | cut -f9)"
        # shellcheck disable=SC2059
        printf "$_fmt" "$_slug" "$_feat" "$_adr" "$_repo" "$_branch" "$_st" "$_agent" "$_idx" "$_upd"
    done
    [ "$_any" -eq 0 ] && printf '  (активных броней нет)\n'
    # счётчик архива
    _arc=0
    for _f in "$COORD_ARCHIVE"/*.json; do [ -f "$_f" ] && _arc=$(( _arc + 1 )); done
    printf '%s  в архиве (merged): %s%s\n' "$_C_DIM" "$_arc" "$_C_RST"
}

cmd_book() {
    _slug=""; _repo="$DEFAULT_REPO"; _want_adr=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --repo) _repo="${2:?имя репы после --repo}"; shift 2 ;;
            --repo=*) _repo="${1#--repo=}"; shift ;;
            --adr) _want_adr=1; shift ;;
            -*) die "неизвестный флаг book: $1" ;;
            *) [ -z "$_slug" ] && _slug="$1" || die "лишний аргумент: $1"; shift ;;
        esac
    done
    [ -n "$_slug" ] || die "укажите slug: coord.sh book <slug> [--repo <имя>] [--adr]"
    _validate_slug "$_slug"
    _validate_repo "$_repo"

    coord_lock booking || die "не удалось захватить лок booking"
    trap 'coord_unlock booking' EXIT INT TERM

    if _slug_taken "$_slug"; then
        coord_unlock booking; trap - EXIT INT TERM
        die "slug '$_slug' уже занят (bookings/ или archive/). Выберите другой."
    fi

    if ! _feat_max_v="$(_feat_max)"; then
        coord_unlock booking; trap - EXIT INT TERM
        die "нумерация FEAT недоступна — почините таблицу в ai/devlog/features/README.md (подробности выше)."
    fi
    # Кросс-проверка реестров против факта: папки FEAT-NNN-* в devlog/features не должны
    # уходить дальше реестров (таблица маппинга + брони/архив). Расхождение = чьё-то закрытие
    # прошло мимо Шага 10 feature-workflow → выдача занятого номера. Чиним реестр, не игнорируем.
    _feat_dirs_v="$(_feat_dirs_max)"
    if [ "$_feat_dirs_v" -gt "$_feat_max_v" ]; then
        coord_unlock booking; trap - EXIT INT TERM
        die "реестры FEAT отстали от факта: в ai/devlog/features/ есть папка FEAT-$(printf '%03d' "$_feat_dirs_v")-*, а максимум по таблице маппинга и броням — FEAT-$(printf '%03d' "$_feat_max_v").
     Кто-то закрыл фичу мимо Шага 10 feature-workflow. Сначала дополните реестр:
       ./scripts/feat-map.sh add FEAT-NNN --branch <ветка> --repo <репо> --status done --commit <sha> --desc \"<что>\"
     (по строке на каждый недостающий номер; данные — в impl.md соответствующей папки), затем повторите book."
    fi

    _feat_n=$(( 10#$_feat_max_v + 1 ))
    _feat="$(printf 'FEAT-%03d' "$_feat_n")"

    _adr="null"; _adr_out="—"
    if [ "$_want_adr" -eq 1 ]; then
        _adr_max_v="$(_adr_max)"
        _adr_n=$(( 10#$_adr_max_v + 1 ))
        _adr="\"$(printf 'ADR-%03d' "$_adr_n")\""
        _adr_out="$(printf 'ADR-%03d' "$_adr_n")"
    fi

    _idx="$(_index_free)"
    [ -n "$_idx" ] || { coord_unlock booking; trap - EXIT INT TERM; die "все индексы 1..$INDEX_LIMIT заняты — лимит параллельных броней исчерпан."; }

    # Порты (источник истины — здесь; таблица в coordination.md — справка).
    _be=$(( PORT_BASE_BACKEND  + _idx * PORT_STRIDE ))
    _fe=$(( PORT_BASE_FRONTEND + _idx * PORT_STRIDE ))
    _ax=$(( PORT_BASE_AUX      + _idx * PORT_STRIDE ))
    # redis-пул с пропуском REDIS_SKIP_DB (номер общего брокера).
    _rdb=$(( REDIS_BASE_DB + _idx ))
    [ "$_rdb" -ge "$REDIS_SKIP_DB" ] && _rdb=$(( _rdb + 1 ))
    _sess="$(coord_session)"
    _acc="$(coord_account)"
    _now="$(coord_now)"
    _branch="feat/$_slug"

    # Запись брони АТОМАРНО: собираем во временный файл, валидируем jq, затем mv на место.
    _bt="$COORD_BOOKINGS/.$_slug.json.tmp.$$"
    {
        printf '{\n'
        printf '  "slug": "%s",\n'      "$_slug"
        printf '  "feat": "%s",\n'      "$_feat"
        printf '  "adr": %s,\n'         "$_adr"
        printf '  "repo": "%s",\n'      "$_repo"
        printf '  "branch": "%s",\n'    "$_branch"
        printf '  "status": "planned",\n'
        printf '  "agent": "%s",\n'     "$_sess"
        printf '  "account": "%s",\n'   "$_acc"
        printf '  "index": %s,\n'       "$_idx"
        printf '  "ports": { "backend": %s, "frontend": %s, "aux": %s },\n' "$_be" "$_fe" "$_ax"
        printf '  "redis_db": %s,\n'    "$_rdb"
        printf '  "created": "%s",\n'   "$_now"
        printf '  "updated": "%s"\n'    "$_now"
        printf '}\n'
    } > "$_bt"

    if ! jq -e . "$_bt" >/dev/null 2>&1; then
        rm -f "$_bt"
        coord_unlock booking; trap - EXIT INT TERM
        die "собранный JSON брони невалиден — запись отменена."
    fi
    mv "$_bt" "$COORD_BOOKINGS/$_slug.json"

    coord_unlock booking; trap - EXIT INT TERM

    say "${_C_GRN}Забронировано: $_slug${_C_RST}"
    say "  FEAT: $_feat   ADR: $_adr_out   репо: $_repo   ветка: $_branch   индекс: $_idx"
    say "  порты: backend $_be, frontend $_fe, aux $_ax   redis_db: $_rdb"
    say ""
    say "Следующие шаги:"
    say "  1) ./scripts/task.sh new $_slug         # ветка $_branch + worktree tasks/$_slug"
    # env-for-task.sh существует только при включённом M4 (env-изоляция задач); при M4=OFF не подсказываем.
    if [ -x "$SCRIPT_DIR/env-for-task.sh" ]; then
        say "  2) ./scripts/env-for-task.sh $_slug     # изолированное окружение (ПОСЛЕ task.sh new; M4)"
        say "  3) статус по мере работы: ./scripts/coord.sh update $_slug --status spec|impl|verify"
    else
        say "  2) статус по мере работы: ./scripts/coord.sh update $_slug --status spec|impl|verify"
    fi
}

cmd_update() {
    _slug=""; _status=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --status) _status="${2:?статус после --status}"; shift 2 ;;
            --status=*) _status="${1#--status=}"; shift ;;
            -*) die "неизвестный флаг update: $1" ;;
            *) [ -z "$_slug" ] && _slug="$1" || die "лишний аргумент: $1"; shift ;;
        esac
    done
    [ -n "$_slug" ] || die "укажите slug: coord.sh update <slug> --status <s>"
    [ -n "$_status" ] || die "укажите --status <planned|spec|impl|verify|delivered|merged>"
    printf '%s ' $STATUSES | grep -qw "$_status" || die "недопустимый статус '$_status'. Допустимо: $STATUSES"
    _bp="$(_booking_path "$_slug")"
    [ -n "$_bp" ] || die "брони '$_slug' нет (bookings/). Возможно, она в архиве."

    coord_lock booking || die "не удалось захватить лок booking"
    trap 'coord_unlock booking' EXIT INT TERM

    _cur="$(jq -r '.status' "$_bp")"
    # индексы для проверки «скачка»
    _oi=0; _ni=0; _p=0
    for _s in $STATUSES; do
        _p=$(( _p + 1 ))
        [ "$_s" = "$_cur" ] && _oi="$_p"
        [ "$_s" = "$_status" ] && _ni="$_p"
    done
    _delta=$(( _ni - _oi ))
    [ "$_delta" -lt 0 ] && _delta=$(( -_delta ))
    if [ "$_delta" -gt 1 ]; then
        printf '%sПРЕДУПРЕЖДЕНИЕ: скачок статуса %s -> %s (пропущены промежуточные).%s\n' \
            "$_C_YEL" "$_cur" "$_status" "$_C_RST" >&2
    fi

    _now="$(coord_now)"
    _tmp="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/coord.$$")"
    jq --arg s "$_status" --arg u "$_now" '.status=$s | .updated=$u' "$_bp" > "$_tmp" \
        && mv "$_tmp" "$_bp" || { rm -f "$_tmp"; coord_unlock booking; trap - EXIT INT TERM; die "не удалось обновить бронь."; }

    coord_unlock booking; trap - EXIT INT TERM
    say "${_C_GRN}$_slug: статус $_cur -> $_status${_C_RST}"
    [ "$_status" = "merged" ] && say "  merged: убрать бронь в архив — ./scripts/coord.sh unbook $_slug (или sync.sh --cleanup сделает автоматически)"
}

cmd_unbook() {
    _slug=""; _force=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --force) _force=1; shift ;;
            -*) die "неизвестный флаг unbook: $1" ;;
            *) [ -z "$_slug" ] && _slug="$1" || die "лишний аргумент: $1"; shift ;;
        esac
    done
    [ -n "$_slug" ] || die "укажите slug: coord.sh unbook <slug> [--force]"
    _bp="$(_booking_path "$_slug")"
    [ -n "$_bp" ] || die "брони '$_slug' нет (bookings/)."

    coord_lock booking || die "не удалось захватить лок booking"
    trap 'coord_unlock booking' EXIT INT TERM

    _st="$(jq -r '.status' "$_bp")"
    if [ "$_st" = "merged" ]; then
        mv "$_bp" "$COORD_ARCHIVE/$_slug.json"
        coord_unlock booking; trap - EXIT INT TERM
        say "${_C_GRN}$_slug: бронь (merged) перемещена в archive/${_C_RST}"
        [ -x "$SCRIPT_DIR/env-for-task.sh" ] && say "  ${_C_YEL}напоминание: тирдаун окружения — ./scripts/env-for-task.sh $_slug --down${_C_RST}"
        return 0
    fi
    if [ "$_force" -ne 1 ]; then
        coord_unlock booking; trap - EXIT INT TERM
        die "бронь '$_slug' в статусе '$_st' (не merged). Это брошенная работа — подтвердите: coord.sh unbook $_slug --force"
    fi
    # --force НЕ снимает чужую АКТИВНУЮ бронь: если владелец — другой агент и его присутствие
    # ещё живо (heartbeat не протух), отказываем (работа не брошена, а идёт).
    _owner="$(jq -r '.agent // empty' "$_bp" 2>/dev/null)"
    _me="$(coord_session)"
    if [ -n "$_owner" ] && [ "$_owner" != "$_me" ] && coord_presence_alive "$_owner"; then
        _ohb="$(jq -r '.heartbeat // "?"' "$COORD_AGENTS/$_owner.json" 2>/dev/null)"
        coord_unlock booking; trap - EXIT INT TERM
        die "бронь '$_slug' принадлежит ЖИВОМУ агенту $_owner (heartbeat $_ohb) — снимать чужую активную бронь нельзя. Дождитесь протухания его присутствия или согласуйте снятие с владельцем."
    fi
    rm -f "$_bp"
    coord_unlock booking; trap - EXIT INT TERM
    say "${_C_YEL}$_slug: бронь удалена (--force, статус был '$_st').${_C_RST}"
    [ -x "$SCRIPT_DIR/env-for-task.sh" ] && say "  ${_C_YEL}напоминание: тирдаун окружения — ./scripts/env-for-task.sh $_slug --down${_C_RST}"
}

# --- диспетчер ----------------------------------------------------------------
cmd="${1:-}"; [ "$#" -gt 0 ] && shift
case "$cmd" in
    agents) cmd_agents "$@" ;;
    board)  cmd_board "$@" ;;
    book)   cmd_book "$@" ;;
    update) cmd_update "$@" ;;
    unbook) cmd_unbook "$@" ;;
    reap)   coord_reap; say "reap выполнен." ;;
    -h|--help|'') grep '^#' "$0" | sed 's/^# \{0,1\}//' ;;
    *) die "неизвестная команда: $cmd (agents|board|book|update|unbook|reap)" ;;
esac
