---
repo: cbook
authored_hash: cc3df94f9ca4ef22e87e33dfe6c32e9a12632804
patch_id: 4cf21d0b3c4a7f0a5f3554a5b2cea30c760f190c
feat: FEAT-005
branch: feat/infra-toolchain
reviewer_model: Opus 4.8
review_date: 2026-07-31
verdict: PASS
blockers_total: 0
blockers_open: 0
resolved_by: []
---

# cbook@cc3df94 — REVIEW — fix: указать версию pnpm в CI

**Verdict:** PASS
**Blocking findings:**
- нет
**Non-blocking notes:**
- нет
**Evidence:**
- **Узкий скоуп §6** (фикс blocker'а ревью `74fe7ab-review.md`); `trivial-scope` по объёму (2×2 строки,
  один файл `.github/workflows/ci.yml`), но проверен по существу как закрытие blocker'а.
- `git show cc3df94`: единственное изменение — `with: version: 10` добавлен к ОБОИМ шагам
  `pnpm/action-setup@v4` (job `tests`, строка 74→75-76; job `frontend`, строка 99→101-102). Ничего
  больше в дифе нет; `package.json` не тронут (зона FEAT-008 не задета).
- **Находка закрыта:** по README `pnpm/action-setup` v4 вход `version` обязателен, когда в
  `package.json` нет `packageManager` — теперь задан; мажор-указание `10` резолвится действием в
  актуальный pnpm 10.x. Шаг «Setup pnpm» больше не падает; `cache: pnpm` у setup-node снова получает
  рабочий pnpm в PATH.
- **Совместимость с lockfile:** `pnpm-lock.yaml` — `lockfileVersion: '9.0'` (формат pnpm 9/10);
  локальный зелёный `pnpm install --frozen-lockfile` + `pnpm build` шли на pnpm 10.30.3 — тот же
  мажор, что резолвит CI → расхождения фрозен-лока не будет.
- **Регрессии:** нет — прочие шаги/джобы не изменены (сверка контекста дифа).
- **Стоп-словарь по дифу** (`githooks/stopwords.txt`, grep -iE): чисто; сообщение коммита
  `fix: указать версию pnpm в CI` — conventional (`fix:`), «от лица человека», без следов
  системы/FEAT-номеров.
**Suggested next:** none

## Рубрика (сокращённая, узкий скоуп §6 + trivial-scope)

☑ Находка `74fe7ab-review.md` Blocking #1 закрыта · ☑ Регрессий вокруг нет (диф минимален)
☑ Атомарность (один смысл: версия pnpm в CI) · ☑ Чистота (стоп-словарь чист, conventional message)

## Журнал закрытия находок

- Находок нет. Этот коммит сам закрывает Blocking #1 ревью `74fe7ab-review.md` (отметка — там).

## Связи

- Исходное ревью с blocker'ом: `74fe7ab-review.md` (рядом; вердикт цепочки обновлён на PASS).
- Разбор «почему» исходного коммита (ADR-009): `74fe7ab-infra-toolchain.md`.
- Фича: `../../features/FEAT-005-infra-toolchain/impl.md` · `spec.md`.
- Гайд ревью: [`../../guides/commit-review.md`](../../guides/commit-review.md) §6 (фикс-цикл, узкий скоуп).
