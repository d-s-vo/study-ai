#!/usr/bin/env bash
# state.sh — генерация ai/state.json (машиночитаемый снимок состояния слоя синхронизации).
# Источится (source) из sync.sh / status.sh --write. bash 3.2, JSON руками (printf).
# Имена реп/веток ограничены [a-z0-9-/], экранирование не требуется.
#
# GENERIC-КОПИЯ шаблона. Деградирует безопасно: без таблицы FEAT (M2/M6 OFF) поле feat
# просто пустое (ws_state_feat → return 0).
#
# Функции:
#   ws_state_target        — путь целевого файла state.json
#   ws_state_write         — собрать и записать JSON, вернуть 0/1
#   ws_state_migrate       — перенести временный .state.json в ai/state.json, если ai/ появился

# Библиотека workspace обязана быть уже подключена; подстрахуемся.
if ! command -v ws_conf_lines >/dev/null 2>&1; then
    _st_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
    . "$_st_dir/workspace.sh"
fi

# ws_state_target — где лежит state.json.
#   STATE_FILE      — явное переопределение (используется в тестах, чтобы не трогать ai/).
#   каталог ai/ есть → ai/state.json (штатное место).
#   каталога ai/ нет → временный .state.json в корне (зону ai/ создавать нельзя).
ws_state_target() {
    if [ -n "${STATE_FILE:-}" ]; then
        printf '%s\n' "$STATE_FILE"; return 0
    fi
    if [ -d "$WS_ROOT/ai" ]; then
        printf '%s\n' "$WS_ROOT/ai/state.json"
    else
        printf '%s\n' "$WS_ROOT/.state.json"
    fi
}

# ws_state_migrate — если есть временный .state.json и появился каталог ai/ — перенести.
ws_state_migrate() {
    [ -z "${STATE_FILE:-}" ] || return 0
    if [ -f "$WS_ROOT/.state.json" ] && [ -d "$WS_ROOT/ai" ]; then
        if mv "$WS_ROOT/.state.json" "$WS_ROOT/ai/state.json" 2>/dev/null; then
            printf 'state: перенесён .state.json -> ai/state.json\n' >&2
        fi
    fi
}

# _st_bool <0/1-код> — печатает true/false из кода возврата ($1=0 -> true).
_st_bool() { [ "$1" -eq 0 ] && printf 'true' || printf 'false'; }

# ws_state_feat <repo> <slug> — маппинг ветки на FEAT-NNN из таблицы
# ai/devlog/features/README.md (§ «Маппинг FEAT-NNN ↔ ветка»). Единый источник правды.
# Формат строки таблицы: | FEAT-NNN | `feat/<slug>` | <repo> | ... |
# Возвращает FEAT-NNN или пусто (нет соответствия / нет README / проект без FEAT-нумерации).
ws_state_feat() {
    _st_feat_repo="$1"; _st_feat_slug="$2"
    _st_feat_readme="$WS_ROOT/ai/devlog/features/README.md"
    [ -f "$_st_feat_readme" ] || return 0
    awk -F'|' -v repo="$_st_feat_repo" -v slug="$_st_feat_slug" '
        /FEAT-[0-9]/ && NF >= 4 {
            f=$2; br=$3; rp=$4
            gsub(/[ \t`]/,"",f); gsub(/[ \t`]/,"",br); gsub(/[ \t]/,"",rp)
            if (f !~ /^FEAT-[0-9]+$/) next
            bslug=br; sub(/^feat\//,"",bslug)
            if ((bslug==slug || br==slug) && (rp=="" || repo=="" || rp==repo)) {
                print f; exit
            }
        }
    ' "$_st_feat_readme"
}

# ws_state_write — собрать JSON по repos.conf и записать в целевой файл.
ws_state_write() {
    _st_target="$(ws_state_target)"
    _st_tmp="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/state.$$")"
    _st_now="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

    {
        printf '{\n'
        printf '  "updated": "%s",\n' "$_st_now"
        printf '  "repos": {\n'

        _st_first_repo=1
        while IFS= read -r _st_line || [ -n "$_st_line" ]; do
            _st_name="$(ws_name "$_st_line")"
            _st_type="$(ws_type "$_st_line")"
            _st_base="$(ws_base "$_st_line")"
            _st_gd="$(ws_gitdir "$_st_line")"
            _st_wt="$(ws_mainwt_abs "$_st_line")"

            [ "$_st_first_repo" -eq 1 ] || printf ',\n'
            _st_first_repo=0

            # база: локальный и origin hash + behind локальной базовой ветки
            _st_bl="$(ws_head "$_st_gd" "$_st_base")"
            _st_bo="$(ws_head "$_st_gd" "origin/$_st_base")"
            _st_ab="$(ws_ahead_behind "$_st_gd" "$_st_base" "$_st_base")"
            # behind = левое поле (коммиты origin/base, которых нет в локальной base)
            _st_behind="$(printf '%s' "$_st_ab" | awk -F'\t' '{print $1}')"

            printf '    "%s": {\n' "$_st_name"
            printf '      "type": "%s",\n' "$_st_type"
            printf '      "base": "%s",\n' "$_st_base"
            printf '      "base_local": "%s",\n' "$_st_bl"
            printf '      "base_origin": "%s",\n' "$_st_bo"
            printf '      "behind": %s,\n' "${_st_behind:-0}"
            printf '      "tasks": {'

            # задачи только у bare
            _st_first_task=1
            if [ "$_st_type" = "bare" ]; then
                while IFS="$(printf '\t')" read -r _st_twt _st_tbr || [ -n "$_st_twt" ]; do
                    [ -n "$_st_twt" ] || continue
                    _st_slug="$(ws_slug "$_st_twt")"
                    _st_thead="$(ws_head "$_st_gd" "$_st_tbr")"
                    _st_tab="$(ws_ahead_behind "$_st_gd" "$_st_tbr" "$_st_base")"
                    _st_tbehind="$(printf '%s' "$_st_tab" | awk -F'\t' '{print $1}')"
                    _st_tahead="$(printf '%s' "$_st_tab" | awk -F'\t' '{print $2}')"
                    ws_delivered "$_st_gd" "$_st_tbr"; _st_deliv=$?
                    ws_merged "$_st_gd" "$_st_tbr" "$_st_base"; _st_mrg=$?
                    _st_feat="$(ws_state_feat "$_st_name" "$_st_slug")"

                    [ "$_st_first_task" -eq 1 ] && printf '\n' || printf ',\n'
                    _st_first_task=0
                    printf '        "%s": {\n' "$_st_slug"
                    printf '          "branch": "%s",\n' "$_st_tbr"
                    printf '          "head": "%s",\n' "$_st_thead"
                    if [ -n "$_st_feat" ]; then
                        printf '          "feat": "%s",\n' "$_st_feat"
                    fi
                    printf '          "ahead": %s,\n' "${_st_tahead:-0}"
                    printf '          "behind": %s,\n' "${_st_tbehind:-0}"
                    printf '          "delivered": %s,\n' "$(_st_bool "$_st_deliv")"
                    printf '          "merged": %s\n' "$(_st_bool "$_st_mrg")"
                    printf '        }'
                done <<EOF
$(ws_task_worktrees "$_st_line")
EOF
            fi

            [ "$_st_first_task" -eq 1 ] && printf '}\n' || printf '\n      }\n'
            printf '    }'
        done <<EOF
$(ws_conf_lines)
EOF

        printf '\n  }\n'
        printf '}\n'
    } > "$_st_tmp"

    # валидация, если есть jq
    if command -v jq >/dev/null 2>&1; then
        if ! jq -e . "$_st_tmp" >/dev/null 2>&1; then
            printf 'state: собранный JSON невалиден, запись отменена\n' >&2
            rm -f "$_st_tmp"; return 1
        fi
    fi

    mv "$_st_tmp" "$_st_target" 2>/dev/null || { rm -f "$_st_tmp"; return 1; }

    if [ "$_st_target" = "$WS_ROOT/.state.json" ]; then
        printf 'ПРЕДУПРЕЖДЕНИЕ: каталога ai/ нет — состояние записано во временный %s\n' \
            "$_st_target" >&2
        printf '               sync.sh перенесёт его в ai/state.json, как только ai/ появится.\n' >&2
    fi
    return 0
}
