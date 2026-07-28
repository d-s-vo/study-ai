#!/usr/bin/env bash
# claude-pretool.sh — PreToolUse hook Claude Code для matcher Bash.  ⇐ ИНВАРИАНТЫ №1,2,3,4.
# Читает JSON события со stdin, достаёт .tool_input.command и .cwd и решает:
#   exit 0 — разрешить; exit 2 — заблокировать (причина в stderr).
# Блокирует: git push; правку .push-allow; git remote set-url; запуск deliver.sh;
#            обход хуков (--no-verify/-n, core.hooksPath, индирекция/eval/GIT_DIR);
#            обращение к git-хосту клиента; git/сеть через интерпретатор; sh -c с git;
#            git stash в общем worktree; git commit со стоп-словами В КОНТЕКСТЕ КЛИЕНТСКОЙ репы.
#
# GENERIC-КОПИЯ (МОДУЛЬ M1/M6). # ADAPT: github.com/d-s-vo/nuxt4-ts-project-cbook — git-хост клиента;
# cbook|prod — имена клиентских worktree-каталогов через | (из repos.conf:
# main-worktree и extra-worktree). При M6=OFF (внутренний проект, push агенту разрешён)
# антипуш-часть упрощается; антиобход-хуков и stash-блок остаются полезны везде.
set -u

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"   # .../githooks
WS_ROOT="$(dirname "$HOOK_DIR")"                               # корень workspace
. "$HOOK_DIR/lib/scan.sh"

deny() { printf 'ЗАБЛОКИРОВАНО охранной обвязкой: %s\n' "$*" >&2; exit 2; }

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -z "$cmd" ] && exit 0

# 0. Запуск deliver.sh агентом запрещён (доставка — только человек в TTY, см. deliver.sh).
if printf '%s\n' "$cmd" | grep -qE 'deliver\.sh'; then
    deny "запуск scripts/deliver.sh. Доставка в клиентскую репу — только пользователем в интерактивном терминале."
fi

# 1. Прямой git push запрещён (доставка — только через deliver.sh пользователем).
if printf '%s\n' "$cmd" | grep -qE '(^|[^[:alnum:]_-])git([[:space:]]+[^[:space:]]+)*[[:space:]]+push([[:space:]]|$)'; then
    deny "прямой 'git push'. Доставка в клиентскую репу — только пользователем через scripts/deliver.sh."
fi

# 1b. Обход хуков через --no-verify / -n у git commit|push запрещён.
if printf '%s\n' "$cmd" | grep -qE '(^|[^[:alnum:]_-])git([[:space:]]+[^[:space:]]+)*[[:space:]]+(commit|push)([[:space:]]|$)'; then
    if printf '%s\n' "$cmd" | grep -qE '(^|[[:space:]])--no-verify([[:space:]]|=|$)' \
       || printf '%s\n' "$cmd" | grep -qE '(^|[[:space:]])-n([[:space:]]|$)'; then
        deny "обход хуков ('--no-verify' / '-n') запрещён. Коммит/пуш обязаны проходить охранную обвязку."
    fi
fi

# 1c. Переопределение пути хуков через core.hooksPath (обход всей обвязки) запрещено.
if printf '%s\n' "$cmd" | grep -qiE '(^|[^[:alnum:]_-])git([[:space:]]+[^[:space:]]+)*[[:space:]]+-c[[:space:]]*core\.hookspath' \
   || printf '%s\n' "$cmd" | grep -qiE '(^|[^[:alnum:]_-])git([[:space:]]+[^[:space:]]+)*[[:space:]]+config([[:space:]]|$).*core\.hookspath'; then
    deny "переопределение core.hooksPath запрещено (обход охранной обвязки)."
fi

# 1d. Индирекция: подкоманда git подставляется через переменную ('git $g ...', 'git "$c"').
if printf '%s\n' "$cmd" | grep -qE '(^|[^[:alnum:]_-])git[[:space:]]+["'\'']?\$'; then
    deny "непрямые формы git запрещены (подкоманда через переменную скрывает push/commit от обвязки)."
fi

# 1e. eval с git внутри (скрывает реальную git-команду от разбора).
if printf '%s\n' "$cmd" | grep -qE '(^|[^[:alnum:]_-])eval([[:space:]]|$)' \
   && printf '%s\n' "$cmd" | grep -qE '(^|[^[:alnum:]_-])git([[:space:]]|$)'; then
    deny "eval с git запрещён (скрывает git-команду от охранной обвязки)."
fi

# 1f. Подмена GIT_DIR / GIT_WORK_TREE вместе с git (увод команды в чужой репо/обход хуков).
if printf '%s\n' "$cmd" | grep -qE '(^|[^[:alnum:]_-])(GIT_DIR|GIT_WORK_TREE)=' \
   && printf '%s\n' "$cmd" | grep -qE '(^|[^[:alnum:]_-])git([[:space:]]|$)'; then
    deny "переопределение GIT_DIR/GIT_WORK_TREE вместе с git запрещено (обход охранной обвязки)."
fi

# 1g. Прямое обращение к git-хосту клиента любым каналом (curl/wget/gh/git с URL/ssh) —
#     обход шлюза доставки deliver.sh.
if printf '%s\n' "$cmd" | grep -qiE 'github.com/d-s-vo/nuxt4-ts-project-cbook'; then
    deny "прямое обращение к git-хосту клиента запрещено (github.com/d-s-vo/nuxt4-ts-project-cbook). Доставка — только через scripts/deliver.sh пользователем."
fi

# 1h. Запуск git/сети через интерпретатор (python/node/perl/ruby с инлайн-кодом), скрывающий
#     git-push / subprocess / сетевой вызов от разбора. Блокируем ТОЛЬКО если инлайн-код реально
#     трогает git/сеть — легитимная разработка (без git/сети) проходит свободно.
_interp_inline='(^|[^[:alnum:]_.-])(python[0-9.]*[[:space:]]+-c|node[[:space:]]+(-e|--eval)|perl[[:space:]]+-e|ruby[[:space:]]+-e)([[:space:]]|$)'
_net_git_kw='(^|[^[:alnum:]_])(git|push|subprocess|socket|urllib|requests)([^[:alnum:]_]|$)'
if printf '%s\n' "$cmd" | grep -qE "$_interp_inline" \
   && printf '%s\n' "$cmd" | grep -qiE "$_net_git_kw"; then
    deny "запуск git/сети через интерпретатор запрещён (python -c / node -e / perl -e / ruby -e с git/push/subprocess/socket/urllib/requests). Обвязка не может разобрать такой код."
fi

# 1i. sh -c / bash -c / zsh -c с git внутри — увод git-команды от разбора обвязки.
#     'ssh -c' сюда НЕ попадает ('sh' в 'ssh' предваряется alnum-символом).
if printf '%s\n' "$cmd" | grep -qE '(^|[^[:alnum:]_-])(sh|bash|zsh)[[:space:]]+-c([[:space:]]|$)' \
   && printf '%s\n' "$cmd" | grep -qiE '(^|[^[:alnum:]_])git([^[:alnum:]_]|$)'; then
    deny "'sh -c'/'bash -c'/'zsh -c' с git внутри запрещён (скрывает git-команду от охранной обвязки)."
fi

# 2. Правка файла-разрешения .push-allow.
if printf '%s\n' "$cmd" | grep -qE '\.push-allow'; then
    deny "обращение к .push-allow. Файл-разрешение выдаёт только пользователь/deliver.sh."
fi

# 3. Подмена remote / pushurl.
if printf '%s\n' "$cmd" | grep -qE 'git([[:space:]]+[^[:space:]]+)*[[:space:]]+remote[[:space:]]+set-url' \
   || printf '%s\n' "$cmd" | grep -qE 'git[[:space:]]+config[[:space:]].*remote\.[^[:space:]]+\.(push)?url'; then
    deny "изменение remote/pushurl запрещено (обход шлюза доставки)."
fi

# --- определение контекста клиентской репы по cwd (для §4 и §5). ---
# ADAPT: cbook|prod — имена клиентских worktree-каталогов; tasks/.repos — общие.
client_ctx=0
case "$cwd" in
    "$WS_ROOT"/*)
        _rel="${cwd#"$WS_ROOT"/}"; _first="${_rel%%/*}"
        case "$_first" in
            cbook|prod|tasks|.repos)
                client_ctx=1 ;;
        esac
        ;;
esac
# команда явно нацелена на клиентское дерево через 'git -C <клиентский путь>'
if printf '%s\n' "$cmd" | grep -qE '(^|[^[:alnum:]_-])git[[:space:]]+-C[[:space:]]+[^[:space:]]*(cbook|prod|tasks|\.repos)'; then
    client_ctx=1
fi

# 4. git stash в общем worktree запрещён (ИНВАРИАНТ №4). Task-worktree делят общий .git bare-репо:
#    stash одного видят все, риск потери/путаницы. Политика CLAUDE.md/security-rails.md — запрет.
if [ "$client_ctx" -eq 1 ] \
   && printf '%s\n' "$cmd" | grep -qE '(^|[^[:alnum:]_-])git([[:space:]]+[^[:space:]]+)*[[:space:]]+stash([[:space:]]|$)'; then
    deny "'git stash' в общем worktree запрещён (общий .git — stash виден всем worktree; риск потери). См. CLAUDE.md / ai/ops/security-rails.md."
fi

# 5. git commit со стоп-словами — сканируем ТОЛЬКО в контексте КЛИЕНТСКОЙ репы.
#    Корневой репо артефактов легитимно содержит следы системы; стоп-скан коммит-сообщения
#    там НЕ применяем (клиентские commit-msg хуки остаются вторым рубежом в любом случае).
if [ "$client_ctx" -eq 1 ] \
   && printf '%s\n' "$cmd" | grep -qE 'git([[:space:]]+[^[:space:]]+)*[[:space:]]+commit'; then
    report="$(scan_string "$cmd")"
    if [ -n "$report" ]; then
        printf 'ЗАБЛОКИРОВАНО: git commit со стоп-словами в команде:\n%s\n' "$report" >&2
        exit 2
    fi
fi

exit 0
