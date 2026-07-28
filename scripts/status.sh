#!/usr/bin/env bash
# status.sh — панель состояния workspace БЕЗ сетевых операций (никакого fetch).
# Показывает по локальным данным: базовые ветки, task-ветки (behind/ahead/delivered/merged),
# чистоту каждого worktree, незакоммиченные изменения корневого репо артефактов, недоставленные ветки.
# Компактно, читается и человеком, и агентом.
#
# GENERIC-КОПИЯ. Ноль сети. Тексты про «корневой репо артефактов» — параметр.
#
# Флаги:
#   --write   дополнительно пересобрать ai/state.json (по локальным данным).
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
: "${WS_ROOT:=$(dirname "$SCRIPT_DIR")}"
. "$SCRIPT_DIR/lib/workspace.sh"
. "$SCRIPT_DIR/lib/state.sh"

WRITE=0
for a in "$@"; do
    case "$a" in
        --write)   WRITE=1 ;;
        -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) printf '%sНеизвестный флаг: %s%s\n' "$WS_RED" "$a" "$WS_RST" >&2; exit 2 ;;
    esac
done

head_line() { printf '%s== %s ==%s\n' "$WS_BLD" "$*" "$WS_RST"; }
hr() { printf '%s\n' "------------------------------------------------------------------------"; }

# dirty <worktree> — печатает "чистый" или "грязный (N)".
wt_dirty() {
    [ -d "$1" ] || { printf 'нет'; return; }
    _n="$(git -C "$1" status --porcelain 2>/dev/null | grep -c .)"
    if [ "${_n:-0}" -eq 0 ]; then printf '%sчистый%s' "$WS_GRN" "$WS_RST"
    else printf '%sгрязный (%s)%s' "$WS_YEL" "$_n" "$WS_RST"; fi
}

# ---------------------------------------------------------------------------
# 0. Координация: агенты онлайн + брони (coord_reap внутри)
# ---------------------------------------------------------------------------
if [ -x "$SCRIPT_DIR/coord.sh" ]; then
    "$SCRIPT_DIR/coord.sh" agents
    echo
    "$SCRIPT_DIR/coord.sh" board
    echo
fi

# ---------------------------------------------------------------------------
# 1. Репы и основные worktree
# ---------------------------------------------------------------------------
head_line "репозитории (локальные данные, без fetch)"
RFMT='  %-18s %-6s %-12s %-14s %s\n'
# shellcheck disable=SC2059
printf "$RFMT" "РЕПА" "ТИП" "БАЗА" "behind" "worktree"
hr
UNDELIVERED=0
while IFS= read -r line || [ -n "$line" ]; do
    name="$(ws_name "$line")"; type="$(ws_type "$line")"
    base="$(ws_base "$line")"; wt="$(ws_mainwt_abs "$line")"; gd="$(ws_gitdir "$line")"
    ab="$(ws_ahead_behind "$gd" "$base" "$base")"
    behind="$(printf '%s' "$ab" | awk -F'\t' '{print $1}')"
    ahead="$(printf '%s'  "$ab" | awk -F'\t' '{print $2}')"
    bcell="$behind"
    [ "${ahead:-0}" != "0" ] && [ "${ahead:-0}" != "?" ] && bcell="$behind (ahead $ahead!)"
    # shellcheck disable=SC2059
    printf "$RFMT" "$name" "$type" "$base" "$bcell" "$(wt_dirty "$wt")"
done <<EOF
$(ws_conf_lines)
EOF

# ---------------------------------------------------------------------------
# 2. Task-ветки
# ---------------------------------------------------------------------------
echo; head_line "task-ветки"
TFMT='  %-34s %-14s %-10s %-10s %-8s %s\n'
# shellcheck disable=SC2059
printf "$TFMT" "ВЕТКА" "FEAT" "beh/ahd" "delivered" "merged" "worktree"
hr
TASK_TOTAL=0
while IFS= read -r line || [ -n "$line" ]; do
    [ "$(ws_type "$line")" = "bare" ] || continue
    name="$(ws_name "$line")"; base="$(ws_base "$line")"; gd="$(ws_gitdir "$line")"
    while IFS="$(printf '\t')" read -r twt tbr || [ -n "$twt" ]; do
        [ -n "$twt" ] || continue
        TASK_TOTAL=$((TASK_TOTAL+1))
        slug="$(ws_slug "$twt")"
        ab="$(ws_ahead_behind "$gd" "$tbr" "$base")"
        behind="$(printf '%s' "$ab" | awk -F'\t' '{print $1}')"
        ahead="$(printf '%s'  "$ab" | awk -F'\t' '{print $2}')"
        ws_delivered "$gd" "$tbr"; deliv=$?
        ws_merged "$gd" "$tbr" "$base"; mrg=$?
        feat="$(ws_state_feat "$name" "$slug")"; [ -n "$feat" ] || feat="-"
        d_txt="no"; [ "$deliv" -eq 0 ] && d_txt="yes"
        m_txt="no"; [ "$mrg" -eq 0 ] && m_txt="yes"
        [ "$deliv" -ne 0 ] && UNDELIVERED=$((UNDELIVERED+1))
        # shellcheck disable=SC2059
        printf "$TFMT" "$tbr" "$feat" "$behind/$ahead" "$d_txt" "$m_txt" "$(wt_dirty "$twt")"
    done <<EOF
$(ws_task_worktrees "$line")
EOF
done <<EOF
$(ws_conf_lines)
EOF
hr
[ "$TASK_TOTAL" -eq 0 ] && printf '  (task-веток нет)\n'

# ---------------------------------------------------------------------------
# 3. Корневой репозиторий артефактов
# ---------------------------------------------------------------------------
echo; head_line "корневой репозиторий (артефакты знаний)"
root_n="$(git -C "$WS_ROOT" status --porcelain 2>/dev/null | grep -c .)"
root_branch="$(git -C "$WS_ROOT" symbolic-ref --short HEAD 2>/dev/null || echo '?')"
if git -C "$WS_ROOT" rev-parse HEAD >/dev/null 2>&1; then
    root_head="$(git -C "$WS_ROOT" rev-parse --short HEAD)"
else
    root_head="БЕЗ КОММИТОВ"
fi
printf '  ветка %s, HEAD %s\n' "$root_branch" "$root_head"
if [ "${root_n:-0}" -eq 0 ]; then
    printf '%s  рабочее дерево чистое%s\n' "$WS_GRN" "$WS_RST"
else
    printf '%s  незакоммиченных изменений: %s (публикация: scripts/ai-push.sh)%s\n' \
        "$WS_YEL" "$root_n" "$WS_RST"
fi

# ---------------------------------------------------------------------------
# 4. Напоминания
# ---------------------------------------------------------------------------
echo; head_line "напоминания"
if [ "$UNDELIVERED" -gt 0 ]; then
    printf '%s  недоставленных task-веток: %s — доставка: пользователь через scripts/deliver.sh%s\n' \
        "$WS_YEL" "$UNDELIVERED" "$WS_RST"
else
    printf '%s  все task-ветки доставлены%s\n' "$WS_GRN" "$WS_RST"
fi
printf '  входящие изменения: scripts/sync.sh  |  уборка merged: scripts/sync.sh --cleanup\n'

if [ "$WRITE" -eq 1 ]; then
    echo; ws_state_migrate
    if ws_state_write; then
        printf '%sstate.json обновлён: %s%s\n' "$WS_GRN" "$(ws_state_target)" "$WS_RST"
    fi
fi
