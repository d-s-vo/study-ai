#!/usr/bin/env bash
# ledger-check.sh — чекер ПОЛНОТЫ метрик-леджера инициативы (модуль M7, process-retro §б).
#
# Сверяет: на каждую ЗАКРЫТУЮ (✅/⚠️) фичу инициативы в леджере adr-<NNN>.jsonl обязана быть
# строка с обязательными КЛЮЧАМИ feat/adr/role/model. Проверяется наличие КЛЮЧА, не значения —
# null ОК (ядро толерантности к пропускам, process-retro.md §б). ⬜/🚧 игнорируются; пустой
# список закрытых фич → тихий проход (анти-self-lock на только что заведённой инициативе).
#
# По умолчанию WARN-ONLY: дыры печатаются, код возврата 0 (не валит CI/DoD — усиливает
# следующий ретро сигналом «тут метрику потеряли»). Флаг --strict → exit 1 при любой дыре
# (локальный опт-ин).
#
# Список закрытых фич берётся из (можно совмещать):
#   • позиционных аргументов FEAT-NNN — детерминированный путь;
#   • таблицы --table <md>: строки со статусом ✅/⚠️, из них извлекаются токены FEAT-NNN
#     (⬜/🚧-строки не матчатся).
# # ADAPT: реестр feat-map (ai/devlog/features/README.md) ведёт статус СЛОВАМИ
#   (done/reserved/in-progress), не эмодзи — для него передавай FEAT-NNN ЯВНО либо таблицу
#   инициативы, где статус проставлен ✅/⚠️ (напр. план adr-execution). Однозначного эмодзи-
#   источника «фичи инициативы» в этом workspace нет → список фич сделан входным параметром.
#
# Использование:
#   ledger-check.sh [--strict] --ledger <adr-NNN.jsonl> [--table <md>] [FEAT-NNN ...]
#   пример: ./scripts/ledger-check.sh --ledger ai/process-metrics/adr-012.jsonl FEAT-020 FEAT-021
#   пример: ./scripts/ledger-check.sh --strict --ledger ai/process-metrics/adr-012.jsonl \
#             --table ai/process-metrics/plan-adr-012.md
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
: "${WS_ROOT:=$(dirname "$SCRIPT_DIR")}"

# Минимальные цвета (без побочных эффектов coord-lib): только на TTY.
if [ -t 1 ]; then
    _C_RED=$'\033[31m'; _C_YEL=$'\033[33m'; _C_GRN=$'\033[32m'; _C_DIM=$'\033[2m'; _C_RST=$'\033[0m'
else
    _C_RED=''; _C_YEL=''; _C_GRN=''; _C_DIM=''; _C_RST=''
fi

die() { printf '%sОШИБКА: %s%s\n' "$_C_RED" "$*" "$_C_RST" >&2; exit 2; }

usage() {
    cat >&2 <<'EOF'
ledger-check.sh — чекер полноты метрик-леджера инициативы (M7, process-retro §б).

  ledger-check.sh [--strict] --ledger <adr-NNN.jsonl> [--table <md>] [FEAT-NNN ...]

Проверяет: на каждую ЗАКРЫТУЮ (✅/⚠️) фичу — строка в леджере с ключами feat/adr/role/model
(наличие КЛЮЧА, не значения — null ОК). ⬜/🚧 игнорируются; пустой список → тихий проход.

  --strict         exit 1 при любой дыре (по умолчанию warn-only, exit 0)
  --ledger <файл>  путь к adr-<NNN>.jsonl (обязателен; несуществующий/пустой → дыры, не падение)
  --table  <md>    md-таблица инициативы: закрытые фичи = строки со статусом ✅/⚠️
  FEAT-NNN ...     явный список закрытых фич (детерминированный путь)

Источник списка фич: аргументы FEAT-NNN и/или --table (совмещаются, дедуп). Реестр feat-map
(ai/devlog/features/README.md) ведёт статус словами (done/…), не эмодзи — для него передавай
FEAT-NNN явно либо таблицу инициативы со статусом ✅/⚠️. Пути можно относительные (от корня
workspace) или абсолютные.

Примеры:
  ledger-check.sh --ledger ai/process-metrics/adr-012.jsonl FEAT-020 FEAT-021
  ledger-check.sh --strict --ledger ai/process-metrics/adr-012.jsonl --table plan.md
EOF
    exit 2
}

command -v jq >/dev/null 2>&1 || die "нужен jq (парсинг JSONL леджера)."

STRICT=0
LEDGER=''
TABLE=''
feats=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help) usage ;;
        --strict) STRICT=1; shift ;;
        --ledger) [ "$#" -ge 2 ] || die "--ledger требует путь."; LEDGER="$2"; shift 2 ;;
        --table)  [ "$#" -ge 2 ] || die "--table требует путь.";  TABLE="$2";  shift 2 ;;
        FEAT-[0-9]*) feats+=("$1"); shift ;;
        --) shift ;;
        -*) die "неизвестный флаг: $1 (см. --help)." ;;
        *) die "неожиданный аргумент: $1 (ожидается FEAT-NNN или флаг; см. --help)." ;;
    esac
done

[ -n "$LEDGER" ] || die "обязателен --ledger <adr-NNN.jsonl> (см. --help)."

# Нормализация путей относительно WS_ROOT — запуск из любого каталога.
case "$LEDGER" in /*) : ;; *) LEDGER="$WS_ROOT/$LEDGER" ;; esac
if [ -n "$TABLE" ]; then case "$TABLE" in /*) : ;; *) TABLE="$WS_ROOT/$TABLE" ;; esac; fi

# Сбор закрытых фич из таблицы: строки со статусом ✅/⚠️ → токены FEAT-NNN (⬜/🚧 не матчатся).
if [ -n "$TABLE" ]; then
    [ -f "$TABLE" ] || die "таблица не найдена: $TABLE"
    while IFS= read -r _tok; do
        [ -n "$_tok" ] && feats+=("$_tok")
    done < <(grep -E '✅|⚠️' "$TABLE" 2>/dev/null | grep -oE 'FEAT-[0-9]+' | sort -u)
fi

# Дедуп списка фич (под set -u — только при непустом массиве).
if [ "${#feats[@]}" -gt 0 ]; then
    _uniq=()
    while IFS= read -r _f; do [ -n "$_f" ] && _uniq+=("$_f"); done < <(printf '%s\n' "${feats[@]}" | sort -u)
    feats=("${_uniq[@]}")
fi

# Анти-self-lock: пустой список закрытых фич → тихий проход.
if [ "${#feats[@]}" -eq 0 ]; then
    printf '%sledger-check: закрытых (✅/⚠️) фич не найдено — тихий проход.%s\n' "$_C_DIM" "$_C_RST" >&2
    exit 0
fi

# Леджер может отсутствовать/быть пустым/с битыми строками — это НЕ падение, а дыры по фичам.
# fromjson? // empty пропускает невалидные строки; jq -s собирает валидные объекты в массив.
_rows='[]'
if [ -f "$LEDGER" ]; then
    _rows="$(jq -R 'fromjson? // empty' "$LEDGER" 2>/dev/null | jq -s '.' 2>/dev/null)" || _rows='[]'
    [ -n "$_rows" ] || _rows='[]'
fi

missing=0
present=0
for _f in "${feats[@]}"; do
    _stat="$(printf '%s' "$_rows" | jq -r --arg f "$_f" '
        [ .[] | select(.feat==$f) ] as $rows
        | ([ $rows[]
             | select(has("feat") and has("adr") and has("role") and has("model")) ] | length) as $ok
        | if $ok > 0 then "OK"
          elif ($rows|length) > 0 then "PARTIAL"
          else "MISSING" end' 2>/dev/null)"
    case "$_stat" in
        OK)
            present=$((present + 1))
            printf '%s  ✓ %s — строка с ключами feat/adr/role/model есть%s\n' "$_C_GRN" "$_f" "$_C_RST" ;;
        PARTIAL)
            missing=$((missing + 1))
            printf '%s  ⚠ %s — строка есть, но не хватает обязательного ключа (feat/adr/role/model)%s\n' "$_C_YEL" "$_f" "$_C_RST" ;;
        *)
            missing=$((missing + 1))
            printf '%s  ⚠ %s — нет строки в леджере%s\n' "$_C_YEL" "$_f" "$_C_RST" ;;
    esac
done

printf '%sledger-check: закрыто %d, с полной строкой %d, дыр %d (леджер: %s)%s\n' \
    "$_C_DIM" "${#feats[@]}" "$present" "$missing" "$LEDGER" "$_C_RST" >&2

if [ "$missing" -gt 0 ]; then
    if [ "$STRICT" -eq 1 ]; then
        printf '%sledger-check --strict: %d дыр(а) — exit 1.%s\n' "$_C_RED" "$missing" "$_C_RST" >&2
        exit 1
    fi
    printf '%sledger-check: warn-only — дыры замечены, код возврата 0 (усильте следующий ретро).%s\n' "$_C_YEL" "$_C_RST" >&2
fi
exit 0
