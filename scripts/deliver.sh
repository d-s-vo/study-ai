#!/usr/bin/env bash
# deliver.sh — доставка ветки в клиентский origin (МОДУЛЬ M1, «контуры разведены»).
# ЗАПУСКАЕТ ТОЛЬКО ПОЛЬЗОВАТЕЛЬ. Единственный санкционированный путь пуша: выдаёт разрешение
# (.push-allow), временно возвращает рабочий pushurl, пушит и всё откатывает через trap.
#
# При совпадении контуров (внутренний одно-репный проект) — НЕ НУЖЕН: push делает ai-push.sh/
# человек напрямую; агент-развёртыватель удаляет этот файл.
#
# GENERIC-КОПИЯ. Имя репы валидируется по repos.conf (bare). # ADAPT: github.com/d-s-vo/nuxt4-ts-project-cbook и
# study-cbook-ai — под проект (см. ai/guides/stack-specifics.md).
#
# Usage:
#   deliver.sh <repo> <branch> [--dry-run]     # repo — bare-имя из repos.conf
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
WS_ROOT="$(dirname "$SCRIPT_DIR")"
. "$WS_ROOT/githooks/lib/scan.sh"
. "$SCRIPT_DIR/lib/workspace.sh"
. "$SCRIPT_DIR/lib/role.sh"

# Ролевой гвард (K-role, M5) — ДО разбора аргументов и TTY-гейта: изолированная сессия получает
# внятное «выполните на хосте» (exit 3). Слой ПОВЕРХ физической границы. На хосте прозрачен.
role_require_privileged "доставка в клиентский git"

PUSH_ALLOW="$WS_ROOT/.push-allow"
DISABLED_URL="DISABLED_use_deliver_sh"
say() { printf '%s\n' "$*" >&2; }
die() { say "ОШИБКА: $*"; exit 1; }

DRY=0
POS=""
for a in "$@"; do
    case "$a" in
        --dry-run) DRY=1 ;;
        -*) die "неизвестный флаг: $a" ;;
        *) POS="$POS $a" ;;
    esac
done
# shellcheck disable=SC2086
set -- $POS
[ "$#" -eq 2 ] || die "Usage: deliver.sh <repo> <branch> [--dry-run]  (repo — bare-имя из repos.conf)"
REPO="$1"; BRANCH="$2"

# --- Гейт «только человек»: реальный пуш требует интерактивного TTY. ---
if [ "$DRY" -ne 1 ] && [ ! -t 0 ]; then
    die "deliver.sh запускается только человеком в интерактивном терминале (реальный пуш требует TTY). Для проверки без пуша используйте --dry-run."
fi

# Валидация репы по repos.conf: обязана быть bare (двухконтурная модель M1).
CONF_LINE="$(ws_conf_lines | while IFS= read -r l; do
    [ "$(ws_name "$l")" = "$REPO" ] && printf '%s' "$l" && break
done)"
[ -n "$CONF_LINE" ] || die "репа '$REPO' не найдена в repos.conf."
[ "$(ws_type "$CONF_LINE")" = "bare" ] || die "репа '$REPO' не bare — доставка через deliver.sh не поддерживается."
BARE="$(ws_gitdir "$CONF_LINE")"
[ -d "$BARE" ] || die "bare-репозиторий не найден: $BARE"
export GIT_DIR="$BARE"

# 1. Проверка имени ветки и существования.
FORBIDDEN_BRANCH_RE='(feat-[0-9]|(^|/)ai[-_/]|claude|anthropic|study-cbook-ai|~wip~|(^|/)wip(-|/|$))'
if printf '%s\n' "$BRANCH" | grep -qiE -- "$FORBIDDEN_BRANCH_RE"; then
    die "имя ветки '$BRANCH' под запретом (feat-номер/ai/claude/wip)."
fi
git rev-parse --verify "refs/heads/$BRANCH" >/dev/null 2>&1 \
    || die "локальной ветки '$BRANCH' нет в $BARE."

# 2. Финальный скан всего исходящего диапазона (не на origin).
say "== Скан исходящих коммитов ветки '$BRANCH' =="
commits="$(git rev-list "$BRANCH" --not --remotes=origin 2>/dev/null)"
if [ -z "$commits" ]; then
    say "   (нет новых коммитов относительно origin — пушить нечего)"
fi
scan_fail=0
for c in $commits; do
    mrep="$(git log -1 --format='%B' "$c" 2>/dev/null | scan_stream)"
    drep="$(git show --no-color --format= "$c" 2>/dev/null \
              | grep -E '^\+' | grep -vE '^\+\+\+' | sed 's/^+//' | scan_stream)"
    # Автор/коммиттер (имя+почта) по стоп-словарю — след ИИ/агента в метаданных.
    arep="$(git log -1 --format='%an%n%ae%n%cn%n%ce' "$c" 2>/dev/null | scan_stream)"
    if [ -n "$mrep" ] || [ -n "$drep" ] || [ -n "$arep" ]; then
        say "  БЛОК: коммит $c"
        [ -n "$mrep" ] && printf '%s\n' "$mrep" >&2
        [ -n "$drep" ] && printf '%s\n' "$drep" >&2
        [ -n "$arep" ] && { say "  (автор/коммиттер содержит след):"; printf '%s\n' "$arep" >&2; }
        scan_fail=1
    fi
done
[ "$scan_fail" -eq 0 ] || die "найдены стоп-слова — доставка прервана."
say "   Чисто."

# 3. Реальный pushurl (из fetch url).
REAL_URL="$(git config --get remote.origin.url)"
[ -n "$REAL_URL" ] || die "не удалось получить remote.origin.url."

if [ "$DRY" -eq 1 ]; then
    say ""
    say "[DRY-RUN] Всё чисто. Реально было бы выполнено:"
    say "  echo '$BRANCH' >> $PUSH_ALLOW"
    say "  git remote set-url --push origin '$REAL_URL'   (временно)"
    say "  git push -u origin $BRANCH"
    say "  (затем откат pushurl -> $DISABLED_URL и удаление ветки из .push-allow)"
    exit 0
fi

# 3b. Интерактивное подтверждение человеком (реальный пуш; при --dry-run сюда не доходим).
ncommits="$(printf '%s\n' "$commits" | grep -c . 2>/dev/null)"
say ""
say "== ПОДТВЕРЖДЕНИЕ ДОСТАВКИ =="
say "  Репозиторий:      $REPO"
say "  Ветка:            $BRANCH"
say "  Коммитов к пушу:  ${ncommits:-0} (относительно origin)"
say "  Назначение:       $REAL_URL"
say ""
printf 'Введите имя ветки повторно для подтверждения (или пусто для отмены): ' >&2
IFS= read -r _confirm || _confirm=""
if [ "$_confirm" != "$BRANCH" ]; then
    die "подтверждение не совпало ('$_confirm' != '$BRANCH') — доставка отменена."
fi

# 4. Разрешение + временный pushurl + гарантированный откат.
cleanup() {
    git remote set-url --push origin "$DISABLED_URL" 2>/dev/null
    if [ -f "$PUSH_ALLOW" ]; then
        grep -vxF -- "$BRANCH" "$PUSH_ALLOW" > "$PUSH_ALLOW.tmp" 2>/dev/null
        mv "$PUSH_ALLOW.tmp" "$PUSH_ALLOW" 2>/dev/null
        [ -s "$PUSH_ALLOW" ] || rm -f "$PUSH_ALLOW" 2>/dev/null
    fi
    say "== Откат выполнен: pushurl=DISABLED, разрешение снято =="
}
trap cleanup EXIT INT TERM

# выдаём разрешение (без дублей)
touch "$PUSH_ALLOW"
grep -qxF -- "$BRANCH" "$PUSH_ALLOW" || printf '%s\n' "$BRANCH" >> "$PUSH_ALLOW"

# возвращаем рабочий pushurl
git remote set-url --push origin "$REAL_URL" || die "не удалось выставить pushurl."

say "== Пуш origin/$BRANCH =="
git push -u origin "$BRANCH"
rc=$?

exit $rc
