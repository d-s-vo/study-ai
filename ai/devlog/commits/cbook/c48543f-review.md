---
repo: cbook
authored_hash: c48543f8f38d82e666c3daf1417b09f79e7dae42
patch_id: 634101e0ef36c6bcab02beb740bdb2a6730664e2
feat: FEAT-009
branch: feat/recipe-data-layer
reviewer_model: Opus 4.8
review_date: 2026-07-31
verdict: PASS
blockers_total: 0
blockers_open: 0
resolved_by: []
---

# cbook@c48543f — REVIEW — feat: слой данных рецептов и ингредиентов

**Verdict:** PASS
**Blocking findings:**
- (нет)
**Non-blocking notes:**
- `tests/Feature/Recipe/RecipeRepositoryTest.php:57` — вакуумная ассерция: `assertDatabaseMissing('ingredients', ['recipe_id'=>$recipe->id,'name'=>'Salt','quantity'=>999])`. Salt вставлен с `quantity=1.0`, поэтому строка `(Salt, 999)` отсутствует всегда, независимо от корректности кода — ассерция мёртвая. Ловящее мутацию покрытие синхронизации уже даёт `count()===2` + `assertDatabaseHas(Sugar)` строкой выше. Рекомендация: убрать или заменить на проверку, что старые ингредиенты (по имени из фабрики) удалены. (severity: nit)
- `database/migrations/2026_07_31_000002_*` / `..._000001_*` — `down()` (`dropIfExists`) не покрыт автоматическим тестом: `RefreshDatabase` прогоняет только `up()`. AC «migrate:rollback откатывает» подтверждён вручную (ниже, Evidence). Тривиальный `dropIfExists` — риск низкий. (severity: minor, advisory)
- `tests/Feature/ArchitectureTest.php` — характеризующий red→green кейс-нарушитель (утечка `Recipe` в Task) не добавлен; spec помечал его «опционально». Барьер эмпирически подтверждён (arch-тест зелёный, upper-слоёв в allow-list нет). (severity: nit)

**Evidence:**
- Контекст прочитан ПЕРЕД diff: spec.md/AC, impl.md (3 отклонения), разбор ADR-009 автора, stack-specifics (5 STRICT RULES), смежные spec FEAT-010/011. `git show c48543f` — весь diff (16 файлов, +573).
- Гейты (worktree Sail, .env.testing/RefreshDatabase): PHPStan **L10 — No errors**; `grep` подавлений (`@phpstan-ignore*`/`ignoreErrors`/baseline) — **0**; Pint `--test` — **passed**; Pest `--filter=Recipe` — **8 passed (39 assertions)**; ArchitectureTest — **2 passed**.
- TS-детерминизм: `artisan typescript:transform` → `git diff generated.d.ts` **пусто** (регенерация детерминирована; `Difficulty` как union `'low'|'medium'|'high'`).
- Миграции: `migrate:fresh` → `rollback --step=2` (порядок ingredients→recipes, FK-безопасно) → повторный `migrate` — все проходят на testing-БД.
- **Отклонение №1 (App\Models в allow-list) — обосновано и минимально.** Межмодельные связи (`Recipe↔User`, `Recipe↔Ingredient`) — использование `App\Models\*` внутри `App\Models\*`, что namespace-wide правило иначе валит (у `User`/`UserData` перекрёстных ссылок не было — spec это недооценил). Барьер НЕ ослаблен: allow-list остаётся из 4 namespace (`App\Models` + 3 слоя данных Laravel); Controllers/Tasks/Resolvers/Vue по-прежнему вне списка → ссылка на модель из них падает (arch-тест зелёный это подтверждает — правило активно). Аддитивно и не конфликтует с планируемым в FEAT-010 `+App\Policies`.
- **Отклонение №3 (создание через `User::recipes()->create()`)** — обосновано: обходит L10 `int<0,max>` на прямом присваивании FK, без каста/подавления; связь сама ставит `user_id`.
- **user_id-утечка:** `RecipeData` не содержит поля `user_id`; негативный тест `never leaks the owner id` ассертит точный набор ключей `toArray()` + `not->toHaveKey('user_id')` — ловит мутацию «добавили user_id в DTO».
- **Mass assignment:** `Recipe::$fillable` без `user_id`, `Ingredient::$fillable` без `recipe_id`; владелец ставится через связь, `recipe_id` — через `createMany` на связи; `update()` использует `fill()` (защищён fillable). Подмена владельца через payload заблокирована.
- **N+1:** `paginate`/`findModel` используют `with('ingredients')`; тест paginate ставит `Model::preventLazyLoading()` до выборки и обходит `ingredients` — ловит мутацию «убрали eager-load».
- **Каскады FK:** тесты «delete recipe → 0 ingredients» и «delete user → 0 recipes/ingredients» эмпирически подтверждают цепочку `users→recipes→ingredients` на уровне БД.
- **Контракт для 010/011:** сигнатуры `paginate():PaginatedDataCollection`, `findModel(int):?Recipe`, `createForUser/update/delete`, `RecipeData` без `user_id` — совпадают с ожиданиями обеих смежных spec; конфликтов нет.
- §8-гигиена диффа: код/комментарии человеческого стиля (рус. комментарий в arch-тесте про связи), без следов системы/FEAT/AI.

**Suggested next:** advisory

## Рубрика (бинарно, commit-review.md §3)

☑ Атомарность/целостность — один смысл (слой данных домена), компилируется, релевантные тесты зелёные.
☑ Логика vs спека/интент — AC покрыты; 3 отклонения задокументированы и обоснованы (проверены независимо).
☑ Business-security (OWASP) — mass-assignment/IDOR-фундамент (user_id вне fillable, не утекает в DTO); authz-мутаций — по плану в FEAT-010.
☑ Тихие регрессии/parity — правка `User.php` (+`recipes()`) и провайдера TS аддитивны; baseline-тесты не затронуты.
☑ Тесты (мутационно) — paginate/cascade/sync/DTO-leak ловят конкретные мутации; одна вакуумная ассерция (нота nit).
☑ N+1/перф — eager-load + preventLazyLoading-guard; пагинация есть.
☑ Over-engineering — нет; отдельный IngredientRepository обоснованно отклонён (композиция агрегата).

## Журнал закрытия находок

- Блокеров нет. Ноты (nit/minor) — advisory: закрыть попутным фиксом либо принять с записью оркестратором.
- Нота `RecipeRepositoryTest.php:57` (вакуумная ассерция) + разнобой типов дат (`?string` vs `?CarbonImmutable`) → закрыты фикс-коммитом `73050e3` (узкое ревью §6: обе ноты закрыты, регрессий нет — `73050e3-review.md` PASS). 2026-07-31.

## Связи

- Разбор «почему» (автор, ADR-009): `c48543f-recipe-data-layer.md` (рядом).
- Фича: `../../features/FEAT-009-recipe-data-layer/impl.md` · `spec.md`.
- Смежные: `../../features/FEAT-010-recipe-crud/spec.md` · `../../features/FEAT-011-recipe-pages/spec.md` (контракты сверены).
- Арх-инвариант: `../../adr/003-layered-architecture.md`; гайд ревью: `../../guides/commit-review.md`.
