#!/usr/bin/env bash
# ai-push.sh — публикация корневого репозитория артефактов знаний во ВНУТРЕННИЙ remote.
# ЕДИНСТВЕННЫЙ канал пуша для агентов (клиентские репы пушит только пользователь через deliver.sh).
# Здесь нет клиентского кода — только артефакты системы. Хук всё равно заблокирует секреты в коммите;
# тут — вежливая предпроверка чистоты рабочего дерева и собственно push.
#
# GENERIC-КОПИЯ. # ADAPT: github.com/d-s-vo/nuxt4-ts-project-cbook — хост клиентского git (напр. gitlab.example.com):
#   защита от случайного пуша артефактов в клиентский origin. Механизм очереди/rebase — «как есть».
#
# Usage:
#   ai-push.sh [--dry-run]
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
: "${WS_ROOT:=$(dirname "$SCRIPT_DIR")}"
. "$SCRIPT_DIR/lib/workspace.sh"
. "$SCRIPT_DIR/lib/coord.sh"   # coord_lock/coord_unlock/coord_lock_toucher
. "$SCRIPT_DIR/lib/role.sh"    # role_require_privileged (K-role, M5)

# Ролевой гвард (K-role, M5) — в начале, ДО лока/dry-run/сети: разрешённый агенту пуш артефактов
# выполняется как привилегированный (хостовой) канал. Из изолированной сессии — отказ (exit 3)
# ещё до захвата лока ai-push и до обращения к сети. На хосте/при M5=OFF прозрачен.
role_require_privileged "публикация артефактов во внутренний remote"

DRY=0
for a in "$@"; do
    case "$a" in
        --dry-run) DRY=1 ;;
        -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) printf '%sНеизвестный флаг: %s%s\n' "$WS_RED" "$a" "$WS_RST" >&2; exit 2 ;;
    esac
done

die() { printf '%sОШИБКА: %s%s\n' "$WS_RED" "$*" "$WS_RST" >&2; exit 1; }
say() { printf '%s\n' "$*"; }

cd "$WS_ROOT" || die "не удалось перейти в $WS_ROOT"
git rev-parse --git-dir >/dev/null 2>&1 || die "$WS_ROOT — не git-репозиторий"

# 1. Это именно внутренний репо артефактов, а не клиентская репа.
URL="$(git config --get remote.origin.url 2>/dev/null)"
[ -n "$URL" ] || die "не задан remote.origin.url"
case "$URL" in
    *github.com/d-s-vo/nuxt4-ts-project-cbook*) die "origin указывает на клиентский git-хост — это НЕ канал ai-push." ;;
esac
say "== цель: origin = $URL =="

# 2. Ветка и наличие коммитов.
if git rev-parse HEAD >/dev/null 2>&1; then
    BRANCH="$(git rev-parse --abbrev-ref HEAD)"
    HAVE_COMMIT=1
else
    BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || echo main)"
    HAVE_COMMIT=0
fi
say "== ветка: $BRANCH =="

# 3. Вежливая проверка чистоты рабочего дерева.
DIRTY="$(git status --porcelain 2>/dev/null | grep -c .)"
if [ "${DIRTY:-0}" -ne 0 ]; then
    say "${WS_YEL}Внимание: незакоммиченных изменений: $DIRTY.${WS_RST}"
    say "  Публикуется только то, что уже закоммичено. Сначала: git commit (хук проверит секреты) или edit-shared.sh/ai-commit.sh."
fi

# 4. Есть ли что пушить.
if [ "$HAVE_COMMIT" -eq 0 ]; then
    say "${WS_YEL}В репозитории ещё нет ни одного коммита — пушить нечего.${WS_RST}"
    [ "$DRY" -eq 1 ] || die "нет коммитов для публикации (сделайте первый коммит)."
fi

if [ "$DRY" -eq 1 ]; then
    say ""
    say "[DRY-RUN] Реально было бы выполнено:"
    say "  git push origin $BRANCH"
    say "  (origin=$URL, коммиты: $([ "$HAVE_COMMIT" -eq 1 ] && echo есть || echo нет))"
    exit 0
fi

# 5. Захват лока ai-push вокруг сетевой части (сериализация: несколько инстансов пушат
#    параллельно). Семантика — ОЧЕРЕДЬ, а не отказ: второй дожидается очереди, делает
#    pull --rebase и пушит; non-fast-forward между нашими инстансами исключён под локом.
#    Таймаут ожидания = REQUEUE (мягкий повтор, exit 75 = EX_TEMPFAIL), НЕ жёсткий провал.
AIPUSH_WAIT="${AIPUSH_WAIT:-120}"     # сек ждать очередь
if ! coord_lock ai-push "$AIPUSH_WAIT" 20; then
    say "${WS_YEL}Очередь ai-push занята > ${AIPUSH_WAIT}с — REQUEUE.${WS_RST}"
    say "  Повторите: ./scripts/ai-push.sh (чужой push ещё идёт; это не ошибка)."
    exit 75      # EX_TEMPFAIL — «занято, повторите», НЕ жёсткий провал; чужой лок не тронут
fi
trap 'coord_unlock ai-push' EXIT INT TERM          # немедленно после захвата
coord_lock_toucher ai-push &   # сетевая секция может тянуться; toucher держит owner-mtime свежим
AIPUSH_TOUCHER=$!
# trap ПЕРЕУСТАНАВЛИВАЕТСЯ ПОСЛЕ запуска toucher'а: kill toucher'а — явно, на ЛЮБОМ пути
# выхода, включая die (die → exit → EXIT-trap).
trap 'kill "$AIPUSH_TOUCHER" 2>/dev/null; coord_unlock ai-push' EXIT INT TERM

# 6. Rebase-retry в критической секции (вместо однократного pull+push). Под локом
#    non-fast-forward между нашими инстансами исключён; retry покрывает гонку с каналом ВНЕ
#    нашего лока (напр. пользовательский push) и сетевые сбои.
AIPUSH_TRIES="${AIPUSH_TRIES:-3}"
_i=1
while :; do
    say "== git pull --rebase origin $BRANCH (попытка $_i/$AIPUSH_TRIES) =="
    if ! git pull --rebase origin "$BRANCH"; then
        git rebase --abort >/dev/null 2>&1 || true
        die "pull --rebase не удался (конфликт с чужими коммитами). Rebase откачен.
     Разберите вручную: git fetch origin; git rebase origin/$BRANCH (устраните конфликт), затем повторите ai-push.sh.
     Частая причина — правка общего файла без edit-shared.sh/ai-commit.sh (локи edit-shared/shared-docs)."
    fi
    say "== git push origin $BRANCH =="
    if git push origin "$BRANCH"; then break; fi
    # push отвергнут: канал ВНЕ нашего лока опередил (напр. пользовательский push) — повтор.
    _i=$(( _i + 1 ))
    [ "$_i" -le "$AIPUSH_TRIES" ] || die "push отвергнут $AIPUSH_TRIES раза — разберите вручную."
    say "${WS_YEL}push отвергнут — повтор pull --rebase…${WS_RST}"
done

kill "$AIPUSH_TOUCHER" 2>/dev/null; coord_unlock ai-push; trap - EXIT INT TERM
