#!/usr/bin/env bash
# coord-session-end.sh — SessionEnd-хук: удаляет свой файл присутствия (best-effort).
set -u

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
WS_ROOT="$(dirname "$HOOK_DIR")"
COORD_AGENTS="$WS_ROOT/ai/coord/agents"

input="$(cat)"
session_id="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
[ -n "$session_id" ] || exit 0

rm -f "$COORD_AGENTS/$session_id.json" 2>/dev/null
exit 0
