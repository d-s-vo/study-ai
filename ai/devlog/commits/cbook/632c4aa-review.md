---
repo: cbook
authored_hash: 632c4aa28b6187bb6d2dcc6f1a8166478fd7d0ea
patch_id: 5bf0c20fd240339fb177d339cb41a4493f9be0df
feat: FEAT-010
branch: feat/recipe-crud
reviewer_model: Opus 4.8
review_date: 2026-07-31
verdict: PASS
blockers_total: 0
blockers_open: 0
resolved_by: []
---

# cbook@632c4aa — REVIEW — feat: мутации рецептов с проверкой владельца

**Verdict:** PASS
**Blocking findings:**
- (нет)
**Non-blocking notes:**
- `tests/Feature/Recipe/RecipeCrudTest.php:88` («cannot update … do not own») — негатив прав проверяет только неизменность `title`, но не проверяет, что ингредиенты чужого рецепта уцелели. IDOR отсекается `Gate::authorize` **до** Task, поэтому по коду данные не могут быть тронуты — но ассерт на неизменность ингредиентов сделал бы тест устойчивее к будущей регрессии «authorize после мутации». (severity: nit)
- `RecipeController.php:47` (`destroy`) — путь `findModel(null)→404` покрыт тестом только для `update` (`updating a missing recipe returns 404`), для `destroy` теста 404 нет. Код-путь идентичен (`abort_if($found===null,404)`), риск низкий. (severity: nit)
- `tests/Feature/Recipe/RecipeCrudTest.php:120` («owner cannot be spoofed») — защита двухслойная (`validated()` вырезает `user_id`, `createForUser` ставит владельца через связь `user->recipes()`), поэтому даже подмена `->validated()`→`->all()` в одиночку тест бы не завалила (Eloquent молча отбросил бы нефиллабельный `user_id`). Тест валиден как end-to-end гарантия «спуф → владелец = auth-пользователь», но не изолирует один слой защиты. Реальная защита корректна. (severity: nit)

**Evidence:**
- Контекст прочитан ПЕРЕД diff: `spec.md`/AC (13 AC), `impl.md` (3 отклонения), stack-specifics §Backend (5 STRICT RULES), memory §North Star, architecture §8 (изоляция по владельцу + обязательные негативные тесты), смежный `c48543f-review.md` (FEAT-009, контракт репозитория). `git show 632c4aa` — весь diff (11 файлов, +~440).
- Гейты в worktree (Sail, порты брони, .env.testing/RefreshDatabase): PHPStan **L10 — No errors** (40 файлов); `grep` подавлений (`@phpstan-ignore*`/`ignoreErrors`/baseline) в новом коде — **0**; Pint `--test` — **passed**; таргетный прогон `RecipeCrudTest`+`ProfileTest`+`ArchitectureTest` — **21 passed (76 assertions)** (полный сьют — 65 passed, прогнан автором).
- **IDOR (ядро фичи) — реально закрыт.** `update`/`destroy`: `findModel($id)` → `abort_if(null,404)` → `Gate::authorize('update'|'delete',$found)` **до** Task. `RecipePolicy::update/delete` = `$user->id === $recipe->user_id`. Negative-тесты «stranger PUT/DELETE чужого → 403» **ловят мутацию**: удаление `Gate::authorize` из контроллера → stranger получил бы 302 вместо 403 → тесты красные (проверено логикой пути; authorize — единственный барьер).
- **Mass-assignment / подмена владельца:** `Store/UpdateRecipeRequest::rules()` без `user_id`/`recipe_id` → `->validated()` вырезает их; `createForUser` берёт владельца из `$user->id` (auth), ставит через связь. Recipe `$fillable` (FEAT-009) без `user_id`. Подмена заблокирована на двух уровнях (нота nit о слое покрытия).
- **Арх-барьер (5 STRICT RULES) не ослаблен.** Контроллер/Tasks ссылаются только на `App\Data\Repositories\RecipeRepository` и `App\Tasks\*` — **нет** `use App\Models\*`/тип-хинта `Recipe` (доступ по выведенному `?Recipe` из `findModel`). Единственное касание модели вне репозитория — `RecipePolicy` (`use App\Models\{User,Recipe}`), санкционировано расширением allow-list `+App\Policies` в `ArchitectureTest` (Policy читает атрибуты гидрированной модели, запросов не делает — комментарий человеческий, без следов системы). Барьер зелёный подтверждает: Controllers/Tasks вне allow-list, ссылка на модель из них падала бы.
- **Валидация:** датасет-негативы (пустой title / `difficulty='extreme'` вне enum / `steps` не массив / ингредиент без name) → 422-redirect + session errors + `Recipe::count()===0`. Ловят снятие правил. `Rule::enum(Difficulty::class)` ограничивает `low|medium|high`.
- **Синхронизация ингредиентов (update):** тест обновляет 2→1 ингредиент и ассертит `count()===1` — ловит мутацию «update не удаляет старые» (иначе было бы 3). Каскад delete подтверждён `assertDatabaseMissing('ingredients')`.
- **auth/verified:** гость `POST` → 302 `/login`; unverified → `verification.notice` (и для `/recipes`, и для `/profile` — перевод группы profile под `verified` покрыт новым profile-тестом). AC «попутный долг /profile» выполнен.
- **Тихие регрессии/parity:** правка `routes/web.php` (`auth`→`['auth','verified']` на profile-группе) — поведенческая, но покрыта тестом и была AC; существующие profile-тесты зелёные (фабрика по умолчанию verified). `ArchitectureTest` — аддитивное расширение allow-list, второе правило (фасад `DB`) не тронуто.
- **N+1/перф:** мутации не листят; `update` делает лишний `findModel` (eager `with('ingredients')`) для authz + повторный `findOrFail` в репозитории — 1 избыточный запрос на операцию записи, не N+1, не на горячем пути. Приемлемо.
- **Чужая среда:** CI-файлы/пайплайны не тронуты; dev-пакетов в прод-путь не добавлено; `assert($user!==null)` (nullsafe-нарратив под L10, паттерн `ProfileController`) в проде с `zend.assertions=-1` вырождается в no-op — безопасно, т.к. `auth`-middleware гарантирует не-null.
- §8-гигиена диффа: код/комментарии человеческого стиля (рус. комментарии про общий каталог и редирект на дашборд), без следов системы/FEAT/AI/номеров.

**Suggested next:** advisory

## Рубрика (бинарно, commit-review.md §3)

☑ Атомарность/целостность — один смысл (мутации домена Recipe: маршруты+контроллер+Tasks+FormRequests+Policy+тесты), компилируется, релевантные тесты зелёные.
☑ Логика vs спека/интент — все 13 AC покрыты; 3 отклонения impl.md (`$user->id` вместо каста, наследование UpdateRequest, отсутствие явного create-authorize) обоснованы и проверены независимо.
☑ Business-security (OWASP) — IDOR закрыт Policy+authorize до Task (негативы ловят мутацию); mass-assignment двухслойно; вся валидация во FormRequest до Task.
☑ Тихие регрессии/parity — перевод profile под `verified` покрыт тестом; расширение allow-list аддитивно, второе арх-правило не тронуто.
☑ Тесты (мутационно) — IDOR/sync/каскад/валидация/404/unverified ловят конкретные мутации; 3 nit-ноты по устойчивости, не вакуумность.
☑ N+1/перф — мутации не листят; лишний authz-запрос не критичен; пагинация — зона FEAT-011.
☑ Over-engineering — нет; Tasks тонкие, UpdateRequest наследованием без дублирования.

## Журнал закрытия находок

<!-- История статуса — записями, не правкой чужих строк. -->
- Блокеров нет. Три ноты (nit) — advisory: закрыть попутным фиксом в FEAT-011 (усилить негатив-ассерты) либо принять с записью оркестратором.

## Связи

- Разбор «почему» (автор, ADR-009): `632c4aa-recipe-crud.md` (файл-разбор рядом, если создан).
- Фича: `../../features/FEAT-010-recipe-crud/impl.md` · `spec.md`.
- Смежные: `../../features/FEAT-009-recipe-data-layer/` (контракт репозитория) · `../../features/FEAT-011-recipe-pages/spec.md` (redirect-таргеты, пагинация).
- Арх-инвариант: `../../adr/003-layered-architecture.md`; гайд ревью: `../../guides/commit-review.md`.
