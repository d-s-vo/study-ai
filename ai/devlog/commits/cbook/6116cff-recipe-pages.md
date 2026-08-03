---
repo: cbook
authored_hash: 6116cffbc203a0ffadb3685924e121cf1ac11301
patch_id: 98fda3cd0cb88c295a252e16e19323db72698274
branch: feat/recipe-pages
feat: FEAT-011
date: 2026-08-03
final_hash:                   # best-effort, заполнить при обнаружении после merge MR
---

# cbook@6116cff — страницы рецептов с общим каталогом и пагинацией

> Коммит-сообщение (как в клиентском репо): `feat: страницы рецептов с общим каталогом и пагинацией`

## Кратко (для инженера)

- `app/Resolvers/Page/RecipeIndexResolver.php` — новый: DI `RecipeRepository`, `run(int $perPage = 12)` → `['recipes' => $this->recipes->paginate($perPage)]` (весь каталог, без owner-скоупа). Первый Page Resolver в проекте.
- `app/Resolvers/Page/RecipeShowResolver.php` — новый: `run(RecipeData $recipe, bool $canUpdate)` → пропсы `recipe`+`canUpdate`; конструктора нет — резолвер не обращается к репозиторию, только оборачивает уже готовые значения.
- `app/Resolvers/Page/RecipeEditResolver.php` — новый: `run(RecipeData $recipe)` → `['recipe' => $recipe]`; тоже без DI репозитория.
- `app/Http/Controllers/RecipeController.php` — +`index`/`create`/`show`/`edit` (read); `show` берёт модель через `findModel`, `abort_if(...,404)`, вычисляет `Gate::allows('update', $found)` и передаёт вместе с DTO в резолвер; `edit` — `Gate::authorize('update', $found)` (403 чужому) перед сборкой пропсов; redirect-таргеты `store`/`update` → `recipes.show`, `destroy` → `recipes.index` (был временный `dashboard` из FEAT-010).
- `routes/web.php` — 4 GET-маршрута (`recipes.index/create/show/edit`), `create` объявлен до `{recipe}` (иначе `/recipes/create` матчится как show с id=`create`); `show`/`edit` — `whereNumber('recipe')`.
- `resources/js/types/pagination.ts` — новый `Paginated<TData>` (data/links/meta) — ручной структурный тип обёртки, DTO внутри не дублируется.
- `resources/js/Pages/Recipe/{Index,Show,Create,Edit}.vue` — новые Inertia-страницы, `<script setup lang="ts">`, типы из `generated.d.ts`, 0 `any`/`as`, Tailwind, `AuthenticatedLayout`.
- `resources/js/Layouts/AuthenticatedLayout.vue` — +пункт меню «Рецепты» (desktop `NavLink` + responsive `ResponsiveNavLink`), активен на `recipes.*`.
- `eslint.config.js` — `no-undef: off` для `**/*.ts|tsx|vue` — резолюция идентификаторов (в т.ч. ambient `App.*`) отдана TS/vue-tsc, правило давало ложные срабатывания на первых файлах с `App.Data.*`/`App.Enums.*` в `.vue`.
- `tests/Feature/Recipe/RecipeCrudTest.php` — ассерты redirect обновлены под новые таргеты (FEAT-010 долг); IDOR-негатив update теперь проверяет неизменность ингредиентов; добавлен 404-тест для `destroy`; тест спуфа владельца расширен явными ассертами обоих слоёв защиты (`validated()` без `user_id`, `$fillable` без `user_id`).
- `tests/Feature/Recipe/RecipePagesTest.php` — новый: 16 тестов на index/show/create/edit (каталог, пагинация, N+1 через `preventLazyLoading`, canUpdate true/false, 403/404, guest/unverified, полные циклы create→show/edit→show/destroy→index).

## Детально (для новичка)

### Зачем это всё: первый Page Resolver и завершение потока Request→Vue

До этого коммита в проекте были только данные (FEAT-009: модели/DTO/репозиторий) и мутации (FEAT-010: Tasks/Policy/FormRequest), но не было ни одной страницы — все мутации редиректили на `dashboard` как временную заглушку. Этот коммит замыкает поток: `Request → Controller → Resolver → DTO-пропсы → Inertia Vue Page`. Ключевой архитектурный ход — **Page Resolver**: класс, чья единственная работа — собрать пропсы конкретной Inertia-страницы из уже готовых DTO. Контроллер не решает, что именно нужно вью — он лишь достаёт данные и отдаёт их резолверу.

### `app/Resolvers/Page/*.php`

Три файла — три страницы. Резолвер — обычный класс без наследования от чего-либо специфичного Inertia; это просто соглашение о месте и форме. `RecipeIndexResolver` внедряет `RecipeRepository` через конструктор (`private readonly`) — ему нужно самому запросить весь список с пагинацией. `RecipeShowResolver` и `RecipeEditResolver` репозиторий **не внедряют** — они получают уже готовый `RecipeData` от контроллера параметром метода `run()`. Разница объясняется тем, кто уже сделал запрос к БД: для show/edit контроллеру всё равно нужна модель до резолвера (для `findModel`+`abort_if(404)` и для авторизации через Gate), поэтому повторный поход в репозиторий изнутри резолвера был бы лишним запросом и мёртвой зависимостью. Резолверы не ссылаются на `App\Models\*` — работают только с DTO, это соответствует арх-барьеру (`ArchitectureTest`) и STRICT RULE 4 (в Inertia уходят только DTO).

### `app/Http/Controllers/RecipeController.php`

`index()` — просто `Inertia::render('Recipe/Index', $this->recipeIndex->run())`; гейт — маршрутная мидлвара `auth`+`verified`, каталог общий для всех (решение владельца из спеки FEAT-011). `show()` — интереснее: рецепт открыт для просмотра любому, но кнопки редактирования/удаления должны быть видны только владельцу. DTO (`RecipeData`) намеренно не содержит `user_id` (решение FEAT-009, чтобы не палить владельца на фронте), поэтому владение вычисляется на сервере: `Gate::allows('update', $found)` даёт `bool`, который кладётся в пропс `canUpdate` рядом с самим DTO. `edit()` — наоборот, `Gate::authorize('update', $found)` (не `allows`) — бросает 403 сразу, потому что страница редактирования по решению спеки доступна только владельцу без исключений.

Изменение в `store`/`update`/`destroy` — только строка редиректа: `dashboard` → `recipes.show($id)` / `recipes.index()`. Это был явно обозначенный техдолг FEAT-010 («страниц пока нет»), и теперь он закрыт.

### `routes/web.php`

Порядок регистрации маршрутов в Laravel имеет значение: роутер матчит первый подходящий шаблон. `/recipes/create` и `/recipes/{recipe}` оба технически совпадают с `GET /recipes/create`, поэтому `create` должен быть объявлен раньше — иначе Laravel примет строку `"create"` за числовой `{recipe}` (а `whereNumber` на `show` его бы просто отбросил в 404, ломая маршрут создания). Комментарий в коде фиксирует это явно, чтобы будущая правка маршрутов не сломала порядок случайно.

### `resources/js/types/pagination.ts`

Spatie Laravel Data сериализует пагинированную коллекцию в объект `{ data, links, meta }` — стандартная форма пагинатора Laravel. Это не DTO домена (не описывает рецепт), а универсальный «конверт» для любой пагинированной коллекции, поэтому его можно типизировать вручную как generic `Paginated<TData>`, не нарушая правило «типы DTO только из автогенерации» — `TData` в конкретном использовании (`Paginated<App.Data.RecipeData>`) всё равно приходит из `generated.d.ts`.

### `resources/js/Pages/Recipe/*.vue`

Четыре страницы, все — `<script setup lang="ts">`. `Index.vue` рендерит сетку карточек, использует `recipes.meta.prev_page_url`/`next_page_url` для навигации между страницами (просто ссылки, не кастомный компонент пагинации — минимально достаточно для 12/стр). `Show.vue` показывает рецепт целиком; кнопки редактирования/удаления — под `v-if="canUpdate"`, удаление — через `useForm({}).delete(...)` с `window.confirm` перед отправкой. `Create.vue`/`Edit.vue` — идентичные по структуре формы с динамическими массивами шагов и ингредиентов (`form.steps.push/splice`, аналогично для ingredients); `Edit.vue` копирует значения из пропа `recipe` в локальный `useForm`, не мутируя проп напрямую.

### `resources/js/Layouts/AuthenticatedLayout.vue`

Добавлен пункт «Рецепты» в двух местах шаблона — desktop-навигация (`NavLink`) и мобильное выпадающее меню (`ResponsiveNavLink`), оба с `:active="route().current('recipes.*')"` — подсветка активного раздела работает для любой из четырёх recipes-страниц через wildcard, не перечисляя каждый route по имени.

### `eslint.config.js`

`App.Data.RecipeData`, `App.Enums.Difficulty` — это ambient-типы (глобальный TS-namespace, сгенерированный в FEAT-009), они не импортируются явно. Базовое правило ESLint `no-undef` не умеет резолвить такие глобальные объявления типов и подсвечивало их как «неопределённые» ложноположительно — хотя `vue-tsc --noEmit` (реальный тайпчекер) их прекрасно видит и был бы единственным источником правды для резолюции идентификаторов TS. Отключение точечное — только для `.ts/.tsx/.vue`, не глобально по проекту.

### Тесты

`RecipeCrudTest.php` — правки под новые redirect-таргеты плюс закрытие трёх advisory-нитов из ревью FEAT-010: IDOR-негатив update теперь явно проверяет, что ингредиенты тоже не изменились (не только сам рецепт); добавлен 404-тест на `destroy` несуществующего id (раньше был только на `update`); тест спуфа владельца получил явные ассерты обоих слоёв защиты вместо неявного вывода из поведения. `RecipePagesTest.php` — новый файл, 16 тестов покрывают все четыре read-маршрута: общий каталог (рецепты разных пользователей видны всем), пагинация (15 рецептов → 12 на первой странице, `last_page=2`), отсутствие N+1 через `Model::preventLazyLoading()`, `canUpdate` true/false в зависимости от владельца, 403 на чужой edit, 404 на несуществующий id, guest/unverified редиректы на все четыре маршрута, и три «полных цикла» (create→store→show, edit→update→show, destroy→index) как интеграционная проверка склейки с FEAT-010.

## Почему так, а не иначе

- **DI `RecipeRepository` в резолверах show/edit** — отклонено. Спека такую возможность не запрещала, но раз контроллер уже обязан получить модель сам (для `findModel`+`abort_if(404)`+авторизации до вызова резолвера), повторный запрос внутри резолвера был бы дублирующим запросом к БД и неиспользуемой зависимостью. Показатель: `RecipeShowResolver`/`RecipeEditResolver` — чистые трансформеры DTO→пропсы, без конструктора.
- **`Gate::allows`/`Gate::authorize` вместо `$user->can()`** — отклонена фасадная альтернатива через модель пользователя: `Gate::` не требует null-проверки `$request->user()` перед вызовом и уже используется в контроллере FEAT-010 (`Gate::authorize` в `update`) — выбор ради консистентности стиля внутри одного класса.
- **Пагинация через `meta.prev/next_page_url` вместо рендера `links[]` в шаблоне** — отклонена вёрстка по `links` (массив с числовыми страницами и HTML-сущностями `&laquo;`/`&raquo;` в `label`), потому что потребовала бы `v-html` (небезопасно/не в духе Tailwind-вёрстки проекта) или парсинга сущностей на клиенте; `meta.*_page_url` даёт готовые URL без интерполяции разметки.
- **`Paginated<T>` как обычный экспортируемый TS-модуль, а не ambient-namespace** — отклонено расширение `generated.d.ts`-подобного глобального `App.*`: правило `no-namespace` из `typescript-eslint` (уже включённое в проекте) блокирует ambient-namespace вне автогенерации; обычный `interface`+экспорт проще и не требует правок конфигурации сверх точечного `no-undef: off`.

## Связи

- Спека: `../../features/FEAT-011-recipe-pages/spec.md` (модель просмотра «общий каталог», граница с FEAT-010, дизайн резолверов/маршрутов/страниц).
- Журнал реализации: `../../features/FEAT-011-recipe-pages/impl.md` (отклонения, гейты, живая приёмка).
- Фундамент: `cbook/c48543f-recipe-data-layer.md` (модели/DTO/репозиторий, FEAT-009), `cbook/632c4aa-recipe-crud.md` (Tasks/Policy/мутационные маршруты, FEAT-010 — этот коммит перенаправляет их redirect-таргеты и закрывает 3 advisory-нита её ревью).
