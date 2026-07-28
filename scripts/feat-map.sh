#!/usr/bin/env bash
# feat-map.sh — маппинг FEAT-NNN ↔ ветка/репо/статус как append-атомарные записи
# (по образцу броней), с генерацией markdown-таблицы в ai/devlog/features/README.md
# (МОДУЛЬ M2/M6; K-shared).
#
# Каждая фича дописывает СВОЮ запись атомарно (tmp+mv под локом): разные FEAT — разные
# файлы ai/devlog/features/map/FEAT-NNN.json ⇒ конкурентный add разных номеров не имеет
# общего файла для перезаписи. Таблица маппинга — ГЕНЕРИРУЕТСЯ из записей между маркерами
# <!-- FEAT-MAP:BEGIN --> / <!-- FEAT-MAP:END -->; проза README — вне маркеров, сохраняется.
#
# GENERIC-КОПИЯ. # ADAPT: сущность «FEAT» и путь таблицы — под нумерацию проекта. Для проекта
# без FEAT-нумерации скрипт не нужен либо переосмысливается под свои сущности.
#
# Использование:
#   feat-map.sh add <FEAT-NNN> --branch <b> --repo <r> [--adr <ADR-NNN>] --status <s> --desc "<d>" [--commit <sha>]
#   feat-map.sh reserve <FROM..TO> --adr <ADR-NNN> --phase "<...>" [--desc-prefix "<...>"]
#   feat-map.sh set <FEAT-NNN> --status <s> [--branch <b>] [--commit <sha>] [--desc "<d>"]
#   feat-map.sh render        # регенерирует секцию таблицы README из записей
#   feat-map.sh migrate       # разовая: маркеры + посев map/ из текущей таблицы README
#
# Локи (порядок строго booking → edit-shared → shared-docs, против дедлока):
#   add/reserve/migrate (выделяют/резервируют номера): coord_lock booking + toucher → coord_lock
#     edit-shared + toucher → RMW (record-файлы tmp+mv + render README tmp+mv) → ai-commit.sh
#     (берёт shared-docs) → снятие. booking держится до конца: конкурентный coord.sh book
#     ждёт лок и видит уже консистентную таблицу (_feat_max свеж).
#   set/render (номера не выделяют): без booking — только edit-shared + toucher → ai-commit.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
: "${WS_ROOT:=$(dirname "$SCRIPT_DIR")}"
. "$SCRIPT_DIR/lib/coord.sh"
. "$WS_ROOT/githooks/lib/scan.sh"

# study-cbook-ai — имя внутреннего репо артефактов (для маппинга инфраструктурных фич).
AI_REPO_NAME="study-cbook-ai"
MAP_DIR="$WS_ROOT/ai/devlog/features/map"
README="$WS_ROOT/ai/devlog/features/README.md"
README_REL="ai/devlog/features/README.md"
MAP_REL="ai/devlog/features/map"
MARK_BEGIN="<!-- FEAT-MAP:BEGIN -->"
MARK_END="<!-- FEAT-MAP:END -->"
STATUSES="reserved in-progress done"

die() { printf '%sОШИБКА: %s%s\n' "$_C_RED" "$*" "$_C_RST" >&2; exit 1; }
say() { printf '%s\n' "$*"; }

# --- валидация ---------------------------------------------------------------

# _valid_feat <FEAT-NNN> — формат FEAT- + >=3 цифр (совместимо с _feat_max/coord.sh).
_valid_feat() {
    printf '%s' "$1" | grep -qE '^FEAT-[0-9]{3,}$' || die "недопустимый FEAT '$1': ожидается FEAT-NNN (>=3 цифр)."
}

# _valid_status <s> — из набора reserved|in-progress|done.
_valid_status() {
    printf '%s ' $STATUSES | grep -qw "$1" || die "недопустимый статус '$1'. Допустимо: $STATUSES"
}

# _valid_repo <repo> — репа из repos.conf либо внутренний репо артефактов.
_valid_repo() {
    _vr="$1"
    [ "$_vr" = "$AI_REPO_NAME" ] && return 0
    printf '%s' "$_vr" | grep -qE '^[a-z0-9-]+$' || die "недопустимое имя репы '$_vr': [a-z0-9-] или $AI_REPO_NAME."
    _conf="$SCRIPT_DIR/repos.conf"
    [ -f "$_conf" ] || die "реестр реп не найден: $_conf"
    _known="$(grep -vE '^[[:space:]]*#' "$_conf" 2>/dev/null | awk -F'|' 'NF>=2 {gsub(/^[ \t]+|[ \t]+$/,"",$1); if($1!="") print $1}')"
    printf '%s\n' "$_known" | grep -qxF -- "$_vr" || die "неизвестная репа '$_vr'. Допустимо (repos.conf): $(printf '%s' "$_known" | tr '\n' ' ') $AI_REPO_NAME"
}

# _valid_adr <ADR-NNN> — формат либо пусто/null.
_valid_adr() {
    case "$1" in ''|null) return 0 ;; esac
    printf '%s' "$1" | grep -qE '^ADR-[0-9]{3,}$' || die "недопустимый ADR '$1': ожидается ADR-NNN."
}

# _valid_branch <b> — [a-z0-9/_.-] и без стоп-слов (как coord.sh); '—' пропускается.
_valid_branch() {
    _vb="$1"
    [ "$_vb" = "—" ] && return 0
    printf '%s' "$_vb" | grep -qE '^[a-z0-9/_.-]+$' || die "недопустимая ветка '$_vb': разрешены [a-z0-9/_.-]."
    _rep="$(scan_string "$_vb" || true)"
    [ -z "$_rep" ] || { printf '%s\n' "$_rep" >&2; die "ветка '$_vb' содержит стоп-слово."; }
}

# _valid_desc <d> — только скан стоп-словаря (текст произвольный, но без следов системы).
_valid_desc() {
    _rep="$(scan_string "$1" || true)"
    [ -z "$_rep" ] || { printf '%s\n' "$_rep" >&2; die "описание содержит стоп-слово (см. выше)."; }
}

# _feat_num <FEAT-NNN> — печатает числовую часть без ведущих нулей (10#).
_feat_num() { printf '%s\n' "$(( 10#$(printf '%s' "$1" | sed 's/^FEAT-//') ))"; }

# --- запись record-файла (атомарно) ------------------------------------------

# _write_record <path> <feat> <branch> <repo> <status> <adr> <commit> <desc> <created> <updated>
# Собирает JSON через jq -n (валидный по построению) во временный файл рядом, mv на место.
_write_record() {
    _wr_path="$1"; shift
    _wr_feat="$1"; _wr_branch="$2"; _wr_repo="$3"; _wr_status="$4"
    _wr_adr="$5"; _wr_commit="$6"; _wr_desc="$7"; _wr_created="$8"; _wr_updated="$9"
    _wr_tmp="$(dirname "$_wr_path")/.$(basename "$_wr_path").tmp.$$"
    if ! jq -n \
        --arg feat "$_wr_feat" --arg branch "$_wr_branch" --arg repo "$_wr_repo" \
        --arg status "$_wr_status" --arg adr "$_wr_adr" --arg commit "$_wr_commit" \
        --arg desc "$_wr_desc" --arg created "$_wr_created" --arg updated "$_wr_updated" \
        '{feat:$feat, branch:$branch, repo:$repo, status:$status,
          adr:(if $adr=="" or $adr=="null" then null else $adr end),
          commit:$commit, desc:$desc, created:$created, updated:$updated}' \
        > "$_wr_tmp" 2>/dev/null; then
        rm -f "$_wr_tmp"
        die "не удалось собрать валидный JSON для $_wr_feat."
    fi
    mv "$_wr_tmp" "$_wr_path"
}

# --- render: генерация таблицы между маркерами -------------------------------

# _render_table — печатает содержимое таблицы (header+separator+строки) из map/*.json,
# отсортированных по числовому FEAT. Формат строки инвариантен для _feat_max:
#   лидирующий '| FEAT-NNN |' → grep '^\s*\|' + 'FEAT-[0-9]+' видит все номера.
_render_table() {
    printf '| FEAT | Ветка (клиентская репа) | Репо | Статус | Коммит | Что |\n'
    printf '|------|-------------------------|------|--------|--------|-----|\n'
    # сортировка по числовой части имени FEAT-NNN.json
    _rt_list=""
    for _rt_f in "$MAP_DIR"/FEAT-*.json; do
        [ -f "$_rt_f" ] || continue
        _rt_n="$(basename "$_rt_f" .json | sed 's/^FEAT-//')"
        case "$_rt_n" in ''|*[!0-9]*) continue ;; esac
        _rt_list="$_rt_list$(( 10#$_rt_n )) $_rt_f
"
    done
    [ -n "$_rt_list" ] || return 0
    printf '%s' "$_rt_list" | sort -n -k1,1 | while read -r _rt_key _rt_path; do
        [ -f "$_rt_path" ] || continue
        jq -r '"| \(.feat) | \(.branch) | \(.repo) | \(.status) | \(.commit) | \(.desc) |"' "$_rt_path"
    done
}

# _render — регенерирует секцию README между маркерами из record-файлов (tmp+mv).
_render() {
    [ -f "$README" ] || die "README не найден: $README"
    grep -qF "$MARK_BEGIN" "$README" || die "маркер '$MARK_BEGIN' в README не найден — сначала выполните: feat-map.sh migrate."
    grep -qF "$MARK_END" "$README"   || die "маркер '$MARK_END' в README не найден — таблица маппинга повреждена."
    _rn_table="$(_render_table)"
    _rn_tmp="$(dirname "$README")/.$(basename "$README").tmp.$$"
    # awk: до BEGIN включительно — как есть; между маркерами — сгенерированная таблица;
    # с END включительно — как есть. Тело таблицы передаём через переменную окружения.
    FEATMAP_BODY="$_rn_table" awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
        $0==b { print; print ENVIRON["FEATMAP_BODY"]; skip=1; next }
        $0==e { skip=0; print; next }
        skip==1 { next }
        { print }
    ' "$README" > "$_rn_tmp" || { rm -f "$_rn_tmp"; die "render: awk не смог перестроить README."; }
    mv "$_rn_tmp" "$README"
}

# --- локи --------------------------------------------------------------------
_BT_PID=""   # toucher booking
_ET_PID=""   # toucher edit-shared

_cleanup_locks() {
    [ -n "${_ET_PID:-}" ] && kill "$_ET_PID" 2>/dev/null
    coord_unlock edit-shared
    [ -n "${_BT_PID:-}" ] && kill "$_BT_PID" 2>/dev/null
    coord_unlock booking
}

# _acquire_locks <want_booking:0|1> — берёт локи в порядке booking → edit-shared,
# каждый длинный держатель — с toucher'ом. trap ставит вызывающий (диспетчер).
_acquire_locks() {
    if [ "$1" -eq 1 ]; then
        coord_lock booking 120 15 || die "не удалось захватить лок booking."
        coord_lock_toucher booking & _BT_PID=$!
    fi
    coord_lock edit-shared 120 15 || { _cleanup_locks; die "не удалось захватить лок edit-shared."; }
    coord_lock_toucher edit-shared & _ET_PID=$!
}

# _commit_map_and_readme <msg> — атомарный коммит записей + таблицы (ai-commit → shared-docs).
_commit_map_and_readme() {
    "$SCRIPT_DIR/ai-commit.sh" "$1" "$MAP_REL" "$README_REL"
}

# --- команды -----------------------------------------------------------------

cmd_add() {
    _feat=""; _branch=""; _repo=""; _status=""; _adr=""; _commit="—"; _desc=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --branch) _branch="${2:?ветка после --branch}"; shift 2 ;;
            --repo)   _repo="${2:?репа после --repo}"; shift 2 ;;
            --status) _status="${2:?статус после --status}"; shift 2 ;;
            --adr)    _adr="${2:?ADR после --adr}"; shift 2 ;;
            --commit) _commit="${2:?sha после --commit}"; shift 2 ;;
            --desc)   _desc="${2:?описание после --desc}"; shift 2 ;;
            -*) die "неизвестный флаг add: $1" ;;
            *) [ -z "$_feat" ] && _feat="$1" || die "лишний аргумент: $1"; shift ;;
        esac
    done
    [ -n "$_feat" ] || die "укажите FEAT-NNN: feat-map.sh add <FEAT-NNN> --branch .. --repo .. --status .. --desc .."
    _valid_feat "$_feat"; _valid_repo "$_repo"; _valid_status "$_status"
    _valid_adr "$_adr"; _valid_branch "$_branch"; _valid_desc "$_desc"
    [ -n "$_desc" ] || die "--desc обязателен."
    _rp="$MAP_DIR/$_feat.json"

    _acquire_locks 1
    trap '_cleanup_locks' EXIT INT TERM
    mkdir -p "$MAP_DIR"
    [ -e "$_rp" ] && { _cleanup_locks; trap - EXIT INT TERM; die "$_feat уже существует ($_rp) — номер занят, add не перезаписывает."; }
    _now="$(coord_now)"
    _write_record "$_rp" "$_feat" "$_branch" "$_repo" "$_status" "$_adr" "$_commit" "$_desc" "$_now" "$_now"
    _render
    _commit_map_and_readme "DOCS / feat-map / add $_feat"
    _crc=$?
    _cleanup_locks; trap - EXIT INT TERM
    [ "$_crc" -eq 0 ] && say "${_C_GRN}feat-map: добавлен $_feat${_C_RST}"
    return "$_crc"
}

cmd_reserve() {
    _range=""; _adr=""; _phase=""; _prefix=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --adr)         _adr="${2:?ADR после --adr}"; shift 2 ;;
            --phase)       _phase="${2:?фаза после --phase}"; shift 2 ;;
            --desc-prefix) _prefix="${2:?префикс после --desc-prefix}"; shift 2 ;;
            -*) die "неизвестный флаг reserve: $1" ;;
            *) [ -z "$_range" ] && _range="$1" || die "лишний аргумент: $1"; shift ;;
        esac
    done
    [ -n "$_range" ] || die "укажите диапазон: feat-map.sh reserve <FROM..TO> --adr <ADR-NNN> --phase \"<...>\""
    [ -n "$_adr" ] || die "--adr обязателен для reserve."
    _valid_adr "$_adr"
    printf '%s' "$_range" | grep -qE '^[0-9]{1,}\.\.[0-9]{1,}$' || die "диапазон '$_range' — ожидается FROM..TO (числа, напр. 030..035)."
    _from="$(( 10#${_range%%..*} ))"; _to="$(( 10#${_range##*..} ))"
    [ "$_from" -le "$_to" ] || die "диапазон пуст: FROM ($_from) > TO ($_to)."
    _pfx="${_prefix:-Зарезервировано планом $_adr}"
    _dsc="$_pfx${_phase:+ ($_phase)}"
    _valid_desc "$_dsc"

    _acquire_locks 1
    trap '_cleanup_locks' EXIT INT TERM
    mkdir -p "$MAP_DIR"

    # Шаг 1 — pre-check ВСЕГО диапазона ДО создания чего-либо (all-or-nothing).
    _n="$_from"
    while [ "$_n" -le "$_to" ]; do
        _f="$(printf 'FEAT-%03d' "$_n")"; _rp="$MAP_DIR/$_f.json"
        if [ -e "$_rp" ]; then
            _e_adr="$(jq -r '.adr // "null"' "$_rp" 2>/dev/null)"
            _e_st="$(jq -r '.status // ""' "$_rp" 2>/dev/null)"
            if [ "$_e_adr" != "$_adr" ] || [ "$_e_st" != "reserved" ]; then
                _cleanup_locks; trap - EXIT INT TERM
                die "$_f уже занят чужой/иной записью (adr=$_e_adr status=$_e_st) — диапазон недоступен, НИЧЕГО не создано."
            fi
        fi
        _n=$(( _n + 1 ))
    done

    # Шаг 2 — последовательные tmp+mv недостающих (свои существующие reserved — пропуск/докат).
    _now="$(coord_now)"
    _n="$_from"; _created_cnt=0; _kept_cnt=0
    while [ "$_n" -le "$_to" ]; do
        _f="$(printf 'FEAT-%03d' "$_n")"; _rp="$MAP_DIR/$_f.json"
        if [ -e "$_rp" ]; then
            _kept_cnt=$(( _kept_cnt + 1 ))
        else
            _write_record "$_rp" "$_f" "—" "$AI_REPO_NAME" "reserved" "$_adr" "—" "$_dsc" "$_now" "$_now"
            _created_cnt=$(( _created_cnt + 1 ))
        fi
        _n=$(( _n + 1 ))
    done

    # Шаг 3 — render + коммит в той же обёртке.
    _render
    _commit_map_and_readme "DOCS / feat-map / reserve $_range для $_adr"
    _crc=$?
    _cleanup_locks; trap - EXIT INT TERM
    [ "$_crc" -eq 0 ] && say "${_C_GRN}feat-map: reserve $_range ($_adr) — создано $_created_cnt, признано своих $_kept_cnt${_C_RST}"
    return "$_crc"
}

cmd_set() {
    _feat=""; _status=""; _branch=""; _commit=""; _desc=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --status) _status="${2:?статус после --status}"; shift 2 ;;
            --branch) _branch="${2:?ветка после --branch}"; shift 2 ;;
            --commit) _commit="${2:?sha после --commit}"; shift 2 ;;
            --desc)   _desc="${2:?описание после --desc}"; shift 2 ;;
            -*) die "неизвестный флаг set: $1" ;;
            *) [ -z "$_feat" ] && _feat="$1" || die "лишний аргумент: $1"; shift ;;
        esac
    done
    [ -n "$_feat" ] || die "укажите FEAT-NNN: feat-map.sh set <FEAT-NNN> --status <s> [--branch b] [--commit sha]"
    _valid_feat "$_feat"
    _rp="$MAP_DIR/$_feat.json"
    [ -e "$_rp" ] || die "$_feat нет ($_rp) — set меняет существующую запись; создайте её через add/reserve."
    [ -n "$_status" ] && _valid_status "$_status"
    [ -n "$_branch" ] && _valid_branch "$_branch"
    [ -n "$_desc" ] && _valid_desc "$_desc"

    _acquire_locks 0
    trap '_cleanup_locks' EXIT INT TERM
    _now="$(coord_now)"
    _tmp="$(dirname "$_rp")/.$(basename "$_rp").tmp.$$"
    if ! jq \
        --arg s "$_status" --arg b "$_branch" --arg c "$_commit" --arg d "$_desc" --arg u "$_now" \
        '(if $s!="" then .status=$s else . end)
         | (if $b!="" then .branch=$b else . end)
         | (if $c!="" then .commit=$c else . end)
         | (if $d!="" then .desc=$d else . end)
         | .updated=$u' "$_rp" > "$_tmp" 2>/dev/null; then
        rm -f "$_tmp"; _cleanup_locks; trap - EXIT INT TERM
        die "не удалось обновить запись $_feat (jq)."
    fi
    mv "$_tmp" "$_rp"
    _render
    _commit_map_and_readme "DOCS / feat-map / set $_feat"
    _crc=$?
    _cleanup_locks; trap - EXIT INT TERM
    [ "$_crc" -eq 0 ] && say "${_C_GRN}feat-map: обновлён $_feat${_C_RST}"
    return "$_crc"
}

cmd_render() {
    _acquire_locks 0
    trap '_cleanup_locks' EXIT INT TERM
    _render
    _commit_map_and_readme "DOCS / feat-map / render"
    _crc=$?
    _cleanup_locks; trap - EXIT INT TERM
    [ "$_crc" -eq 0 ] && say "${_C_GRN}feat-map: таблица перегенерирована${_C_RST}"
    return "$_crc"
}

# migrate — разовый шаг: маркеры вокруг существующей ручной таблицы + посев map/ из
# текущих строк (статусы КАК ЕСТЬ), затем render. Повторный запуск — die (маркеры есть).
cmd_migrate() {
    [ -f "$README" ] || die "README не найден: $README"
    grep -qF "$MARK_BEGIN" "$README" && die "маркеры FEAT-MAP уже присутствуют в README — миграция уже выполнена (повторный migrate запрещён; используйте render)."

    _acquire_locks 1
    trap '_cleanup_locks' EXIT INT TERM
    mkdir -p "$MAP_DIR"

    # ВСЁ чтение README — ПОД локом (против TOCTOU). Повторная проверка маркеров.
    grep -qF "$MARK_BEGIN" "$README" && { _cleanup_locks; trap - EXIT INT TERM; die "маркеры появились под локом — миграция уже выполнена конкурентно."; }
    _hdr_ln="$(grep -nE '^\| FEAT \|' "$README" | head -1 | cut -d: -f1)"
    [ -n "$_hdr_ln" ] || { _cleanup_locks; trap - EXIT INT TERM; die "не найдена строка-заголовок таблицы '| FEAT |' в README — нечего мигрировать."; }
    _last_ln="$(grep -nE '^\| FEAT-[0-9]' "$README" | tail -1 | cut -d: -f1)"
    [ -n "$_last_ln" ] || { _cleanup_locks; trap - EXIT INT TERM; die "не найдено ни одной строки данных '| FEAT-NNN |' в README."; }
    [ "$_last_ln" -ge "$_hdr_ln" ] || { _cleanup_locks; trap - EXIT INT TERM; die "порядок строк таблицы нарушен (заголовок $_hdr_ln, последняя данных $_last_ln)."; }

    # Посев record-файлов из строк данных.
    _now="$(coord_now)"
    _seeded=0
    while IFS= read -r _line; do
        case "$_line" in "| FEAT-"*) : ;; *) continue ;; esac
        _feat="$(printf '%s' "$_line"   | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')"
        _branch="$(printf '%s' "$_line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$3); print $3}')"
        _repo="$(printf '%s' "$_line"   | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$4); print $4}')"
        _status="$(printf '%s' "$_line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$5); print $5}')"
        _commit="$(printf '%s' "$_line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$6); print $6}')"
        _desc="$(printf '%s' "$_line"   | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$7); print $7}')"
        case "$_feat" in FEAT-[0-9]*) : ;; *) continue ;; esac
        # ADAPT: эвристика привязки ADR при посеве — по умолчанию пусто (заполните при желании).
        _adr=""
        _write_record "$MAP_DIR/$_feat.json" "$_feat" "$_branch" "$_repo" "$_status" "$_adr" "$_commit" "$_desc" "$_now" "$_now"
        _seeded=$(( _seeded + 1 ))
    done < "$README"

    # Вставка маркеров: BEGIN перед заголовком, END после последней строки данных.
    _mg_tmp="$(dirname "$README")/.$(basename "$README").tmp.$$"
    awk -v hdr="$_hdr_ln" -v last="$_last_ln" -v b="$MARK_BEGIN" -v e="$MARK_END" '
        NR==hdr { print b }
        { print }
        NR==last { print e }
    ' "$README" > "$_mg_tmp" || { rm -f "$_mg_tmp"; _cleanup_locks; trap - EXIT INT TERM; die "migrate: awk не смог вставить маркеры."; }
    mv "$_mg_tmp" "$README"

    _render
    _commit_map_and_readme "DOCS / feat-map / migrate: маркеры + посев map/ ($_seeded записей)"
    _crc=$?
    _cleanup_locks; trap - EXIT INT TERM
    [ "$_crc" -eq 0 ] && say "${_C_GRN}feat-map: миграция выполнена — посеяно $_seeded записей, таблица генерируется${_C_RST}"
    return "$_crc"
}

# --- диспетчер ----------------------------------------------------------------
cmd="${1:-}"; [ "$#" -gt 0 ] && shift
case "$cmd" in
    add)     cmd_add "$@" ;;
    reserve) cmd_reserve "$@" ;;
    set)     cmd_set "$@" ;;
    render)  cmd_render "$@" ;;
    migrate) cmd_migrate "$@" ;;
    -h|--help|'') grep '^#' "$0" | sed 's/^# \{0,1\}//' ;;
    *) die "неизвестная команда: $cmd (add|reserve|set|render|migrate)" ;;
esac
