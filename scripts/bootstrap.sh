#!/usr/bin/env bash
# bootstrap.sh — идемпотентная (пере)настройка защит workspace. Повторный запуск ничего не
# ломает: только приводит конфиг к целевому состоянию.
#   Использование: bash scripts/bootstrap.sh [--skip-missing]
#     --skip-missing — не падать, если клиентскую репу нельзя склонировать (нет origin/доступа);
#                      по умолчанию недоступная репа = ЯВНАЯ ошибка (M1 не инстанцируется молча).
#   Инстанцирование клиентского контура (M1) из repos.conf:
#     - если .repos/<имя>.git отсутствует и задан origin (поле 7) — `git clone --bare` + worktree
#   Для клиентских реп (repos.conf):
#     - core.hooksPath = githooks/client
#     - remote.origin.pushurl = DISABLED_use_deliver_sh   (шлюз доставки — deliver.sh; M1)
#     - fetch refspec +refs/heads/*:refs/remotes/origin/*  (у bare)
#     - user.name / user.email = «человеческая» личность  ⇐ ЗАКРЫТИЕ ИНЦИДЕНТА (см. ниже)
#   Для корневого репо артефактов (.git):
#     - core.hooksPath = githooks/root
#     - pushurl НЕ трогаем (ai-push.sh — легальный канал)
#     - user.name / user.email — та же «человеческая» личность (консистентность метаданных)
#   Генерация .claude/settings.json из шаблона (абсолютные пути к хукам от корня workspace).
#   Права +x на хуки и скрипты слоя. Идемпотентен.
#
# ⚠ ИНВАРИАНТ БЕЗОПАСНОСТИ №8 (git-identity bare-клонов). Метаданные автора/коммиттера коммита
#   не должны выдавать агента/ИИ. Реальный инцидент: незаданный user.email в bare-клоне брал
#   `dev@local` (или иной локальный дефолт), перекрывая global → след в метаданных. deliver.sh/
#   pre-push ловят это ПОЗДНО (на доставке). Поэтому bootstrap ОБЯЗАН привести user.name/email
#   bare-клонов к «человеческой» личности заранее. # ADAPT: Dmitriy /
#   smirnov@whyme.agency — заполните реальными данными человека/команды.
set -u

SKIP_MISSING=0
for arg in "$@"; do
    case "$arg" in
        --skip-missing) SKIP_MISSING=1 ;;
        -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) printf 'Неизвестный аргумент: %s (см. --help)\n' "$arg" >&2; exit 2 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
: "${WS_ROOT:=$(dirname "$SCRIPT_DIR")}"
. "$SCRIPT_DIR/lib/workspace.sh"
MISSING=0

DISABLED_URL="DISABLED_use_deliver_sh"
CLIENT_HOOKS="$WS_ROOT/githooks/client"
ROOT_HOOKS="$WS_ROOT/githooks/root"

# --- git-identity (инвариант №8) ---
HUMAN_NAME="Dmitriy"
HUMAN_EMAIL="smirnov@whyme.agency"

ok()   { printf '%s  ok  %s%s\n'   "$WS_GRN" "$*" "$WS_RST"; }
set_c(){ printf '%s  set %s%s\n'   "$WS_YEL" "$*" "$WS_RST"; }
warn() { printf '%s  !!  %s%s\n'   "$WS_RED" "$*" "$WS_RST"; }

# cfg_ensure <gitdir> <key> <want> — выставить key=want, если отличается. Печатает изменение.
cfg_ensure() {
    _gd="$1"; _k="$2"; _w="$3"
    _cur="$(git -C "$_gd" config --local --get "$_k" 2>/dev/null || true)"
    if [ "$_cur" = "$_w" ]; then
        ok "$_k = $_w"
    else
        git -C "$_gd" config --local "$_k" "$_w"
        set_c "$_k : '$_cur' -> '$_w'"
    fi
}

# ensure_identity <gitdir> — выставить user.name/email в «человеческую» личность (инвариант №8).
# Отказ, если плейсхолдеры не заполнены (лучше громко упасть, чем записать литерал '{{...}}'
# как личность коммитов — это стало бы ещё худшим следом).
IDENTITY_OK=1
case "$HUMAN_NAME$HUMAN_EMAIL" in
    *'{{'*|'') IDENTITY_OK=0 ;;
esac
ensure_identity() {
    if [ "$IDENTITY_OK" -ne 1 ]; then
        warn "git-identity НЕ выставлена: заполните Dmitriy/smirnov@whyme.agency в bootstrap.sh."
        warn "  Без этого метаданные автора коммита могут выдать агента (инвариант безопасности №8)."
        return 0
    fi
    cfg_ensure "$1" user.name "$HUMAN_NAME"
    cfg_ensure "$1" user.email "$HUMAN_EMAIL"
}

# add_worktree <gitdir> <worktree-abs-path> <branch> — создать worktree, если его нет.
add_worktree() {
    _wgd="$1"; _wp="$2"; _wb="$3"
    [ -n "$_wp" ] && [ -n "$_wb" ] || return 0
    case "$_wp$_wb" in *'{{'*) return 0 ;; esac   # плейсхолдеры не заполнены — пропуск
    [ -d "$_wp" ] && { ok "worktree $_wp уже есть"; return 0; }
    if git -C "$_wgd" worktree add "$_wp" "$_wb" >/dev/null 2>&1 \
       || git -C "$_wgd" worktree add -b "$_wb" "$_wp" "origin/$_wb" >/dev/null 2>&1; then
        set_c "worktree создан: $_wp ($_wb)"
    else
        warn "не удалось создать worktree $_wp ($_wb) — создайте вручную (git worktree add)"
    fi
}

printf '%s== Настройка клиентских реп из repos.conf ==%s\n' "$WS_BLD" "$WS_RST"
while IFS= read -r line || [ -n "$line" ]; do
    name="$(ws_name "$line")"; type="$(ws_type "$line")"; gd="$(ws_gitdir "$line")"
    base="$(ws_base "$line")"; origin="$(ws_origin "$line")"; mainwt="$(ws_mainwt_abs "$line")"
    printf '%s- %s (%s) %s%s\n' "$WS_BLD" "$name" "$type" "$gd" "$WS_RST"

    # --- M1-инстанцирование: клонируем клиентскую репу по origin (поле 7 repos.conf) ---
    if [ ! -d "$gd" ]; then
        case "$origin" in
            ''|*'{{'*)
                if [ "$SKIP_MISSING" -eq 1 ]; then
                    warn "нет клона $gd, origin не задан — пропуск (--skip-missing)"; continue
                fi
                warn "нет клона $gd, а origin (поле 7 repos.conf) пуст/плейсхолдер."
                warn "  Укажите origin-URL репы (на git-хосте клиента) в repos.conf, либо --skip-missing."
                MISSING=$((MISSING+1)); continue ;;
        esac
        mkdir -p "$(dirname "$gd")"
        if [ "$type" = "bare" ]; then
            if git clone --bare "$origin" "$gd" >/dev/null 2>&1; then
                set_c "склонирован bare: $origin -> $gd"
            else
                if [ "$SKIP_MISSING" -eq 1 ]; then warn "clone не удался — пропуск (--skip-missing)"; continue; fi
                warn "git clone --bare '$origin' '$gd' не удался — проверьте URL/доступ/SSH-ключ/хост."
                MISSING=$((MISSING+1)); continue
            fi
        else
            if git clone "$origin" "$gd" >/dev/null 2>&1; then
                set_c "склонирован: $origin -> $gd"
            else
                if [ "$SKIP_MISSING" -eq 1 ]; then warn "clone не удался — пропуск (--skip-missing)"; continue; fi
                warn "git clone '$origin' '$gd' не удался — проверьте URL/доступ."
                MISSING=$((MISSING+1)); continue
            fi
        fi
    fi

    cfg_ensure "$gd" core.hooksPath "$CLIENT_HOOKS"
    cfg_ensure "$gd" remote.origin.pushurl "$DISABLED_URL"
    if [ "$type" = "bare" ]; then
        cfg_ensure "$gd" remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
        git -C "$gd" fetch origin >/dev/null 2>&1 || true
    fi
    # ИНВАРИАНТ №8: «человеческая» личность коммитов в клиентской репе.
    ensure_identity "$gd"

    # Основные worktree (M1): интеграционный + доп. (prod и т.п.), если отсутствуют.
    if [ "$type" = "bare" ]; then
        add_worktree "$gd" "$mainwt" "$base"
        while IFS="$(printf '\t')" read -r _en _eb; do
            [ -n "$_en" ] || continue
            add_worktree "$gd" "$WS_ROOT/$_en" "$_eb"
        done <<EOX
$(ws_extra_worktrees "$line")
EOX
    fi
done <<EOF
$(ws_conf_lines)
EOF

if [ "$MISSING" -gt 0 ]; then
    warn "$MISSING реп(ы) не инстанцированы — исправьте repos.conf/доступ и повторите bootstrap (или --skip-missing)."
    if [ "$SKIP_MISSING" -eq 0 ]; then
        exit 1
    fi
fi

printf '\n%s== Корневой репозиторий артефактов (.git) ==%s\n' "$WS_BLD" "$WS_RST"
if git -C "$WS_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    if [ -d "$ROOT_HOOKS" ]; then
        cfg_ensure "$WS_ROOT" core.hooksPath "$ROOT_HOOKS"
    else
        warn "нет каталога хуков $ROOT_HOOKS — core.hooksPath не выставлен"
    fi
    ensure_identity "$WS_ROOT"
    ROOT_PUSHURL="$(git -C "$WS_ROOT" config --local --get remote.origin.pushurl 2>/dev/null || true)"
    if [ -n "$ROOT_PUSHURL" ] && [ "$ROOT_PUSHURL" = "$DISABLED_URL" ]; then
        warn "pushurl корня отключён — ai-push.sh не сможет пушить. Уберите: git -C $WS_ROOT config --unset remote.origin.pushurl"
    else
        ok "pushurl корня не заблокирован (ai-push.sh работает)"
    fi
else
    warn "корень не является git-репозиторием"
fi

# ---------------------------------------------------------------------------
# Генерация .claude/settings.json из шаблона (абсолютные пути к хукам от корня).
# Шаблон .claude/settings.json.template содержит токен {{WORKSPACE_ROOT}}; bootstrap
# подставляет $WS_ROOT и пишет .claude/settings.json (защищённый guard-write.sh — первичную
# настройку делает bootstrap/человек). Повторный запуск перегенерирует из шаблона.
# ---------------------------------------------------------------------------
printf '\n%s== .claude/settings.json (абсолютные пути хуков) ==%s\n' "$WS_BLD" "$WS_RST"
STPL="$WS_ROOT/.claude/settings.json.template"
SOUT="$WS_ROOT/.claude/settings.json"
if [ -f "$STPL" ]; then
    _stmp="$SOUT.tmp.$$"
    if sed "s#{{WORKSPACE_ROOT}}#$WS_ROOT#g" "$STPL" > "$_stmp" 2>/dev/null; then
        if command -v jq >/dev/null 2>&1 && ! jq -e . "$_stmp" >/dev/null 2>&1; then
            rm -f "$_stmp"; warn "сгенерированный settings.json невалиден (jq) — не записан."
        else
            mv "$_stmp" "$SOUT" && set_c "сгенерирован $SOUT (пути от $WS_ROOT)"
        fi
    else
        rm -f "$_stmp"; warn "не удалось сгенерировать settings.json из шаблона."
    fi
else
    warn "шаблон $STPL не найден — .claude/settings.json не сгенерирован (настройте вручную)."
fi

printf '\n%s== Права на исполнение ==%s\n' "$WS_BLD" "$WS_RST"
CHANGED=0
for d in "$WS_ROOT/githooks/client" "$WS_ROOT/githooks/root" "$WS_ROOT/githooks"; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
        [ -f "$f" ] || continue
        case "$f" in *.txt|*.md) continue ;; esac
        if [ ! -x "$f" ]; then chmod +x "$f" 2>/dev/null && CHANGED=$((CHANGED+1)); fi
    done
done
for f in "$SCRIPT_DIR"/*.sh "$SCRIPT_DIR"/lib/*.sh; do
    [ -f "$f" ] || continue
    if [ ! -x "$f" ]; then chmod +x "$f" 2>/dev/null && CHANGED=$((CHANGED+1)); fi
done
if [ "$CHANGED" -eq 0 ]; then ok "все хуки и скрипты уже исполняемы"
else set_c "проставлен +x на $CHANGED файлов"; fi

printf '\n%sГотово. Повторный запуск идемпотентен.%s\n' "$WS_BLD" "$WS_RST"
