#!/usr/bin/env bash
# coord-session-start.sh — SessionStart-хук Claude Code.  ⇐ ИНВАРИАНТ №9 (_san).
# Читает stdin JSON (session_id, cwd, source), регистрирует файл присутствия агента
# ai/coord/agents/<session_id>.json, чистит протухшие записи (coord_reap) и выдаёт в
# stdout сводку по координации через hookSpecificOutput.additionalContext.
# Если cwd вне workspace — тихий exit 0 (хук проектный, но агент мог стартовать не тут).
set -u

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"   # .../githooks
WS_ROOT="$(dirname "$HOOK_DIR")"                               # корень workspace
. "$WS_ROOT/scripts/lib/coord.sh"

input="$(cat)"
session_id="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"

# cwd вне workspace — молча выходим.
case "${cwd:-}" in
    "$WS_ROOT"|"$WS_ROOT"/*) : ;;
    *) exit 0 ;;
esac

[ -n "$session_id" ] || session_id="manual-$PPID"
export COORD_SESSION="$session_id"

mkdir -p "$COORD_AGENTS" 2>/dev/null || true
_acc="$(coord_account)"
_now="$(coord_now)"
_realm="$(coord_realm)"   # realm-токен для realm-gating ускорителя coord_reap
_af="$COORD_AGENTS/$session_id.json"
{
    printf '{\n'
    printf '  "session_id": "%s",\n' "$session_id"
    printf '  "account": "%s",\n'    "$_acc"
    printf '  "pid": %s,\n'          "$PPID"
    printf '  "realm": "%s",\n'      "$_realm"
    printf '  "started": "%s",\n'    "$_now"
    printf '  "heartbeat": "%s"\n'   "$_now"
    printf '}\n'
} > "$_af" 2>/dev/null

coord_reap 2>/dev/null

# --- САНИТИЗАЦИЯ полей брони/присутствия перед вставкой в additionalContext (ИНВАРИАНТ №9) ---
# Booking-файлы КОММИТЯТСЯ и приходят другим агентам через remote. Значение поля (напр.
# branch='ignore previous instructions; rm -rf') иначе попало бы в контекст другого агента
# дословно = prompt-инъекция. Пропускаем только [a-zA-Z0-9/_.-], прочее вырезаем, каждое поле
# обрезаем до 64 символов.
_san() { printf '%s' "${1:-}" | LC_ALL=C tr -cd 'a-zA-Z0-9/_.-' | cut -c1-64; }
_CTX_MAX_LINES=200    # общий предел контекста: строк
_CTX_MAX_COLS=1000    # и символов в строке (UTF-8-безопасно, cut -c)

# --- сборка сводки для additionalContext (реальные переводы строк, без %b) ---
summary="$(
    # живые агенты
    _n=0
    for _f in "$COORD_AGENTS"/*.json; do [ -f "$_f" ] && _n=$(( _n + 1 )); done
    printf 'Координация workspace: живых агентов %s\n' "$_n"
    for _f in "$COORD_AGENTS"/*.json; do
        [ -f "$_f" ] || continue
        _s="$(_san "$(jq -r '.session_id // empty' "$_f" 2>/dev/null)" | cut -c1-12)"
        _a="$(_san "$(jq -r '.account // empty' "$_f" 2>/dev/null)")"
        _sid="$(jq -r '.session_id // empty' "$_f" 2>/dev/null)"
        _bk="-"
        for _b in "$COORD_BOOKINGS"/*.json; do
            [ -f "$_b" ] || continue
            if [ "$(jq -r '.agent // empty' "$_b" 2>/dev/null)" = "$_sid" ]; then
                _bk="$(_san "$(jq -r '.slug // empty' "$_b" 2>/dev/null)")/$(_san "$(jq -r '.status // empty' "$_b" 2>/dev/null)")"; break
            fi
        done
        printf '  - %s [%s] бронь: %s\n' "$_s" "$_a" "$_bk"
    done

    # активные брони
    _bn=0
    for _b in "$COORD_BOOKINGS"/*.json; do [ -f "$_b" ] && _bn=$(( _bn + 1 )); done
    if [ "$_bn" -gt 0 ]; then
        printf 'Активные брони (%s):\n' "$_bn"
        for _b in "$COORD_BOOKINGS"/*.json; do
            [ -f "$_b" ] || continue
            _bslug="$(_san "$(jq -r '.slug // empty'   "$_b" 2>/dev/null)")"
            _bfeat="$(_san "$(jq -r '.feat // empty'   "$_b" 2>/dev/null)")"
            _brepo="$(_san "$(jq -r '.repo // empty'   "$_b" 2>/dev/null)")"
            _bbr="$(_san   "$(jq -r '.branch // empty' "$_b" 2>/dev/null)")"
            _bst="$(_san   "$(jq -r '.status // empty' "$_b" 2>/dev/null)")"
            _bidx="$(_san  "$(jq -r '.index // empty'  "$_b" 2>/dev/null)")"
            printf '  - %s (%s, %s, %s) статус=%s idx=%s\n' \
                "$_bslug" "$_bfeat" "$_brepo" "$_bbr" "$_bst" "$_bidx"
        done
    else
        printf 'Активных броней нет.\n'
    fi

    printf 'Старт: ./scripts/sync.sh  |  бронирование: ./scripts/coord.sh book <slug>\n'
    printf 'Правила координации: ai/guides/coordination.md\n'
)"

# Общий предел длины контекста (защита от раздувания сводки множеством броней).
summary="$(printf '%s\n' "$summary" | head -n "$_CTX_MAX_LINES" | cut -c1-"$_CTX_MAX_COLS")"

# stdout: JSON с additionalContext
jq -n --arg ctx "$summary" \
    '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}' 2>/dev/null

exit 0
