<!--
ШАБЛОН REVIEW-ФАЙЛА (ADR-010). Копировать в ai/devlog/commits/<repo>/<short-hash>-review.md
Правила заполнения (полный гайд — ../../guides/commit-review.md):
  • Пишет ТОЛЬКО ревьюер (независимый агент, чистый контекст), НЕ автор коммита. Файл-разбор автора
    (<short-hash>-<slug>.md, ADR-009) НЕ трогать — это отдельная роль/автор.
  • Verdict — в ПЕРВЫХ 5 строках тела (оркестратор парсит сверху); имена полей канона неизменны.
  • Каждая blocking-находка ОБЯЗАНА нести Evidence (file:line + контрпример). Без Evidence — не blocker (→ WARN).
  • short-hash — as-authored (тот же, что у разбора ADR-009), НЕ финальный клиентский хеш.
  • trivial-scope (doc-only/косметика без изменения поведения) — сокращённая рубрика, пометить в Evidence.
  • Порядок артефактов (гайд §5): СНАЧАЛА этот review-файл коммитом ai-commit.sh, ЗАТЕМ строка
    «Реестра ревью» ../README.md через edit-shared.sh — два отдельных коммита, реестр вторичен.
-->
---
repo: <repo-slug>             # одно из cbook
authored_hash: <full-sha>     # SHA на feat/<slug> в момент коммита (стабильный ключ, как ADR-009)
patch_id: <patch-id>          # git show <hash> | git patch-id --stable
feat: FEAT-NNN
branch: feat/<slug>
reviewer_model: Opus 4.8
review_date: YYYY-MM-DD
verdict: PASS                 # PASS | WARN | FAIL
blockers_total: 0
blockers_open: 0
resolved_by: []               # [<hash-фикса>, …] — фикс-коммиты, закрывшие blocker
---

# <repo>@<short-hash> — REVIEW — <заголовок коммита>

**Verdict:** PASS | WARN | FAIL
**Blocking findings:**
- file:line — нарушение + Evidence (контрпример/путь)   # пусто при PASS
**Non-blocking notes:**
- file:line — предупреждение / рекомендация (severity: minor|nit)
**Evidence:**
- <команды / выводы / что проверил>   # при trivial-scope — пометить здесь
**Suggested next:** fix-now | fix-forward-FEAT-NNN | advisory | none

## Рубрика (бинарно, commit-review.md §3)

□ Атомарность/целостность · □ Логика vs спека/интент · □ Business-security (OWASP)
□ Тихие регрессии/parity · □ Тесты (мутационно: какую мутацию ловит каждый новый тест)
□ N+1/перф · □ Over-engineering
<!-- trivial-scope: атомарность + подтверждение отсутствия изменения поведения + чистота. -->

## Журнал закрытия находок

<!-- История статуса — записями, не правкой чужих строк. -->
- <blocker> → фикс-коммит <hash> (узкое ревью §6: закрыта находка + нет регрессии) → закрыт
- <WARN>   → принят оркестратором <дата>, причина … | закрыт фиксом <hash>

## Связи

<!-- Только ссылки, без пересказа. -->
- Разбор «почему» (автор, ADR-009): `<short-hash>-<slug>.md` (файл-разбор рядом).
- Фича: `../features/FEAT-NNN-slug/impl.md` · spec (подставь реальный FEAT-slug).
- ADR/keystone: `../../adr/NNN-slug.md` (если коммит затрагивает архитектурное решение).
- Гайд ревью: [`../../guides/commit-review.md`](../../guides/commit-review.md).
