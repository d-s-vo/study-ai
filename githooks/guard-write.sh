#!/usr/bin/env bash
# guard-write.sh — PreToolUse-хук Claude Code для matcher Write|Edit|MultiEdit.  ⇐ ИНВАРИАНТ №11.
# Читает JSON события со stdin, достаёт .tool_input.file_path и БЛОКИРУЕТ (exit 2 + причина)
# запись в файлы самой охранной обвязки / конфигов, которыми обвязка держится.
# Разрешает всё остальное (exit 0).
#
# Зачем: без этого гейта агент с доступом к Write/Edit мог бы переписать сами хуки, stopwords,
# .git/config, .git/hooks/*, .push-allow, coord.sh, settings.json, .mcp.json — и снять всю
# обвязку. Pretool-Bash-гейт этого не ловил (это не bash). «Агент не переписывает свою клетку».
set -u

deny() { printf 'ЗАБЛОКИРОВАНО охранной обвязкой (guard-write): %s\n' "$*" >&2; exit 2; }

input="$(cat)"
fp="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"

# Нет пути — нечего проверять (не наш кейс), пропускаем.
[ -z "$fp" ] && exit 0

# Нормализация: относительный путь разворачиваем относительно cwd, чтобы
# 'githooks/stopwords.txt' и '/abs/.../githooks/stopwords.txt' ловились одинаково.
case "$fp" in
    /*) norm="$fp" ;;
    *)  [ -n "$cwd" ] && norm="$cwd/$fp" || norm="$fp" ;;
esac

# Проверяем И исходный путь, и нормализованный (на случай пустого cwd / хитрых форм).
for p in "$fp" "$norm"; do
    [ -n "$p" ] || continue

    # 1. Любой файл внутри дерева githooks/ (сами хуки, stopwords, allowpatterns, scan.sh).
    if printf '%s\n' "$p" | grep -qE '(^|/)githooks/'; then
        deny "запись в githooks/ ($fp). Файлы охранной обвязки правит только человек."
    fi

    # 2. Любой .git/config (подмена remote/pushurl/hooksPath в обход Bash-гейта).
    if printf '%s\n' "$p" | grep -qE '(^|/)\.git/config$'; then
        deny "запись в .git/config ($fp). Конфиг git правит только человек/скрипты обвязки."
    fi

    # 3. Любой каталог .git/hooks/ (подмена самих git-хуков).
    if printf '%s\n' "$p" | grep -qE '(^|/)\.git/hooks/'; then
        deny "запись в .git/hooks/ ($fp). Git-хуки подключаются только через core.hooksPath."
    fi

    # 4. Файл-разрешение доставки .push-allow.
    if printf '%s\n' "$p" | grep -qE '(^|/)\.push-allow$'; then
        deny "запись в .push-allow ($fp). Разрешение на пуш выдаёт только человек/deliver.sh."
    fi

    # 5. Библиотека координации scripts/lib/coord.sh.
    if printf '%s\n' "$p" | grep -qE '(^|/)scripts/lib/coord\.sh$'; then
        deny "запись в scripts/lib/coord.sh ($fp). Ядро координации правит только человек."
    fi

    # 6. Настройки Claude Code .claude/settings.json.
    if printf '%s\n' "$p" | grep -qE '(^|/)\.claude/settings\.json$'; then
        deny "запись в .claude/settings.json ($fp). Конфиг агентской клетки правит только человек."
    fi

    # 7. Конфиг MCP-серверов .mcp.json.
    if printf '%s\n' "$p" | grep -qE '(^|/)\.mcp\.json$'; then
        deny "запись в .mcp.json ($fp). Список MCP-серверов правит только человек."
    fi
done

exit 0
