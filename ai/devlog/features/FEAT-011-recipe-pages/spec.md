# FEAT-011: Страницы рецептов — Page Resolvers, Inertia Vue-страницы, пагинация

## Статус: SPEC

## Затрагиваемые репозитории
cbook (frontend + backend) — один репозиторий. Мультирепный рецепт §3.5 не применяется.

## Цель
Дать пользовательский интерфейс домена: GET-страницы `index` (список с пагинацией), `show` (детали рецепта), `create`/`edit` (формы) на Inertia + Vue 3 (`<script setup>`, TS strict, Tailwind), собираемые через **Page Resolvers** из DTO. Замкнуть поток `Request → Controller → (Task/Repository) → DTO → Resolver → Inertia Vue Page`. Формы `create`/`edit` шлют мутации на маршруты FEAT-010.

## Контекст
База — `origin/develop` поверх **FEAT-009** (данные/DTO/`RecipeRepository`) и **FEAT-010** (Tasks, `RecipePolicy`, мутационные маршруты). FEAT-011 добавляет **чтение** (GET-маршруты, резолверы, страницы) и «дозапись» — перенаправляет redirect-таргеты мутационных контроллеров 010 с временного `dashboard` на `recipes.show`/`recipes.index`.

**Зачем Page Resolver (педагогика).** `app/Resolvers/Page/` пока пуст — эта фича **вводит паттерн Page Resolver** в проекте. Резолвер — единственное место сборки пропсов Inertia-страницы: он получает DTO из репозитория и формирует ровно ту форму данных, что нужна странице (список + метаданные пагинации, деталь рецепта и т.п.). Это выносит «подготовку вью-модели» из тонкого контроллера, делает пропсы типизированными (через DTO/автоген TS) и тестируемыми. В props Inertia уходят **только DTO** (STRICT RULE 4) — Vue-страницы никогда не видят Eloquent.

Инварианты: `ai/memory.md` §North Star, `stack-specifics.md` §Frontend (types-first, 0 `any`/`as`, только DTO-пропсы, Tailwind), `architecture.md` §4/§6/§8.

## Принятые решения на развилках (зафиксировано)

### Модель просмотра — приватная книга (допущение из FEAT-010, требует подтверждения владельца)
- `index` — **только рецепты текущего пользователя** (`RecipeRepository::paginateForUser($userId)`); `show`/`edit` — `authorize('view'/'update', $recipe)` (чужой → 403). Обоснование и открытый вопрос (конфликт с рекомендацией «общий каталог») — см. FEAT-010 §Принятые решения п.2. Переключение на общий каталог: `view`/`viewAny` Policy → `true` + `paginate()` в index-резолвере (обратимо дёшево).
> ⚠️ Тот же **открытый вопрос владельцу** повторяется здесь: подтвердить «приватная книга» vs «общий каталог» ДО реализации 011 (влияет на index-резолвер, `show`-authz и тесты).

### Граница с FEAT-010
- GET-маршруты (`index/show/create/edit`) и резолверы/страницы — **целиком в 011**. Мутационные маршруты/контроллеры — из 010; 011 лишь **перенаправляет их redirect** на `recipes.show`/`recipes.index` (правка `RecipeController` из 010) и обновляет соответствующие ассерты тестов 010.

## Acceptance Criteria
- [ ] GET-маршруты (в группе `Route::middleware(['auth','verified'])->group(...)`, dot-имена):
  - [ ] `GET /recipes` → `recipes.index`
  - [ ] `GET /recipes/create` → `recipes.create`
  - [ ] `GET /recipes/{recipe}` → `recipes.show`
  - [ ] `GET /recipes/{recipe}/edit` → `recipes.edit`
  - `{recipe}` — id (int), без implicit binding (арх-барьер, как в 010).
- [ ] Page Resolvers в `app/Resolvers/Page/` собирают пропсы **только из DTO** (никаких моделей): `RecipeIndexResolver`, `RecipeShowResolver`, `RecipeEditResolver` (create — пустая форма, резолвер опционален).
- [ ] `GET /recipes` под аутентифицированным+verified → Inertia-страница `Recipe/Index` с **пагинированным** списком рецептов владельца; данные — `App.Data.RecipeData[]` + метаданные пагинации; **N+1 отсутствует** (ингредиенты eager-load в `paginateForUser`).
- [ ] `GET /recipes/{id}` владельцем → страница `Recipe/Show` с полным `RecipeData` (шаги, ингредиенты); чужой → **403**; несуществующий → 404.
- [ ] `GET /recipes/create` → страница `Recipe/Create` с пустой формой; `GET /recipes/{id}/edit` владельцем → `Recipe/Edit` с предзаполненным `RecipeData`; чужой → 403.
- [ ] Формы `Create`/`Edit` (Vue, `useForm`) отправляют `POST recipes.store` / `PUT recipes.update`; при успехе — redirect на `recipes.show` (созданный/изменённый); при ошибках — inline-ошибки валидации (`form.errors.*`).
- [ ] Мутационные контроллеры 010: `store`/`update` → redirect `recipes.show`, `destroy` → redirect `recipes.index` (замена временного `dashboard`); тесты 010 обновлены под новые таргеты.
- [ ] Vue-страницы: `<script setup lang="ts">`, `defineProps<{...}>()` строго по `App.Data.RecipeData`, 0 `any`/`as`, стили Tailwind, `AuthenticatedLayout`.
- [ ] Гейты: PHPStan L10, Pint, Pest 0 fail (backend), `pnpm build` (вкл. `vue-tsc --noEmit`) зелёный, `pnpm lint` зелёный.

## Технический дизайн

### Маршруты (`routes/web.php`)
Добавить в существующую (или новую) группу `['auth','verified']`:
```
Route::get('/recipes',              [RecipeController::class, 'index'])->name('recipes.index');
Route::get('/recipes/create',       [RecipeController::class, 'create'])->name('recipes.create');
Route::get('/recipes/{recipe}',     [RecipeController::class, 'show'])->name('recipes.show');
Route::get('/recipes/{recipe}/edit',[RecipeController::class, 'edit'])->name('recipes.edit');
```
> `create` объявить **до** `{recipe}`, иначе `/recipes/create` матчнется как show с id=`create`. Зафиксировать порядок.

### Page Resolvers (`app/Resolvers/Page/` — вводимый паттерн)
`final`, `private readonly RecipeRepository` (DI), метод-сборщик пропсов, только DTO наружу:
- `RecipeIndexResolver::run(int $userId, int $perPage = 12): array` → `['recipes' => $this->recipes->paginateForUser($userId, $perPage)]` (`PaginatedDataCollection` RecipeData — Inertia сериализует c метаданными пагинации).
- `RecipeShowResolver::run(RecipeData $recipe): array` → `['recipe' => $recipe]`. DTO приходит из контроллера, который **уже** авторизовал по модели (`findModel`+`authorize('view')`) и построил DTO (`RecipeData::from($recipe)` — без явной ссылки на класс `Recipe`). Так show — **один** запрос (authz-модель = источник DTO), резолвер модель-free.
  > Если предпочесть строгую сборку резолвером: `RecipeShowResolver::run(int $id)` + `RecipeRepository::findData($id)` — но тогда авторизация (findModel) даёт второй запрос. Дефолт — вариант с одним запросом (контроллер строит DTO из authz-модели, резолвер оборачивает). Зафиксировать выбор при импле.
- `RecipeEditResolver` — аналогично show (тот же DTO, страница-форма).
- Резолверы **не** ссылаются на `App\Models\*` (арх-барьер) — работают только с DTO из репозитория.

### Контроллер (расширение `RecipeController` из 010 — read-методы)
- `index(Request $request): Response` → `Inertia::render('Recipe/Index', $this->recipeIndexResolver->run($request->user()->getAuthIdentifier()))`. `viewAny` — маршрутная мидлвара `auth`+`verified` (+ Policy `viewAny` при желании); список сам скоупится по владельцу.
- `show(Request $request, int $recipe): Response` → `$model = $this->recipes->findModel($recipe); abort_if($model===null,404); $this->authorize('view',$model); return Inertia::render('Recipe/Show', $this->recipeShowResolver->run(RecipeData::from($model)));`.
- `edit(Request $request, int $recipe): Response` → как show (`authorize('view')` или `update`) → `Recipe/Edit`.
- `create(): Response` → `Inertia::render('Recipe/Create')` (пустая форма; `create`-гейт = мидлвара).
- Redirect-правка мутаций (из 010): `store`/`update` → `redirect()->route('recipes.show', $id)`; `destroy` → `redirect()->route('recipes.index')`.
- Контроллер тонкий, без Eloquent/`DB`/бизнес-логики; `RecipeData::from($model)` — маппинг значения в DTO (без явной ссылки на `Recipe`).

### Inertia Vue-страницы (`resources/js/Pages/Recipe/`, types-first)
- `Index.vue` — `defineProps<{ recipes: PaginatedData }>()` (тип пагинации: обёртка над `App.Data.RecipeData[]` + `links`/`meta`; тип пагинации согласовать — Spatie `PaginatedDataCollection` сериализуется в `{ data, meta, links }`). Список карточек рецептов (title, difficulty, cooking_time, servings), Tailwind; ссылки на `recipes.show`; кнопка «создать» → `recipes.create`; управление пагинацией (`meta.links`).
- `Show.vue` — `defineProps<{ recipe: App.Data.RecipeData }>()`. Рендер title/description/шагов (`recipe.steps`, `v-for`), ингредиентов (`recipe.ingredients`, `v-for`), difficulty (enum → человекочитаемо). Для владельца — кнопки edit/delete (delete — `useForm().delete(route('recipes.destroy', recipe.id))`).
- `Create.vue` / `Edit.vue` — `useForm({...})` (поля title/description/cooking_time/servings/difficulty/steps[]/ingredients[]); динамическое добавление/удаление шагов и ингредиентов; submit `form.post(route('recipes.store'))` / `form.put(route('recipes.update', recipe.id))`; ошибки `form.errors.*` (вкл. вложенные `ingredients.0.name`). Edit предзаполнен из пропа `recipe`.
- Все страницы: `<script setup lang="ts">`, `AuthenticatedLayout`, Tailwind-утилиты, `@/`-алиас, 0 `any`/`as`. Компоненты форм — переиспользовать `Components/{InputLabel,TextInput,InputError,PrimaryButton,DangerButton}.vue`.
- TS-типы — из `resources/js/types/generated.d.ts` (`App.Data.RecipeData`, `App.Data.IngredientData`, `App.Enums.Difficulty`), сгенерированных в FEAT-009. Руками не дублировать.

## Тесты
**Добавить:** `tests/Feature/Recipe/RecipePagesTest.php` (RefreshDatabase авто; Inertia-ассерты через `Inertia\Testing\AssertableInertia`) —
- `index`: `actingAs($owner)->get('/recipes')` → 200, компонент `Recipe/Index`, проп `recipes` содержит только рецепты владельца (не чужие); пагинация присутствует.
- **N+1:** `Model::preventLazyLoading()` в тесте index/show — отсутствие ленивой загрузки ингредиентов (eager `with`).
- `show`: владелец → 200 `Recipe/Show` с `recipe.id`, шагами, ингредиентами; **чужой → 403**; несуществующий → 404.
- `create`: → 200 `Recipe/Create`. `edit`: владелец → 200 `Recipe/Edit` с предзаполнением; **чужой → 403**.
- **Негатив auth:** гость → login; неверифицированный → `verification.notice` (на всех GET).
- Полный цикл (интеграция с 010): `create`-форма → `store` → redirect `recipes.show`; `edit` → `update` → redirect `recipes.show`; `destroy` → redirect `recipes.index`.
**Обновить:** `tests/Feature/Recipe/RecipeCrudTest.php` (из 010) — redirect-ассерты `dashboard` → `recipes.show`/`recipes.index`.
**Удалить:** нет.

> Просмотр чужого рецепта (`show`/`edit`) → **403** — обязательный негативный тест (IDOR на чтение при приватной модели); при подтверждении «общий каталог» — заменить на 200 и оставить негатив только для мутаций (решение владельца).

## Типизация/качество
- Backend-гейты: PHPStan L10 (0 подавлений — резолверы/контроллер модель-free; `RecipeData::from($model)` не создаёт ссылки на класс), Pint, Pest.
- Frontend-гейты: `pnpm build` (`vue-tsc --noEmit`, TS strict) зелёный; `pnpm lint` (ESLint flat-config из FEAT-008) зелёный; 0 `any`/`as`.
- Типы пропсов — **только** из автоген `generated.d.ts` для DTO. Обёртку пагинации (`interface Paginated<T> { data: T[]; meta: {...}; links: {...} }`) допустимо описать **вручную** в `resources/js/types/` — это структурный контейнер Inertia/Laravel, а не дублирование DTO (сам `RecipeData` не переписывается). 0 `any`/`as`.
- DTO не меняются (из 009) — `typescript:transform` повторно не требуется.

## Безопасность
- **Доступы:** все GET-маршруты — под `auth`+`verified`. `show`/`edit` — `authorize('view'/'update')` (Policy, владелец) до рендера. `index` — скоуп по владельцу (не отдаёт чужие рецепты).
- **IDOR (чтение):** прямой `GET /recipes/{чужой}` / `/edit` → 403 (приватная модель). Обязательный негативный тест. (При «общем каталоге» — решение владельца снимает 403 на просмотр, мутации остаются владельцу.)
- **Данные наружу — только DTO:** в Inertia уходит `RecipeData` (без `user_id` — не экспонируется, FEAT-009); сырые модели/массивы Eloquent во Vue не попадают (STRICT RULE 4).
- **Валидация:** формы create/edit шлют на мутационные маршруты 010 → серверная валидация во `StoreRecipeRequest`/`UpdateRecipeRequest` (клиентская валидация — UX, не замена серверной).
- **N+1/производительность:** eager-load ингредиентов в `paginateForUser`/`findData` (FEAT-009); тест `preventLazyLoading` фиксирует отсутствие N+1.
- **Гигиена §8:** резолверы/контроллер/Vue/тесты — человеческий стиль, без следов системы; комментарии — по стилю файла.

## Пользовательская документация (user-visible)
Появляется **новый user-visible раздел** «Рецепты» (список/деталь/создание/редактирование). По правилу публичной доки: проверить клиентские `CLAUDE.md`/README, при необходимости добавить упоминание раздела/навигации; в `impl.md` зафиксировать `updated …` или `needs product-owner review` (навигация/меню — согласовать с владельцем). Пункт меню «Рецепты» в `AuthenticatedLayout` — добавить (ссылка `recipes.index`).

## Зависимые файлы для изменения
| Файл | Тип изменения |
|---|---|
| `routes/web.php` | +GET-маршруты `recipes.index/create/show/edit` |
| `app/Resolvers/Page/RecipeIndexResolver.php` | новый резолвер (вводит паттерн) |
| `app/Resolvers/Page/RecipeShowResolver.php` | новый резолвер |
| `app/Resolvers/Page/RecipeEditResolver.php` | новый резолвер |
| `app/Http/Controllers/RecipeController.php` | +read-методы index/show/create/edit; правка redirect-таргетов мутаций (010 → recipes.*) |
| `resources/js/Pages/Recipe/Index.vue` | новая страница (список + пагинация) |
| `resources/js/Pages/Recipe/Show.vue` | новая страница (деталь) |
| `resources/js/Pages/Recipe/Create.vue` | новая страница (форма создания) |
| `resources/js/Pages/Recipe/Edit.vue` | новая страница (форма редактирования) |
| `resources/js/Layouts/AuthenticatedLayout.vue` | +пункт навигации «Рецепты» (`recipes.index`) |
| `tests/Feature/Recipe/RecipePagesTest.php` | новые тесты (Inertia-ассерты, 403/N+1) |
| `tests/Feature/Recipe/RecipeCrudTest.php` | обновление redirect-ассертов (dashboard → recipes.*) |

## Что НЕ входит в эту фичу
- Слой данных (миграции/модели/repository/DTO/фабрики) — FEAT-009.
- Мутационные маршруты/Tasks/FormRequest/`RecipePolicy` — FEAT-010 (011 их **потребляет** и меняет только redirect-таргеты + добавляет `view`/`viewAny`-использование).
- Filament 5 Resource (админка), изображения рецептов (`whyme-agency/laravel-media`), BVI-панель, публичный поиск/каталог/фильтры — вне пакета.
- Расширенный UX (drag-drop шагов, автосохранение, оптимистичные обновления) — вне скоупа (базовые формы).

## Оценка сложности
Высокая. Риски: (1) первый Page Resolver в проекте — зафиксировать паттерн чисто (модель-free, только DTO); (2) типизация пагинации Spatie (`PaginatedDataCollection` → `{data,meta,links}`) в TS strict без `any`; (3) формы с динамическими массивами (steps/ingredients) и вложенные ошибки валидации (`ingredients.0.name`) в `useForm`; (4) единый порядок маршрутов (`create` до `{recipe}`); (5) правка redirect-таргетов 010 без слома его тестов; (6) открытый вопрос модели просмотра (приватная vs каталог) влияет на index/show-authz и набор 403-тестов.
