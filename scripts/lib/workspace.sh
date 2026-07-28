#!/usr/bin/env bash
# workspace.sh — общая библиотека слоя синхронизации мульти-репо workspace.
# Единственный источник знаний о репах — scripts/repos.conf (ноль хардкода).
# Совместимо с bash 3.2: без ассоциативных массивов, без mapfile, grep -E (без -P).
#
# GENERIC-КОПИЯ шаблона agent-dev-system-template. Механика перенесена дословно;
# проектная конкретика вынесена в repos.conf (единственный параметр этого слоя).
#
# Публичные функции (все принимают "строку конфига" из ws_conf_lines):
#   ws_conf_lines                         — валидные строки repos.conf
#   ws_field <line> <n>                   — n-е поле строки (1..7)
#   ws_name/ws_type/ws_path/ws_base/ws_mainwt/ws_extra/ws_origin <line>
#   ws_origin <line>                      — origin-URL (поле 7) для клонирования bootstrap.sh
#   ws_gitdir <line>                      — каталог для 'git -C' (bare или клон)
#   ws_mainwt_abs <line>                  — абсолютный путь основного worktree
#   ws_task_worktrees <line>              — строки "<путь>\t<ветка>" для tasks/*
#   ws_ahead_behind <gitdir> <ref> <base> — печатает "<behind>\t<ahead>"
#   ws_delivered <gitdir> <branch>        — 0 если ветка есть в origin/*
#   ws_merged <gitdir> <branch> <base>    — 0 если ветка влита в origin/<base>
#   ws_slug <worktree-path>               — последний компонент пути (slug задачи)

_ws_src="${BASH_SOURCE[0]:-$0}"
WS_LIB_DIR="$(cd "$(dirname "$_ws_src")" && pwd)"
WS_SCRIPTS_DIR="$(dirname "$WS_LIB_DIR")"
# WS_ROOT — корень внутреннего репозитория знаний (зона артефактов). Все пути к репам и
# worktree считаются от него. Имя переменной WS_ROOT — внутреннее; наружу не влияет.
: "${WS_ROOT:=$(dirname "$WS_SCRIPTS_DIR")}"
: "${REPOS_CONF:=$WS_SCRIPTS_DIR/repos.conf}"
# ADAPT: корень task-worktree (по умолчанию <WS_ROOT>/tasks) — единственная привязка имени
#        каталога задач в этом слое. Меняется через env TASKS_ROOT; см. ai/guides/stack-specifics.md.
: "${TASKS_ROOT:=$WS_ROOT/tasks}"

# --- цвета (только если stdout — терминал) ---
if [ -t 1 ]; then
    WS_RED="$(printf '\033[31m')"; WS_GRN="$(printf '\033[32m')"
    WS_YEL="$(printf '\033[33m')"; WS_DIM="$(printf '\033[2m')"
    WS_BLD="$(printf '\033[1m')";  WS_RST="$(printf '\033[0m')"
else
    WS_RED=""; WS_GRN=""; WS_YEL=""; WS_DIM=""; WS_BLD=""; WS_RST=""
fi

# ws_conf_lines — печатает непустые не-комментарии строки конфига.
ws_conf_lines() {
    [ -f "$REPOS_CONF" ] || { printf 'repos.conf не найден: %s\n' "$REPOS_CONF" >&2; return 1; }
    while IFS= read -r _ws_l || [ -n "$_ws_l" ]; do
        case "$_ws_l" in
            ''|'#'*) continue ;;
        esac
        # строка без ведущих/хвостовых пробелов
        _ws_l="${_ws_l#"${_ws_l%%[![:space:]]*}"}"
        [ -n "$_ws_l" ] && printf '%s\n' "$_ws_l"
    done < "$REPOS_CONF"
}

# ws_field <line> <n> — n-е поле (разделитель '|'), с обрезкой пробелов.
ws_field() {
    printf '%s\n' "$1" | awk -F'|' -v n="$2" \
        '{ f=$n; gsub(/^[ \t]+/,"",f); gsub(/[ \t]+$/,"",f); print f }'
}

ws_name()   { ws_field "$1" 1; }
ws_type()   { ws_field "$1" 2; }
ws_path()   { ws_field "$1" 3; }
ws_base()   { ws_field "$1" 4; }
ws_mainwt() { ws_field "$1" 5; }
ws_extra()  { ws_field "$1" 6; }
ws_origin() { ws_field "$1" 7; }   # origin-URL для клонирования (bootstrap.sh); пусто у read-only/локальных

# ws_extra_worktrees <line> — доп. основные worktree (поле 6), строки "<имя>\t<ветка>".
# Формат поля: "имя:ветка[,имя:ветка...]". Пусто, если поля нет.
ws_extra_worktrees() {
    _we="$(ws_extra "$1")"
    [ -n "$_we" ] || return 0
    printf '%s\n' "$_we" | tr ',' '\n' | while IFS= read -r _pair || [ -n "$_pair" ]; do
        _pair="$(printf '%s' "$_pair" | tr -d '[:space:]')"
        [ -n "$_pair" ] || continue
        _en="${_pair%%:*}"; _eb="${_pair#*:}"
        [ -n "$_en" ] && [ -n "$_eb" ] && [ "$_en" != "$_eb" ] && printf '%s\t%s\n' "$_en" "$_eb"
    done
}

# ws_gitdir <line> — каталог, пригодный для 'git -C' (bare-репо или клон).
ws_gitdir() {
    printf '%s\n' "$WS_ROOT/$(ws_path "$1")"
}

# ws_mainwt_abs <line> — абсолютный путь основного worktree.
ws_mainwt_abs() {
    printf '%s\n' "$WS_ROOT/$(ws_mainwt "$1")"
}

# ws_slug <path> — slug задачи = имя последнего компонента пути.
ws_slug() {
    printf '%s\n' "${1##*/}"
}

# ws_task_worktrees <line> — только worktree под <TASKS_ROOT>/, строки "<путь>\t<ветка>".
ws_task_worktrees() {
    _ws_gd="$(ws_gitdir "$1")"
    [ -d "$_ws_gd" ] || return 0
    git -C "$_ws_gd" worktree list --porcelain 2>/dev/null | awk -v root="$TASKS_ROOT/" '
        function flush() {
            if (wt != "" && substr(wt,1,length(root))==root)
                print wt "\t" br
            wt=""; br=""
        }
        /^worktree /{ flush(); wt=$0; sub(/^worktree /,"",wt); br="" }
        /^branch refs\/heads\//{ br=$0; sub(/^branch refs\/heads\//,"",br) }
        /^detached/{ br="(detached)" }
        END{ flush() }
    '
}

# ws_ahead_behind <gitdir> <ref> <base> — печатает "<behind>\t<ahead>" ref относительно origin/base.
# behind = коммитов в origin/base, которых нет в ref; ahead = наоборот.
ws_ahead_behind() {
    _ws_out="$(git -C "$1" rev-list --left-right --count "origin/$3...$2" 2>/dev/null)"
    if [ -z "$_ws_out" ]; then
        printf '?\t?\n'
    else
        # rev-list печатает "left right" = "behind ahead"
        printf '%s\t%s\n' "$(printf '%s' "$_ws_out" | awk '{print $1}')" \
                          "$(printf '%s' "$_ws_out" | awk '{print $2}')"
    fi
}

# ws_delivered <gitdir> <branch> — 0 если ветка присутствует в origin/*.
ws_delivered() {
    git -C "$1" show-ref --verify --quiet "refs/remotes/origin/$2"
}

# ws_merged <gitdir> <branch> <base> — 0 если branch влита в origin/base.
ws_merged() {
    git -C "$1" show-ref --verify --quiet "refs/remotes/origin/$3" || return 1
    git -C "$1" merge-base --is-ancestor "$2" "origin/$3" 2>/dev/null
}

# ws_head <gitdir> <ref> — короткий hash.
ws_head() {
    git -C "$1" rev-parse --short "$2" 2>/dev/null || printf '?'
}

# ws_worktree_locked <gitdir> <worktree-path> — 0, если worktree залочен (git worktree lock).
# Залоченные worktree git держит, пока агент жив — уборкой их не трогаем.
ws_worktree_locked() {
    git -C "$1" worktree list --porcelain 2>/dev/null | awk -v p="$2" '
        /^worktree /{ cur=$2 }
        /^locked/  { if (cur==p) found=1 }
        END        { exit(found?0:1) }
    '
}
