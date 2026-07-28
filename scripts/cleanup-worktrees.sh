#!/usr/bin/env bash
# cleanup-worktrees.sh — идемпотентная уборка merged task-worktree.
#
# В ЭТОМ ШАБЛОНЕ реальная уборка живёт в `sync.sh --cleanup` (единый проход по repos.conf с
# теми же гвардами: не трогаем locked / грязные / «свежие» <FRESH_HOURS worktree; удаляем
# ТОЛЬКО влитые в origin/<base>; перенос брони merged → archive/). Этот файл — тонкая обёртка
# для привычного вызова и --dry-run.
#
# Запускает уборку ОРКЕСТРАТОР после подтверждённого merge КАЖДОЙ фичи. Субагент свой worktree
# НЕ убирает — он в нём живёт (уборка = зона оркестратора). См. ai/guides/adr-execution.md
# (Часть H) и ai/guides/feature-workflow.md (Шаг 12).
#
# Использование:
#   cleanup-worktrees.sh            # = sync.sh --cleanup (реально убрать merged)
#   cleanup-worktrees.sh --dry-run  # показать предписания уборки без изменений (= sync.sh)
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

case "${1:-}" in
    --dry-run)
        # sync.sh без --cleanup печатает предписания (что было бы убрано), ничего не удаляя.
        exec "$SCRIPT_DIR/sync.sh" --no-fetch
        ;;
    -h|--help)
        grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0
        ;;
    '')
        exec "$SCRIPT_DIR/sync.sh" --cleanup --no-fetch
        ;;
    *)
        printf 'Неизвестный флаг: %s (допустимо: --dry-run)\n' "$1" >&2; exit 2
        ;;
esac
