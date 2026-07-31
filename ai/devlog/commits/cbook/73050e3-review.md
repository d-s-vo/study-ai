---
repo: cbook
authored_hash: 73050e32c51eeb9fc29529784db388f69cb695b8
patch_id: fc611a67b819c7d5844049cb5ae059d9410d6546
feat: FEAT-009
branch: feat/recipe-data-layer
reviewer_model: Opus 4.8
review_date: 2026-07-31
verdict: PASS
blockers_total: 0
blockers_open: 0
resolved_by: []
---

# cbook@73050e3 — REVIEW — refactor: единообразие типов дат в RecipeData и осмысленная проверка синхронизации ингредиентов

**Verdict:** PASS
**Blocking findings:**
- (нет)
**Non-blocking notes:**
- (нет)
**Evidence:**
- Follow-up к advisory-нотам ревью `c48543f` (PASS): узкий скоуп §6 — (1) закрыты ли обе конкретные ноты; (2) нет ли регрессии от фикса. Дифф — 2 файла, +8/−2.
- **Нота 1 (единообразие дат) закрыта корректно.** `RecipeData::created_at/updated_at` `?string → ?CarbonImmutable` — приведено к типу `UserData` (проверил: `app/Data/UserData.php` использует тот же `?CarbonImmutable`). TS-контракт неизменен: `replaceType(CarbonImmutable → 'string')` в `TypeScriptTransformerServiceProvider` → поле остаётся `string | null`; регенерация `typescript:transform` → `git diff generated.d.ts` **пусто** (детерминизм подтверждён).
- **Нота 2 (вакуумная ассерция) закрыта корректно.** Мёртвая `assertDatabaseMissing(...'Salt','quantity'=>999)` заменена на: фиксация `$originalIds = $recipe->ingredients()->pluck('id')->all()` до `update`, затем `assertDatabaseMissing(['id'=>$originalId])` по каждому исходному id + `assertDatabaseHas(Salt/Sugar)` по имени. Мутационная проверка: подмена стратегии sync на append (без `delete()`) оставит исходные id → тест упадёт (`assertDatabaseMissing` по id). Раньше эту мутацию тест не ловил. Ловит.
- Гейты (worktree Sail, .env.testing/RefreshDatabase): PHPStan **L10 — No errors** (0 подавлений — `RecipeData::from` коерсит Carbon модели в `CarbonImmutable`-свойство без ошибки, как в `UserData`); Pint `--test` — **passed**; Pest `--filter=Recipe` — **8 passed (42 assertions)** (было 39 → +3: цикл по исходным id + `assertDatabaseHas Salt`, минус мёртвая строка).
- Регрессий нет: тесты `builds from a recipe`/`never leaks owner id` зелёные — DTO по-прежнему собирается, `toArray()` содержит `created_at`/`updated_at` (Spatie сериализует CarbonImmutable в строку), `user_id` не утекает. Потребителей PHP-DTO у полей дат пока нет (011 не построен) — тихая регрессия исключена.
- §8-гигиена: код/сообщение человеческого стиля, без следов системы/FEAT/AI.

**Suggested next:** none

## Рубрика (короткий цикл §6 + §3 для нетривиального кода фикса)

☑ Атомарность — один связный смысл (две advisory-чистки одного ревью; сообщение покрывает обе); компилируется, тесты зелёные.
☑ Логика vs интент — обе ноты закрыты ровно как задумано; поведение наружу (TS/JSON) не изменено.
☑ Тихие регрессии/parity — TS-diff пуст; baseline-тесты фичи зелёные.
☑ Тесты (мутационно) — новая ассерция ловит append-мутацию стратегии sync (раньше — нет).
☑ Business-security / N+1 / over-engineering — не затронуты (тип даты + тест-ассерция).

## Журнал закрытия находок

- Обе advisory-ноты исходного ревью `c48543f-review.md` (nit «вакуумная ассерция» + разнобой типов дат) закрыты этим фиксом. Отметка о закрытии — в `c48543f-review.md`.

## Связи

- Разбор «почему» (автор, ADR-009): `73050e3-recipe-data-timestamps-sync-test.md` (рядом).
- Источник advisory: `c48543f-review.md` · базовый разбор `c48543f-recipe-data-layer.md`.
- Фича: `../../features/FEAT-009-recipe-data-layer/impl.md` · `spec.md`; гайд: `../../guides/commit-review.md`.
