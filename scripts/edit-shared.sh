#!/usr/bin/env bash
# edit-shared.sh — правка ОБЩИХ файлов зоны артефактов под edit-cycle-локом на ВЕСЬ цикл
# read-modify-write, а не только на коммит.
#
# Модель — КОМАНДА-ПОД-ЛОКОМ (не лиз acquire/release): mkdir-лок нельзя надёжно держать
# между независимыми вызовами shell (владелец-подпроцесс выходит → его pid/mtime мертвы →
# перехват). Обёртка держит лок в живом процессе весь цикл и авто-снимает на выходе/крэше
# (trap + toucher-протухание при SIGKILL).
#
#   edit-shared.sh "<сообщение-коммита>" <общий-путь>... -- <команда-правки...>
#
# Поток: whitelist-валидация путей → coord_lock edit-shared (+toucher) → <команда-правки>
# (детерминированная: append строки / замена секции / регенерация таблицы) → ai-commit.sh
# (берёт commit-lock shared-docs; порядок edit-shared → shared-docs — дедлока нет) → unlock.
#
# Whitelist (# ADAPT: под структуру ai/ проекта): ai/memory.md, ai/architecture.md,
# ai/devlog/README.md, ai/devlog/features/README.md, ai/devlog/commits/README.md
# (реестр разборов/ревью — ADR-009/010), дневные ai/devlog/YYYY-MM-DD.md, ai/guides/*.
# ai/adr/* и изолированные FEAT-папки СЮДА НЕ входят — они коммитятся ai-commit.sh.
#
# ЗАПРЕТ БЭКГРАУНДИНГА: правка обязана завершиться ДО возврата команды. Если <команда-правки>
# уводит работу в фон (`... &`), лок снимется раньше конца правки → гонка. Обёртка отсекает
# прямых выживших потомков (грубый guard); репарентнутые в init — остаточный риск, поэтому
# правило первично: НЕ бэкграундить работу из команды-правки.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
: "${WS_ROOT:=$(dirname "$SCRIPT_DIR")}"
. "$SCRIPT_DIR/lib/coord.sh"

die() { printf '%sОШИБКА: %s%s\n' "$_C_RED" "$*" "$_C_RST" >&2; exit 1; }
say() { printf '%s\n' "$*"; }

usage() {
    cat >&2 <<'EOF'
edit-shared.sh — правка общих md зоны артефактов под edit-cycle-локом.

  edit-shared.sh "<сообщение-коммита>" <общий-путь>... -- <команда-правки...>

Whitelist общих путей: ai/memory.md, ai/architecture.md, ai/devlog/README.md,
ai/devlog/features/README.md, ai/devlog/commits/README.md, дневные ai/devlog/YYYY-MM-DD.md, ai/guides/*.
ai/adr/* и FEAT-папки — через ai-commit.sh.

Команда-правки ДОЛЖНА завершиться синхронно (НЕ бэкграундить: `... &` запрещено —
лок снимется раньше конца правки).

Пример:
  edit-shared.sh "DOCS / devlog / веха" ai/devlog/2026-01-15.md -- \
      sh -c 'printf "- итог дня\n" >> ai/devlog/2026-01-15.md'
EOF
    exit 2
}

# _es_whitelisted <путь> — 0, если путь входит в whitelist общих файлов.
# Нормализует абсолютный путь под WS_ROOT и ведущий './'.
# ADAPT: список ниже — под структуру ai/ проекта (см. ai/guides/stack-specifics.md).
_es_whitelisted() {
    _esp="$1"
    case "$_esp" in
        "$WS_ROOT"/*) _esp="${_esp#"$WS_ROOT"/}" ;;
    esac
    _esp="${_esp#./}"
    case "$_esp" in
        ai/memory.md|ai/architecture.md|ai/devlog/README.md|ai/devlog/features/README.md|ai/devlog/commits/README.md)
            return 0 ;;
        ai/guides/*)
            return 0 ;;
        ai/devlog/*)
            _esbase="${_esp#ai/devlog/}"
            case "$_esbase" in
                */*) return 1 ;;   # вложенная папка (features/… и пр.) — не дневной файл
                [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md) return 0 ;;
            esac
            return 1 ;;
    esac
    return 1
}

[ "$#" -ge 1 ] || usage
case "$1" in -h|--help) usage ;; esac

MSG="$1"
[ -n "$MSG" ] || die "первый аргумент — непустое сообщение коммита."
shift

# Разбор: пути до '--', затем команда после '--'.
seen_sep=0
paths=()
while [ "$#" -gt 0 ]; do
    if [ "$1" = "--" ]; then seen_sep=1; shift; break; fi
    paths+=("$1"); shift
done
[ "$seen_sep" -eq 1 ] || die "нет '--' между путями и командой: edit-shared.sh \"<msg>\" <путь>... -- <cmd...>"
[ "${#paths[@]}" -ge 1 ] || die "укажите хотя бы один общий путь до '--'."
[ "$#" -gt 0 ] || die "пустая команда после '--'."

# Whitelist-валидация КАЖДОГО пути.
for _p in "${paths[@]}"; do
    _es_whitelisted "$_p" || die "путь вне whitelist общих файлов: $_p — изолированные артефакты и ai/adr/* коммитятся ai-commit.sh."
done

cd "$WS_ROOT" || die "не удалось перейти в $WS_ROOT"

# Взятие edit-cycle-lock на ВЕСЬ цикл. Порядок локов: booking → edit-shared → shared-docs.
coord_lock edit-shared 60 10 || die "не удалось захватить лок edit-shared."
trap 'coord_unlock edit-shared' EXIT INT TERM
# Lock-level heartbeat: цикл правки может тянуться (замена секции/регенерация таблицы).
# Toucher фоново освежает owner-mtime; гибнет вместе с обёрткой (в т.ч. SIGKILL) → лок
# протухает по COORD_LOCK_MTIME_STALE, а не висит до session-порога.
coord_lock_toucher edit-shared &
_es_toucher=$!
trap 'kill "$_es_toucher" 2>/dev/null; coord_unlock edit-shared' EXIT INT TERM

# Запуск команды-правки (детерминированная трансформация под локом).
"$@"
rc=$?

# Грубый guard бэкграундинга: прямые потомки обёртки, пережившие команду-правку
# (кроме toucher'а), — признак фоновой работы за пределами лока. Репарентнутые в init
# этим не ловятся — правило запрета бэкграундинга первично (см. шапку/usage).
_es_survivors="$(pgrep -P $$ 2>/dev/null | grep -vx "$_es_toucher" || true)"
if [ -n "$_es_survivors" ]; then
    kill "$_es_toucher" 2>/dev/null
    coord_unlock edit-shared; trap - EXIT INT TERM
    die "фоновый потомок пережил команду-правку (pids: $(printf '%s' "$_es_survivors" | tr '\n' ' ')) — бэкграундинг ЗАПРЕЩЁН: лок снимется раньше конца правки."
fi

if [ "$rc" -ne 0 ]; then
    kill "$_es_toucher" 2>/dev/null
    coord_unlock edit-shared; trap - EXIT INT TERM
    die "команда-правки вернула код $rc — коммит не выполнен, лок снят."
fi

# Коммит своей зоны через ai-commit.sh — берёт commit-lock shared-docs (разноимённое
# вложение при держащемся edit-shared; порядок edit-shared → shared-docs, дедлока нет).
"$SCRIPT_DIR/ai-commit.sh" "$MSG" "${paths[@]}"
_es_crc=$?

kill "$_es_toucher" 2>/dev/null
coord_unlock edit-shared; trap - EXIT INT TERM
exit "$_es_crc"
