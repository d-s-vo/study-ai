---
feat: FEAT-011
repos: [cbook]
tags: [frontend, backend, inertia, vue, pagination, authz]
class: 'страницы домена Recipe: Page Resolvers (первый паттерн в проекте), read-маршруты, 4 Inertia Vue-страницы, общий каталог с пагинацией, пункт меню'
prevention: 'обязательные тесты N+1 (preventLazyLoading), 403 на чужой edit, 200 на чужой show (общий каталог), 404 на несуществующий id'
---

# FEAT-011: Страницы рецептов — Implementation

## Статус: DONE
## Дата: 2026-08-03

## Что сделано

| Файл | Изменение |
|---|---|
| `app/Resolvers/Page/RecipeIndexResolver.php` | новый: DI `RecipeRepository`, `run(perPage=12)` → пагинированный список всех рецептов (общий каталог) |
| `app/Resolvers/Page/RecipeShowResolver.php` | новый: `run(RecipeData, canUpdate)` → пропсы деталей; без DI репозитория (чистый трансформер DTO) |
| `app/Resolvers/Page/RecipeEditResolver.php` | новый: `run(RecipeData)` → пропсы формы редактирования; без DI репозитория |
| `app/Http/Controllers/RecipeController.php` | +read-методы `index/create/show/edit`; `show` — `findModel`+`abort_if(404)`+`Gate::allows('update')` → `canUpdate`; `edit` — `Gate::authorize('update')` (403 чужому); redirect-таргеты `store/update` → `recipes.show`, `destroy` → `recipes.index` (был `dashboard`, долг FEAT-010) |
| `routes/web.php` | +4 GET-маршрута `recipes.index/create/show/edit`; `create` до `{recipe}`; `show`/`edit` — `whereNumber('recipe')` |
| `resources/js/types/pagination.ts` | новый `Paginated<TData>` (data/links/meta) — ручной структурный тип-обёртка, DTO не дублирует |
| `resources/js/Pages/Recipe/Index.vue` | новая страница: сетка карточек, пагинация через `meta.prev/next_page_url` |
| `resources/js/Pages/Recipe/Show.vue` | новая страница: детали рецепта, кнопки edit/delete под `v-if="canUpdate"` |
| `resources/js/Pages/Recipe/Create.vue` | новая страница: форма с динамическими шагами/ингредиентами, `useForm().post` |
| `resources/js/Pages/Recipe/Edit.vue` | новая страница: предзаполненная форма, `useForm().put` |
| `resources/js/Layouts/AuthenticatedLayout.vue` | +пункт меню «Рецепты» (desktop `NavLink` + responsive `ResponsiveNavLink`), активен на `recipes.*` |
| `eslint.config.js` | `no-undef: off` для `**/*.ts|tsx|vue` — резолюция identifiers (в т.ч. ambient `App.*`) отдана TS/vue-tsc |
| `tests/Feature/Recipe/RecipeCrudTest.php` | ассерты redirect обновлены под новые таргеты; IDOR-негатив update теперь проверяет неизменность ингредиентов; +404-тест для `destroy`; тест спуфа владельца — явные ассерты обоих слоёв защиты |
| `tests/Feature/Recipe/RecipePagesTest.php` | новый: 16 тестов (каталог/пагинация/N+1/canUpdate/403/404/guest/unverified/полные циклы create-edit-destroy) |

Коммит: `6116cff` `feat: страницы рецептов с общим каталогом и пагинацией` (ветка `feat/recipe-pages`).
Разбор «почему»: `../../commits/cbook/6116cff-recipe-pages.md`.

## Отклонения от spec

1. **`RecipeShowResolver`/`RecipeEditResolver` без DI `RecipeRepository`.** Спека не исключала DI явно, но контроллер и так обязан получить модель до вызова резолвера (`findModel`+`abort_if(404)`+авторизация), поэтому повторный запрос внутри резолвера был бы мёртвой зависимостью и лишним обращением к БД. Оба резолвера — чистые трансформеры готового `RecipeData` в пропсы.
2. **`canUpdate` на `show` вычислен через `Gate::allows($found)`, а не `$user->can()`.** Эквивалент по семантике; выбран ради консистентности с `Gate::authorize` в `edit`/мутациях FEAT-010 и null-safe (не требует явной проверки `$request->user()` перед вызовом).
3. **Пагинация во `Index.vue` рендерится через `meta.prev_page_url`/`next_page_url`, а не через `links[]`.** `links[]` из Spatie/Laravel-пагинатора несёт HTML-сущности (`&laquo;`/`&raquo;`) в `label`, что потребовало бы `v-html` — решено не вводить, готовые `meta.*_page_url` дают тот же результат без интерполяции разметки.
4. **`Paginated<T>` — обычный экспортируемый TS-модуль (`interface`), а не ambient-namespace.** Расширение глобального `App.*`-namespace упёрлось бы в правило `no-namespace` (typescript-eslint), уже включённое в проекте; отдельный модуль проще и не требует новых исключений в конфиге.
5. **В `eslint.config.js` отключён `no-undef` для `**/*.ts|tsx|vue`.** Первые файлы, использующие ambient `App.Data.*`/`App.Enums.*` внутри `.vue`, вскрыли ложные срабатывания правила (оно не резолвит ambient-объявления типов); `vue-tsc --noEmit` — единственный корректный источник истины для резолюции идентификаторов TS, что и есть рекомендация `typescript-eslint` для таких случаев.

## Ключевые решения по ходу реализации

- **Порядок маршрутов `create` до `{recipe}`** зафиксирован явным комментарием в `routes/web.php` — без него `/recipes/create` совпал бы с шаблоном `show` (id="create"), что для строкового `$recipe` без `whereNumber` дало бы ошибку типа, а с `whereNumber` — 404 вместо формы создания.
- **DTO без `user_id` (решение FEAT-009) держит владение сервер-сайд.** `RecipeShowResolver` получает `canUpdate` отдельным булевым параметром, а не читает владельца из DTO — фронт никогда не видит `user_id`, но видит достаточно, чтобы показать/скрыть кнопки.
- **Попутное закрытие техдолга FEAT-010:** redirect-таргеты `dashboard` заменены на `recipes.show`/`recipes.index` — ровно как было обозначено в итоговом разделе impl.md FEAT-010.
- **Попутное закрытие 3 advisory-нитов review FEAT-010** (`632c4aa-review.md`): IDOR-негатив update теперь ассертит неизменность ингредиентов; добавлен 404-тест для `destroy`; тест спуфа владельца получил явные ассерты обоих слоёв защиты (`validated()` без `user_id` + `$fillable` модели без `user_id`).

## Как тестировали

- Гейты (worktree-стенд Sail, порт брони 8130): Pint — **PASS**; PHPStan L10 — **PASS, 43 файла, 0 ошибок**; Pest — **82 passed / 369 assertions** (полный прогон под `gate.sh`); `pnpm build` (вкл. `vue-tsc --noEmit` strict) — **PASS**; `pnpm lint` — **PASS**.
- По ходу чинилось до зелёного: Pint-автоформат в `RecipeCrudTest.php`; TS6133 (неиспользуемая переменная цикла — `step` → `_step` в `v-for` на `Create.vue`/`Edit.vue`); стейл Vite-манифест (пересборка `pnpm build` после добавления новых `.vue`); `no-undef` ESLint на ambient `App.*` (см. «Отклонения от spec» п.5).
- **Живая приёмка** (HTTP-сценарий на порту 8130, реальный стенд, два пользователя, 18 рецептов): guest → 302 на login по всем 4 маршрутам; каталог — оба пользователя видят все 18 рецептов, пагинация подтверждена постранично (`page=1`/`page=2`, `meta.total=18`, `meta.per_page=12`, `meta.last_page=2`), сериализация Spatie `PaginatedDataCollection` подтверждена (`data`/`links`/`meta` присутствуют); чужой `show` → 200, `canUpdate=false`; свой `show` → 200, `canUpdate=true`; чужой `edit` → 403; `create` → `POST` → redirect на `/recipes/19`; `PUT` → redirect на `show`; `DELETE` → redirect на `index`; 404 на несуществующий id и на нечисловой id; страница data-компонентов (`Recipe/Index|Show|Create|Edit`) подтверждена в ответе Inertia; пункт меню «Рецепты» подтверждён в layout и во фронтенд-бандле. Тестовые данные стенда убраны по окончании сценария (стенд пуст).

## Пользовательская документация (user-visible изменения отражать в клиентском CLAUDE.md / README проекта)

**updated: 8db26fa (feat/recipe-docs, ждёт доставки)**: появился новый user-visible раздел «Рецепты» (список/деталь/создание/редактирование) и пункт меню в навигации. Формулировка пункта меню согласована с владельцем («Рецепты»); клиентский `README` дополнен секцией «Раздел «Рецепты»» отдельным `docs:`-коммитом `8db26fa` (разбор — `../../commits/cbook/8db26fa-recipe-docs.md`). У клиента нет `CLAUDE.md` — доки живут только в `README`.

## Итог

Работает: полный цикл страниц рецептов поверх FEAT-009/FEAT-010 — общий каталог с пагинацией (12/стр), просмотр открыт всем auth+verified, редактирование/удаление — только владельцу (403 чужому), формы create/edit шлют на мутационные маршруты 010 и после успеха возвращают на `show`/`index`. Первый Page Resolver в проекте зафиксирован чисто (модель-free, только DTO). Риски: пункт меню и раздел «Рецепты» — user-visible изменение, ожидающее согласования владельца для клиентской документации (см. выше); типизация пагинации (`Paginated<T>`) — прецедент для будущих списковых страниц, стоит переиспользовать, а не дублировать похожим интерфейсом.

## Ревью

- **Ревью чистоты** (субагент без доступа к внутренним артефактам, диф глазами тимлида клиента): вердикт **ЧИСТО** — следов процесса нет, стиль соответствует кодовой базе; единственное функциональное опасение (наличие `prev/next_page_url` в `meta` Spatie-пагинатора) снято живой приёмкой.
- **Независимое коммит-ревью ADR-010** (`../../commits/cbook/6116cff-review.md`): вердикт **PASS** (approve-with-nits, блокеров нет). Ревьюер сам перегнал гейты (Pint/PHPStan L10/Pest/ESLint/vue-tsc — зелёные) и адверсариально подтвердил ключевые риски: форма `meta` Spatie-пагинатора сверена с vendor-исходником, IDOR/канал `canUpdate` корректны, N+1-тесты не вакуумны, redirect-parity с мутациями. Ниты (не блокируют): `preventLazyLoading` в теле тестов «протекает» статическим флагом (консистентно с существующим RecipeRepositoryTest); отключение `no-undef` едет вместе с фичей (обосновано).
