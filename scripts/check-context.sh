#!/usr/bin/env bash
#
# check-context.sh — верификатор развёртывания системы агентской разработки.
#
# Запуск из корня workspace:
#   bash scripts/check-context.sh
#   bash scripts/check-context.sh --allow-todo   # TODO/ADAPT → warn, не fail
#
# Проверяет (наследник ../ai-context-template check-context.sh, расширен под шаблон):
#   (a) остатки незаполненных плейсхолдеров {{...}}
#   (b) остатки снимаемых маркеров <!-- TODO: / <!-- ADAPT: / <!-- /ADAPT -->
#   (c) битые относительные markdown-ссылки на .md
#   (d) висящие маркеры модульности <!-- MODULE:Mx BEGIN/END --> (в т.ч. описательная форма
#       <!-- MODULE:Mx BEGIN — текст -->; после развёртывания их быть НЕ должно)
#   (e) наличие обязательных (НЕотключаемых) файлов
#   (f) остаточные постоянные # ADAPT: — info (НЕ fail): это нормально, указатели на stack-specifics
#   (g) ссылки на несуществующие файлы гайдов/скриптов/adr (в т.ч. удалённые файлы OFF-модулей) — warn
#
# Зависимости: bash 3.2 + grep + find (portable, без привязки к стеку проекта).
# Exit: 0 — чисто; 1 — есть находки (problem); 2 — ошибка вызова.

set -u

# --- аргументы ---
ALLOW_TODO=0
for arg in "$@"; do
  case "$arg" in
    --allow-todo) ALLOW_TODO=1 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *)
      echo "Неизвестный аргумент: $arg (см. --help)" >&2
      exit 2 ;;
  esac
done

# --- корень workspace = родитель каталога scripts/ ---
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

if [ ! -d "$ROOT/ai" ]; then
  echo "Не найден каталог ai/ (ожидался в корне: $ROOT)" >&2
  exit 2
fi

PROBLEMS=0
WARNINGS=0
INFOS=0

section() { printf '\n=== %s ===\n' "$1"; }
problem() { printf '  [!] %s\n' "$1"; PROBLEMS=$((PROBLEMS + 1)); }
warn()    { printf '  [~] %s\n' "$1"; WARNINGS=$((WARNINGS + 1)); }
info()    { printf '  [i] %s\n' "$1"; INFOS=$((INFOS + 1)); }

# Все .md внутри workspace, кроме мусора и самого шаблона (если лежит рядом).
md_files() {
  find "$ROOT" -type f -name '*.md' \
    -not -path '*/.git/*' \
    -not -path '*/node_modules/*' \
    -not -path '*/agent-dev-system-template/*' \
    -not -path '*/.repos/*' \
    -not -path '*/tasks/*' \
    -not -path "$ROOT/cbook/*" \
    -not -path "$ROOT/prod/*" \
    -not -path '*/local/*'
}

# Все текстовые файлы для скана плейсхолдеров: .md + скрипты/конфиги/хуки (в т.ч. без расширения,
# как githooks/client/pre-commit). Исключаются *.template — там WORKSPACE_ROOT легитимен до
# bootstrap (контракт). Так плейсхолдеры в *.sh/*.conf/*.txt/хуках не проходят «зелёными» (иначе
# невырезанный CLIENT_GIT_HOST в pretool или COMMIT_MSG_FORMAT в commit.sh уедут молча).
scan_files() {
  find "$ROOT" -type f \
    -not -path '*/.git/*' \
    -not -path '*/node_modules/*' \
    -not -path '*/agent-dev-system-template/*' \
    -not -path '*/.repos/*' \
    -not -path '*/tasks/*' \
    -not -path "$ROOT/cbook/*" \
    -not -path "$ROOT/prod/*" \
    -not -path '*/local/*' \
    -not -name '*.template'
}

# --- (a) плейсхолдеры {{...}} во ВСЕХ файлах (md + скрипты/конфиги/хуки; *.template исключены) ---
section "(a) Незаполненные плейсхолдеры {{...}}"
FOUND_A=0
while IFS= read -r f; do
  # канонические UPPER_SNAKE-плейсхолдеры — problem (обязаны быть вырезаны при развёртывании).
  # WORKSPACE_ROOT исключён: он легитимно остаётся как sed-паттерн в bootstrap.sh (перезапускаемом)
  # и в *.template до bootstrap — этим управляет сам bootstrap, вручную снимать не нужно.
  while IFS= read -r line; do
    problem "$line"; FOUND_A=1
  done < <(grep -nE '\{\{[A-Z0-9_]+\}\}' "$f" | grep -v '{{WORKSPACE_ROOT}}' | sed "s#^#${f#$ROOT/}:#")
  # прозаические/кириллические/вложенные {{ ... }} (любой символ внутри вне [A-Z0-9_]) — warn:
  # незаполненный скелет-слот (architecture §1-11, adr/000-template, {{Принят}}, {{при M6=ON}} и т.п.)
  # не должен пройти «зелёным». Канонические UPPER_SNAKE-плейсхолдеры сюда не попадают (они — problem выше).
  while IFS= read -r line; do
    warn "$line"; FOUND_A=1
  done < <(grep -nE '\{\{[^{}]*[^A-Z0-9_{}][^{}]*\}\}' "$f" | sed "s#^#${f#$ROOT/}:#")
done < <(scan_files)
[ "$FOUND_A" -eq 0 ] && echo "  ок — плейсхолдеров не осталось"

# --- (b) снимаемые маркеры TODO / ADAPT (HTML) ---
section "(b) Маркеры <!-- TODO: --> / <!-- ADAPT: -->"
FOUND_B=0
report_b() { if [ "$ALLOW_TODO" -eq 1 ]; then warn "$1"; else problem "$1"; fi; }
while IFS= read -r f; do
  while IFS= read -r line; do
    report_b "$line"; FOUND_B=1
  done < <(grep -nE '<!--[[:space:]]*(TODO|ADAPT):|<!--[[:space:]]*/ADAPT[[:space:]]*-->' "$f" | sed "s#^#${f#$ROOT/}:#")
done < <(md_files)
if [ "$FOUND_B" -eq 0 ]; then
  echo "  ок — снимаемых маркеров не осталось"
elif [ "$ALLOW_TODO" -eq 1 ]; then
  echo "  (--allow-todo: маркеры засчитаны как warning, не fail)"
fi

# --- (c) битые относительные .md-ссылки ---
section "(c) Битые относительные markdown-ссылки на .md"
FOUND_C=0
while IFS= read -r f; do
  fdir=$(dirname "$f")
  while IFS= read -r link; do
    [ -z "$link" ] && continue
    case "$link" in
      http://*|https://*|mailto:*|\#*) continue ;;
    esac
    case "$link" in
      *.md|*.md#*) ;;
      *) continue ;;
    esac
    target=${link%%#*}
    [ -z "$target" ] && continue
    if [ ! -f "$fdir/$target" ]; then
      problem "${f#$ROOT/} → $link (файл не найден)"
      FOUND_C=1
    fi
  done < <(grep -oE '\]\([^)]+\)' "$f" | sed -E 's/^\]\(//; s/\)$//')
done < <(md_files)
[ "$FOUND_C" -eq 0 ] && echo "  ок — все .md-ссылки ведут на существующие файлы"

# --- (d) висящие маркеры модульности <!-- MODULE:Mx BEGIN/END --> ---
# После развёртывания их быть НЕ должно: OFF-блоки удалены целиком, у ON — сняты строки-маркеры.
section "(d) Висящие маркеры <!-- MODULE:Mx --> (должно быть 0)"
FOUND_D=0
BEG=0; END=0
while IFS= read -r f; do
  while IFS= read -r line; do
    problem "$line"; FOUND_D=1
    case "$line" in
      *BEGIN*) BEG=$((BEG+1)) ;;
      *END*)   END=$((END+1)) ;;
    esac
  done < <(grep -nE '<!--[[:space:]]*MODULE:[A-Z0-9]+[[:space:]]+(BEGIN|END)([[:space:]].*)?-->' "$f" | sed "s#^#${f#$ROOT/}:#")
done < <(md_files)
if [ "$FOUND_D" -eq 0 ]; then
  echo "  ок — маркеров модульности не осталось"
else
  [ "$BEG" -ne "$END" ] && problem "непарность MODULE-маркеров: BEGIN=$BEG END=$END (проверь Шаг 7)"
fi

# --- (e) обязательные (НЕотключаемые) файлы ---
# Свери со списком «НЕотключаемое ядро» в docs/module-matrix.md. Правь под именование проекта.
section "(e) Обязательные (НЕотключаемые) файлы"
REQUIRED="CLAUDE.md ai/architecture.md ai/memory.md ai/guides/feature-workflow.md ai/guides/commit-review.md ai/guides/live-acceptance.md ai/guides/debugging.md ai/guides/briefs/commit-reviewer.md ai/adr/README.md ai/adr/000-template.md scripts/repos.conf scripts/gate.sh scripts/lib/coord.sh githooks/guard-write.sh"
FOUND_E=0
for rel in $REQUIRED; do
  if [ ! -e "$ROOT/$rel" ]; then
    problem "отсутствует обязательный файл: $rel"; FOUND_E=1
  fi
done
[ "$FOUND_E" -eq 0 ] && echo "  ок — все обязательные файлы на месте"

# --- (f) остаточные постоянные # ADAPT: — info, НЕ fail ---
# Это НОРМА: постоянные указатели на stack-specifics.md, они остаются навсегда (см. AGENT-PROMPT).
section "(f) Постоянные # ADAPT: (норма, info)"
ADAPT_N=$(md_files | xargs grep -lE '(^|[^<])#[[:space:]]*ADAPT:' 2>/dev/null | wc -l | tr -d ' ')
if [ "${ADAPT_N:-0}" -gt 0 ]; then
  info "# ADAPT: встречается в $ADAPT_N файлах — это ПОСТОЯННЫЕ маркеры, снимать их НЕ нужно"
else
  echo "  (постоянных # ADAPT: не найдено)"
fi

# --- (g) ссылки на несуществующие файлы гайдов/скриптов/adr (в т.ч. удалённые файлы OFF-модулей) ---
# Backtick-обёрнутые пути под известными корнями; warn (эвристика, возможны примеры).
section "(g) Ссылки на возможно удалённые файлы (warn)"
FOUND_G=0
while IFS= read -r f; do
  while IFS= read -r tok; do
    [ -z "$tok" ] && continue
    case "$tok" in
      scripts/*|githooks/*|ai/*) cand="$ROOT/$tok" ;;
      guides/*|adr/*|devlog/*|ops/*|process-metrics/*|coord/*|reference/*|infra/*) cand="$ROOT/ai/$tok" ;;
      *) continue ;;
    esac
    if [ ! -e "$cand" ]; then
      warn "${f#$ROOT/}: \`$tok\` — файл не найден (удалён по профилю? поправь ссылку)"
      FOUND_G=1
    fi
  done < <(grep -oE '`[A-Za-z0-9_./-]+\.(sh|md|conf|txt)`' "$f" | tr -d '`' | sort -u)
done < <(md_files)
[ "$FOUND_G" -eq 0 ] && echo "  ок — подозрительных ссылок на файлы не найдено"

# --- итог ---
section "Итог"
echo "  проблем: $PROBLEMS   предупреждений: $WARNINGS   info: $INFOS"
echo "  Напоминание: зелёный выход — НЕОБХОДИМОЕ, но НЕ достаточное условие."
echo "  Пройди смысловой чеклист (AGENT-PROMPT.md Шаг 11) и тройную перепроверку (Шаг 12)."
if [ "$PROBLEMS" -gt 0 ]; then
  echo "  РЕЗУЛЬТАТ: есть находки → исправь (exit 1)"
  exit 1
fi
echo "  РЕЗУЛЬТАТ: механически чисто (exit 0)"
exit 0
