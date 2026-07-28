#!/usr/bin/env bash
# gate.sh — сериализация тяжёлых/эксклюзивных операций между агентами через coord-лок.
# Захватывает gate-<ресурс> (ожидание до 30 мин, прогресс раз в 30с), запускает команду,
# освобождает лок по trap. Код возврата = коду команды.
#
# GENERIC-КОПИЯ: механизм полностью проектно-независим (один из лучших кандидатов «как есть»).
# # ADAPT: конвенции имён ресурсов проектны (см. ai/guides/stack-specifics.md), сам gate агностичен.
#   Примеры имён: backend-tests, frontend-build, migrate-shared, typecheck, coverage, build.
#
# Коды возврата: код команды под гейтом транслируется как есть; die-случаи (нет ресурса,
#   нет '--', пустая команда) → exit 2; таймаут очереди (лок не взят за GATE_WAIT) →
#   exit 75 (REQUEUE — «занято, повтори», НЕ красный гейт).
# GATE_WAIT — секунды ожидания очереди (по умолчанию 1800 = 30 мин).
#
# Использование:
#   gate.sh <ресурс> -- <команда...>
#   пример: ./scripts/gate.sh backend-tests -- .venv/bin/pytest
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
: "${WS_ROOT:=$(dirname "$SCRIPT_DIR")}"
. "$SCRIPT_DIR/lib/coord.sh"

die() { printf '%sОШИБКА: %s%s\n' "$_C_RED" "$*" "$_C_RST" >&2; exit 2; }

RES="${1:-}"
[ -n "$RES" ] || die "укажите ресурс: gate.sh <ресурс> -- <команда...>"
shift
[ "${1:-}" = "--" ] || die "ожидается '--' перед командой: gate.sh <ресурс> -- <команда...>"
shift
[ "$#" -gt 0 ] || die "пустая команда после '--'."

LOCK="gate-$RES"

# Вложенный gate того же ресурса РАЗРЕШЁН как реентрантный no-op. Реентрантный guard
# `coord_lock` (COORD_HELD_LOCKS + ре-валидация владения по цепочке предков) сам вернёт 0
# без ожидания, если лок держит этот процесс или его предок — вложенная команда исполняется
# внутри его критической секции (сериализация сохранена). Независимый параллельный gate того
# же ресурса (не предок) по-прежнему честно ждёт очередь.

# ожидание очереди до GATE_WAIT секунд (по умолчанию 1800 = 30 мин), прогресс раз в 30с.
# coord_lock rc==1 — ИМЕННО таймаут очереди (исчерпаны итерации при живом владельце):
# это НЕ красный гейт, а REQUEUE → exit 75 (EX_TEMPFAIL), чужой лок не тронут.
: "${GATE_WAIT:=1800}"
if ! coord_lock "$LOCK" "$GATE_WAIT" 30; then
    printf '%sgate[%s]: queue-timeout — REQUEUE, повтори команду (чужой гейт ещё идёт, это не ошибка)%s\n' \
        "$_C_YEL" "$RES" "$_C_RST" >&2
    exit 75
fi
# lock-level heartbeat: гейт легитимно держит лок до 30 минут (полный прогон/сборка) БЕЗ
# обновления owner-mtime — без toucher'а сигнал (0) steal-матрицы отберёт лок у живого гейта
# на ~COORD_LOCK_MTIME_STALE-й секунде. Toucher фоново освежает owner-mtime; гибнет вместе с
# gate.sh (в т.ч. SIGKILL) и снимается в trap.
coord_lock_toucher "$LOCK" &
_gate_toucher=$!
trap 'kill "$_gate_toucher" 2>/dev/null; coord_unlock "$LOCK"' EXIT INT TERM

printf '%s== gate[%s] захвачен, выполняю: %s ==%s\n' "$_C_GRN" "$RES" "$*" "$_C_RST" >&2
"$@"
rc=$?
printf '%s== gate[%s] освобождён (код %s) ==%s\n' "$_C_DIM" "$RES" "$rc" "$_C_RST" >&2
exit "$rc"
