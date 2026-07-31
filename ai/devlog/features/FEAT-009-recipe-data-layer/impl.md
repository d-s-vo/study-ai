---
feat: FEAT-009
repos: [cbook]
tags: [backend, database, dto, migration, domain]
class: 'фундамент домена Recipe/Ingredient — схема БД, модели, enum, репозиторий, DTO, автоген TS-типов, фабрики'
prevention: 'Pest arch-барьер (namespace-wide App\Models), негативный тест неутечки user_id в DTO, N+1-guard preventLazyLoading в тесте paginate'
---

# FEAT-009: Слой данных Recipe/Ingredient — Implementation

## Статус: DONE
## Дата: 2026-07-31

## Что сделано

| Файл | Изменение |
|---|---|
| `database/migrations/2026_07_31_000001_create_recipes_table.php` | новая миграция `recipes` (user_id FK cascade, title, description, cooking_time, servings, difficulty string, steps json, timestamps) |
| `database/migrations/2026_07_31_000002_create_ingredients_table.php` | новая миграция `ingredients` (recipe_id FK cascade, name, quantity decimal(8,2), unit, timestamps) |
| `app/Enums/Difficulty.php` | новый backed enum `string` (Low/Medium/High), помечен `#[TypeScript]` |
| `app/Models/Recipe.php` | новая модель: `hasMany(Ingredient)`, `belongsTo(User)`, casts steps→array, difficulty→Difficulty; fillable без id/user_id |
| `app/Models/Ingredient.php` | новая модель: `belongsTo(Recipe)`, cast quantity→float; fillable без recipe_id |
| `app/Models/User.php` | +связь `recipes(): HasMany` |
| `app/Data/Repositories/RecipeRepository.php` | новый `final` репозиторий: paginate/findModel/createForUser/update/delete, транзакции, маппинг в DTO |
| `app/Data/RecipeData.php` | новый DTO (вложенная коллекция IngredientData через `#[DataCollectionOf]`) |
| `app/Data/IngredientData.php` | новый DTO |
| `app/Providers/TypeScriptTransformerServiceProvider.php` | +`app_path('Enums')` в `transformDirectories` (иначе Difficulty не генерируется) |
| `resources/js/types/generated.d.ts` | регенерация: RecipeData, IngredientData, Difficulty (union) |
| `database/factories/RecipeFactory.php` | новая фабрика |
| `database/factories/IngredientFactory.php` | новая фабрика |
| `tests/Feature/Recipe/RecipeRepositoryTest.php` | 7 тестов репозитория (create/update/delete/paginate/findModel/cascade) |
| `tests/Feature/Recipe/RecipeDataTest.php` | 2 теста DTO (сборка из модели, негатив неутечки user_id) |
| `tests/Feature/ArchitectureTest.php` | allow-list +`App\Models` (связи между моделями) |

## Отклонения от spec

1. **ArchitectureTest allow-list ИЗМЕНЁН (spec предполагал «не менять в 009»).** Spec утверждал, что namespace-wide правило `expect('App\Models')->toOnlyBeUsedIn([...])` покрывает новые модели без правки allow-list. На практике межмодельные связи (`Recipe belongsTo User`, `Recipe hasMany Ingredient`, `User hasMany Recipe`) — это использование `App\Models\*` внутри самого `App\Models\*`, что старый allow-list запрещал (у `User`/`UserData` таких перекрёстных ссылок не было). Добавлен `'App\Models'` в allow-list с человеческим комментарием: связи Eloquent между моделями — часть слоя и не нарушают изоляцию (барьер по-прежнему блокирует Controllers/Tasks/Resolvers/Vue). Правку `+App\Policies` по-прежнему делает FEAT-010.
2. **`RecipeDataTest` размещён в `tests/Feature/Recipe/`, не в `tests/Unit/`** — как и предусматривала сама спека (примечание: Unit не получает `RefreshDatabase`, а тесту нужна БД для фабрик).
3. **`createForUser` создаёт рецепт через связь `User::recipes()->create()`**, а не прямым присваиванием `$recipe->user_id = $userId`. Причина: Larastan L10 выводит тип `user_id` как `int<0, max>` (из миграции `foreignId`), присваивание обычного `int` → ошибка `assign.propertyType`. Создание через relationship идиоматично, ставит FK автоматически и проходит L10 без каста/подавления.

## Follow-up (ревью ADR-010 коммита c48543f — Verdict PASS без блокеров, advisory)

Фикс-коммит `73050e3` (`refactor: единообразие типов дат в RecipeData и осмысленная проверка синхронизации ингредиентов`) закрыл два дешёвых advisory:
- **RecipeData.created_at/updated_at**: `?string` → `?CarbonImmutable` — единообразие с `UserData`; TS-тип не изменился (`replaceType(CarbonImmutable → 'string')`), `generated.d.ts` перегенерирован, diff пуст.
- **RecipeRepositoryTest sync-ассерция**: вакуумная `assertDatabaseMissing(... 'quantity'=>999)` заменена на осмысленную (фиксация исходных id + проверка их отсутствия после `update` + `assertDatabaseHas` по новым именам) — теперь ловит подмену стратегии sync.

Гейты после фикса: Pest **51 passed** (189 assertions), PHPStan L10 **No errors**, Pint **passed**.

Два advisory приняты **без фикса** (осознанно):
- (а) **down()-миграций без автотеста** — откат подтверждён вручную (`migrate:rollback --step=2` + повторный `migrate` проходят); риск тривиального `dropIfExists` минимален, отдельный тест не оправдан.
- (б) **red→green кейс-нарушитель арх-барьера для домена не добавлялся** — по spec это опционально; существующий PoC-нарушитель из FEAT-004 уже доказывает, что барьер ловит утечку моделей в слой Task.

## Ключевые решения по ходу реализации

- **Маппинг вложенной коллекции DTO** — атрибут `#[DataCollectionOf(IngredientData::class)]` на `public array $ingredients`. Даёт корректный PHP-маппинг из загруженной связи и TS-тип `App.Data.IngredientData[]` (первый вложенный DTO в проекте).
- **`created_at`/`updated_at` как `?string`** — Spatie Data сериализует Carbon в ISO-строку; TS-тип `string | null`. Работает без замечаний.
- **Синхронизация ингредиентов** — стратегия delete+insert внутри `DB::transaction` (композиция без собственного ЖЦ). `delete($id)` полагается на FK `cascadeOnDelete` (проверено тестом каскада от рецепта и от владельца).
- **Автоген TS** — генератор сканирует только `app/Data`; `Difficulty` живёт в `app/Enums` по конвенции, поэтому в провайдер добавлен второй каталог.

## Как тестировали

- Baseline (до правок): Pest **43 passed**, PHPStan L10 **No errors**, Pint **passed** (после штатной настройки окружения свежего worktree: `.env`/`.env.testing`, APP_KEY, testing-БД/пользователь, `pnpm build` для Vite-манифеста).
- После реализации: Pest **51 passed** (147→186 assertions; +8 новых доменных тестов), PHPStan L10 **No errors** (0 подавлений), Pint **passed**.
- `artisan typescript:transform` — сгенерировал `App.Data.RecipeData`, `App.Data.IngredientData`, `App.Enums.Difficulty`.
- `migrate` / `migrate:rollback --step=2` / повторный `migrate` — проходят на чистой БД.
- **Живая приёмка (tinker на стенде):** `createForUser` → рецепт с 2 ингредиентами, owner проставлен; `findModel` — eager `ingredients` + `user_id`; `RecipeData::from` — ключи без `user_id` (нет утечки), `difficulty` enum, `steps` массив, `quantity` = 300.5 (float); `paginate` total=1; `update` синхронизировал 2→1; удаление владельца каскадно вычистило рецепт и ингредиенты.

## Пользовательская документация

checked, no changes needed — внутренний слой данных, user-visible поведения нет; README уже упоминает `typescript:transform`.

## Итог

Фундамент домена заложен: стабильный контракт данных (схема + DTO + TS-типы) для CRUD (FEAT-010) и страниц (FEAT-011). Eloquent домена изолирован в `RecipeRepository`, наружу уходят только DTO/скаляры (кроме `findModel` для authz-handoff). Риски на будущее: allow-list арх-теста теперь допускает межмодельные ссылки — это ожидаемо и корректно, но при вводе новых слоёв (Policies в 010) их доступ к моделям нужно оценивать отдельно.
