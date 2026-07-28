#!/usr/bin/env bash
# ai-commit.sh — коммит в КОРНЕВОЙ внутренний репозиторий (зона артефактов знаний) строго
# СВОЕЙ зоны (по путям). Под coord-локом shared-docs: git add -- <пути> && git commit -m <msg> -- <пути>.
# Пути ОБЯЗАТЕЛЬНЫ; коммитятся ровно указанные pathspec'и (чужие staged-изменения не
# попадают — git commit с pathspec их игнорирует). Публикация — отдельно (ai-push.sh).
#
# GENERIC-КОПИЯ: безопасный коммит своей зоны в общем репо артефактов при параллельных агентах.
#
# Использование:
#   ai-commit.sh "<сообщение>" <путь>...
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
: "${WS_ROOT:=$(dirname "$SCRIPT_DIR")}"
. "$SCRIPT_DIR/lib/coord.sh"

die() { printf '%sОШИБКА: %s%s\n' "$_C_RED" "$*" "$_C_RST" >&2; exit 1; }
say() { printf '%s\n' "$*"; }

MSG="${1:-}"
[ -n "$MSG" ] || die "первый аргумент — сообщение коммита."
shift
[ "$#" -gt 0 ] || die "укажите хотя бы один путь для коммита (только своя зона)."

cd "$WS_ROOT" || die "не удалось перейти в $WS_ROOT"
git rev-parse --git-dir >/dev/null 2>&1 || die "$WS_ROOT — не git-репозиторий."

# проверка: среди путей есть хотя бы один существующий (файл/каталог).
_have=0
for _p in "$@"; do
    [ -e "$WS_ROOT/$_p" ] || [ -e "$_p" ] && { _have=1; break; }
done
[ "$_have" -eq 1 ] || die "ни один из указанных путей не существует — коммитить нечего."

coord_lock shared-docs || die "не удалось захватить лок shared-docs."
trap 'coord_unlock shared-docs' EXIT INT TERM

# add + commit строго по указанным pathspec'ам.
if ! git add -- "$@" 2>/dev/null; then
    coord_unlock shared-docs; trap - EXIT INT TERM
    die "git add по указанным путям не удался."
fi

# есть ли что коммитить по этим путям?
if git diff --cached --quiet -- "$@" 2>/dev/null; then
    coord_unlock shared-docs; trap - EXIT INT TERM
    say "${_C_YEL}Нет изменений по указанным путям — коммит не требуется.${_C_RST}"
    exit 0
fi

if git commit -m "$MSG" -- "$@"; then
    coord_unlock shared-docs; trap - EXIT INT TERM
    say "${_C_GRN}Закоммичено в зону артефактов (своя зона): $MSG${_C_RST}"
    say "  публикация — ./scripts/ai-push.sh (не забудьте)."
else
    coord_unlock shared-docs; trap - EXIT INT TERM
    die "git commit не удался (см. вывод выше — возможно, сработали хуки/сканер)."
fi
