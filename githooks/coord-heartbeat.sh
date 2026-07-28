#!/usr/bin/env bash
# coord-heartbeat.sh — PostToolUse-хук: дёшево обновляет heartbeat своего файла присутствия.
# Троттлинг: если файл моложе 60с (по mtime) — noop. Никакого вывода. Цель <100мс.
# Realm/account вычисляются ИНЛАЙН (намеренно не источит coord.sh — скорость; ветка recreate редкая).
set -u

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
WS_ROOT="$(dirname "$HOOK_DIR")"
COORD_AGENTS="$WS_ROOT/ai/coord/agents"

input="$(cat)"
session_id="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
[ -n "$session_id" ] || exit 0

af="$COORD_AGENTS/$session_id.json"

# Файла присутствия нет (реапнут как протухший, а сессия на деле жива) — ПЕРЕСОЗДАЁМ его
# с теми же полями, что coord-session-start, + source=heartbeat-recreate. Не молчаливый exit:
# иначе живой агент навсегда пропал бы с доски после одного протухания.
if [ ! -f "$af" ]; then
    mkdir -p "$COORD_AGENTS" 2>/dev/null || true
    if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
        acc="$(basename "$CLAUDE_CONFIG_DIR")"
        # хостовая схема .../accounts/<name>/config-dir → имя из родителя (иначе acc='config-dir').
        [ "$acc" = "config-dir" ] && acc="$(basename "$(dirname "$CLAUDE_CONFIG_DIR")")"
    else
        acc="default"
    fi
    # realm-токен — вычисляем инлайн, идентично coord_realm в lib/coord.sh.
    if [ -n "${COORD_REALM:-}" ]; then
        realm="$(printf '%s' "$COORD_REALM" | LC_ALL=C tr -cd 'a-zA-Z0-9._-')"
    elif [ -r /proc/self/ns/pid ]; then
        _r="$(readlink /proc/self/ns/pid 2>/dev/null)"; _r="${_r##*[}"; _r="${_r%]}"
        realm="ns-$_r"
    else
        realm="host-$(hostname 2>/dev/null | LC_ALL=C tr -cd 'a-zA-Z0-9._-' || echo unknown)"
    fi
    ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    tmp="$af.tmp.$$"
    {
        printf '{\n'
        printf '  "session_id": "%s",\n' "$session_id"
        printf '  "account": "%s",\n'    "$acc"
        printf '  "pid": %s,\n'          "${PPID:-0}"
        printf '  "realm": "%s",\n'      "$realm"
        printf '  "started": "%s",\n'    "$ts"
        printf '  "heartbeat": "%s",\n'  "$ts"
        printf '  "source": "heartbeat-recreate"\n'
        printf '}\n'
    } > "$tmp" 2>/dev/null
    mv "$tmp" "$af" 2>/dev/null || rm -f "$tmp" 2>/dev/null
    exit 0
fi

# троттлинг по mtime файла (обновляется при каждой записи heartbeat).
# GNU-форму (-c) пробуем первой: на Linux `stat -f` = --file-system (мусор с кодом 0),
# BSD-first дал бы неверный mtime в контейнере (кросс-граница).
now="$(date -u '+%s')"
mtime="$(stat -c %Y "$af" 2>/dev/null || stat -f %m "$af" 2>/dev/null || echo 0)"
[ "$(( now - mtime ))" -lt 60 ] && exit 0

ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
tmp="$af.tmp.$$"
if jq --arg t "$ts" '.heartbeat=$t' "$af" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$af" 2>/dev/null || rm -f "$tmp" 2>/dev/null
else
    rm -f "$tmp" 2>/dev/null
    touch "$af" 2>/dev/null
fi
exit 0
