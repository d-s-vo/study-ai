#!/usr/bin/env bash
# commit.sh — человекочитаемая обёртка коммита для КЛИЕНТСКИХ worktree (МОДУЛЬ M1/M6).
# Гоняет тот же сканер, что и хуки, ДО коммита и даёт понятный отчёт.
# Тесты/гейты — НЕ здесь (это зона процесса ai/: тесты/typecheck/lint через gate.sh), здесь только чистота следов.
#
# При M6=OFF (внутренний проект, ИИ официально принят) вырождается в тонкую обёртку над
# git commit БЕЗ стоп-скана и БЕЗ FORMAT_RE (агент-развёртыватель убирает шаги 1-3).
#
# Usage:
#   commit.sh <message>                       # из cwd = worktree
#   commit.sh <worktree-path> <message>
#
# ФОРМАТ СООБЩЕНИЯ — контракт команды заказчика. ⚠ ИСТОЧНИК ИСТИНЫ формата — ЗДЕСЬ (FORMAT_RE).
# # ADAPT: conventional commits — тип: feat|fix|chore|refactor|docs|test|style|perf|build|ci,
#   опциональный (scope) и '!', затем ': ' и описание. Напр. 'feat(recipe): импорт рецептов'.
# Обход формата (репы со свободными сообщениями): COMMIT_ALLOW_FREEFORM=1 commit.sh ...
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"     # .../scripts
WS_ROOT="$(dirname "$SCRIPT_DIR")"                                 # корень workspace
. "$WS_ROOT/githooks/lib/scan.sh"

say() { printf '%s\n' "$*" >&2; }

# --- разбор аргументов ---
if [ "$#" -ge 2 ] && [ -d "$1" ]; then
    WT="$(cd "$1" && pwd)"; shift
    MSG="$1"
elif [ "$#" -ge 1 ]; then
    WT="$(pwd)"
    MSG="$1"
else
    say "Usage: commit.sh [<worktree-path>] <message>"; exit 2
fi

cd "$WT" || { say "Не удалось перейти в $WT"; exit 2; }
git rev-parse --git-dir >/dev/null 2>&1 || { say "$WT — не git worktree"; exit 2; }

fail=0

# 1. ~wip~ в staged (доп. быстрая проверка; хук всё равно продублирует).
if git diff --cached --no-color 2>/dev/null | grep -E '^\+' | grep -viE '^\+\+\+' \
     | grep -qiE '~[[:space:]]*wip[[:space:]]*~'; then
    say "ОТЧЁТ: найден маркер ~wip~ в staged-изменениях — коммитить нельзя."
    fail=1
fi

# 2. Полный скан staged-диффа по стоп-словарю.
report="$(git diff --cached --no-color 2>/dev/null \
            | grep -E '^\+' | grep -vE '^\+\+\+' | sed 's/^+//' \
            | scan_stream)"
if [ -n "$report" ]; then
    say "ОТЧЁТ: стоп-слова в staged-диффе:"
    printf '%s\n' "$report" >&2
    fail=1
fi

# 2b. Скан сообщения коммита.
msg_report="$(scan_string "$MSG")"
if [ -n "$msg_report" ]; then
    say "ОТЧЁТ: стоп-слова в сообщении коммита:"
    printf '%s\n' "$msg_report" >&2
    fail=1
fi

# 3. Формат сообщения.
# Один префикс или несколько через запятую: "FRONT / ..." | "FRONT, TEST / FIX / ..."
FORMAT_RE='^(feat|fix|chore|refactor|docs|test|style|perf|build|ci)(\([a-z0-9_-]+\))?!?: .+'
if [ "${COMMIT_ALLOW_FREEFORM:-0}" != "1" ]; then
    if ! printf '%s\n' "$MSG" | grep -qE -- "$FORMAT_RE"; then
        say "ОТЧЁТ: сообщение не соответствует conventional-формату '<тип>(scope)?: описание'."
        say "       тип: feat|fix|chore|refactor|docs|test|style|perf|build|ci."
        say "       Пример: 'feat(recipe): добавить импорт рецептов'."
        say "       Свободный формат: COMMIT_ALLOW_FREEFORM=1."
        fail=1
    fi
fi

if [ "$fail" -ne 0 ]; then
    say ""
    say "Коммит НЕ выполнен: устраните замечания выше."
    exit 1
fi

# 4. Собственно коммит (хуки повторно проверят как страховку).
git commit -m "$MSG"
