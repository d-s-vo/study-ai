#!/usr/bin/env bash
# Управление task-worktree: каждая задача = своя ветка <prefix><slug> = своя папка tasks/<slug>.
# Репа и базовая ветка берутся из scripts/repos.conf (ноль хардкода).
#
# GENERIC-КОПИЯ. Имеет смысл только для bare+worktree модели (изоляция параллельных задач).
#
# Использование:
#   task.sh [--repo <имя>] new <slug> [базовая-ветка]  # ветка <prefix><slug> + worktree от базы
#   task.sh [--repo <имя>] add <ветка>                  # worktree на существующую ветку
#   task.sh [--repo <имя>] rm  <имя-папки>              # удалить worktree (ветка остаётся)
#   task.sh [--repo <имя>] ls                           # список worktree
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
WS_ROOT="$(dirname "$SCRIPT_DIR")"
. "$SCRIPT_DIR/lib/workspace.sh"
. "$SCRIPT_DIR/lib/coord.sh"
. "$WS_ROOT/githooks/lib/scan.sh"

TASKS="$TASKS_ROOT"
# cbook — имя репы по умолчанию (из repos.conf), когда --repo не задан.
REPO="cbook"
# ADAPT: префикс task-ветки (по умолчанию feat/) — ДОЛЖЕН совпадать с coord.sh. См. stack-specifics.md.
BRANCH_PREFIX="${TASK_BRANCH_PREFIX:-feat/}"

# --- разбор --repo (в любом месте до/после команды) ---
ARGS=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --repo) REPO="${2:?имя репы после --repo}"; shift 2 ;;
        --repo=*) REPO="${1#--repo=}"; shift ;;
        *) ARGS="$ARGS $1"; shift ;;
    esac
done
# shellcheck disable=SC2086
set -- $ARGS

# --- найти строку конфига для REPO ---
CONF_LINE="$(ws_conf_lines | while IFS= read -r l; do
    [ "$(ws_name "$l")" = "$REPO" ] && printf '%s' "$l" && break
done)"
[ -n "$CONF_LINE" ] || { echo "Репа '$REPO' не найдена в repos.conf" >&2; exit 1; }
[ "$(ws_type "$CONF_LINE")" = "bare" ] || {
    echo "Репа '$REPO' не bare — task-worktree не поддерживаются." >&2; exit 1; }

BARE="$(ws_gitdir "$CONF_LINE")"
DEFAULT_BASE="$(ws_base "$CONF_LINE")"

# validate_slug <slug> — только [a-z0-9-], без стоп-слов (прогон через сканер).
validate_slug() {
    _sl="$1"
    if ! printf '%s' "$_sl" | grep -qE '^[a-z0-9-]+$'; then
        echo "Недопустимый slug '$_sl': разрешены только [a-z0-9-]." >&2; exit 1
    fi
    _rep="$(scan_string "$_sl" || true)"
    if [ -n "$_rep" ]; then
        echo "Slug '$_sl' содержит стоп-слово — имя ветки под запретом:" >&2
        printf '%s\n' "$_rep" >&2
        exit 1
    fi
}

cmd="${1:?команда: new|add|rm|ls}"
case "$cmd" in
    new)
        name="${2:?имя задачи}"
        base="${3:-$DEFAULT_BASE}"
        validate_slug "$name"
        # --- координация: бронь на slug ---
        _bk="$COORD_BOOKINGS/$name.json"
        if [ -f "$_bk" ]; then
            _bagent="$(jq -r '.agent // empty' "$_bk" 2>/dev/null)"
            _mine="$(coord_session)"
            if [ -n "$_bagent" ] && [ "$_bagent" != "$_mine" ] && [ -f "$COORD_AGENTS/$_bagent.json" ]; then
                echo "ОТКАЗ: slug '$name' забронирован живым агентом '$_bagent'." >&2
                echo "       Согласуйте с ним или выберите другой slug (./scripts/coord.sh board)." >&2
                exit 1
            fi
        else
            printf 'ПРЕДУПРЕЖДЕНИЕ: брони на "%s" нет. Рекомендуется: ./scripts/coord.sh book %s\n' \
                "$name" "$name" >&2
            printf '                (продолжаю — обратная совместимость; без брони нет изоляции портов/БД).\n' >&2
        fi
        branch="$BRANCH_PREFIX$name"
        git -C "$BARE" fetch origin "$base"
        git -C "$BARE" worktree add -b "$branch" "$TASKS/$name" "origin/$base"
        echo "Создано: $TASKS/$name (ветка $branch от $base, репа $REPO)"
        ;;
    add)
        branch="${2:?имя ветки}"
        name="$(echo "$branch" | tr '/' '-')"
        validate_slug "$name"
        git -C "$BARE" fetch origin "$branch" || true
        git -C "$BARE" worktree add "$TASKS/$name" "$branch"
        echo "Создано: $TASKS/$name (ветка $branch, репа $REPO)"
        ;;
    rm)
        name="${2:?имя папки}"
        git -C "$BARE" worktree remove "$TASKS/$name"
        echo "Удалено: $TASKS/$name (репа $REPO)"
        ;;
    ls)
        git -C "$BARE" worktree list
        ;;
    *)
        echo "Неизвестная команда: $cmd (new|add|rm|ls)" >&2; exit 1
        ;;
esac
