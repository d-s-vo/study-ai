# FEAT-009: Слой данных Recipe/Ingredient — миграции, модели, Repository, DTO, автоген TS

## Статус: SPEC

## Затрагиваемые репозитории
cbook (backend) — один репозиторий. Мультирепный рецепт §3.5 не применяется.

## Цель
Заложить **фундамент домена** «Рецепты и Ингредиенты»: схему БД (`recipes` + `ingredients`), Eloquent-модели, enum `Difficulty`, `RecipeRepository` (единственное место Eloquent для домена), DTO `RecipeData`/`IngredientData` (Spatie Data) с автогенерацией TS-типов и фабрики. Это первая фича доменного пакета (FEAT-009 → 010 → 011): она даёт стабильный контракт данных, на котором строятся CRUD (010) и страницы (011).

## Контекст
База — `origin/develop @ 18c7282` (после merge пакета FEAT-005…008: инфраструктура, DTO-граница `UserData`, auth-hardening, фронт-гигиена — гейты зелёные). Домен ещё не существует: `app/Models/` содержит только `User`, `app/Data/` — только `UserData`, `app/Enums/` пуст, `app/Data/Repositories/` — только `UserRepository`. Это **greenfield-домен** (переписывание с нуля, не порт Prisma-схемы — см. `ai/memory.md` §Gotchas «схема пишется ЗАНОВО под MySQL 8»).

**Зачем строгий слой данных (педагогика).** Изоляция Eloquent в `app/Data/Repositories/*` (STRICT RULE 2, enforced PHPStan L10) означает, что вся работа с БД для домена концентрируется в одном классе — `RecipeRepository`. Это делает точку доступа к данным единственной и тестируемой, исключает «расползание» запросов по контроллерам/сервисам и позволяет менять хранилище, не трогая бизнес-логику. DTO (Spatie Data) — контракт «наружу»: то же определение полей порождает и PHP-тип, и TS-тип (`typescript:transform`), поэтому фронт и бэк не расходятся по форме данных. Начинаем со слоя данных, потому что **контракт всегда фиксируется до логики** (feature-workflow Шаг 7, «снизу-вверх»).

Доменная модель — ТЗ заказчика (`ai/memory.md` §North Star, `architecture.md` §1/§5).

### Поправка к ТЗ (принятое решение владельца, 2026-07-31)
ТЗ не задаёт владельца рецепта. Владелец **добавляет `recipes.user_id` (FK → `users`)** — это основа изоляции по владельцу и защиты от IDOR (STRICT RULE 5, `architecture.md` §8 «рецепты изолированы по владельцу»). `RecipePolicy` вводится в FEAT-010, но колонка и связь `Recipe belongsTo User` / `User hasMany Recipe` закладываются **здесь** (миграция + модель), чтобы схема была полной с первого дня.

## Acceptance Criteria
- [ ] Миграция создаёт таблицу `recipes`: `id`, `user_id` (FK→`users`, `ON DELETE CASCADE`), `title` (string), `description` (text), `cooking_time` (unsignedInteger, минуты), `servings` (unsignedInteger), `difficulty` (string/enum `low|medium|high`), `steps` (JSON), `timestamps`. `artisan migrate` на чистой БД проходит; `migrate:rollback` откатывает.
- [ ] Миграция создаёт таблицу `ingredients`: `id`, `recipe_id` (FK→`recipes`, `ON DELETE CASCADE`), `name` (string), `quantity` (decimal(8,2)), `unit` (string), `timestamps`. Удаление рецепта каскадно удаляет его ингредиенты (проверено тестом).
- [ ] `app/Enums/Difficulty.php` — backed enum `string` с кейсами `Low = 'low'`, `Medium = 'medium'`, `High = 'high'`.
- [ ] `app/Models/Recipe.php`: `hasMany(Ingredient::class)`, `belongsTo(User::class)`; casts `steps => 'array'`, `difficulty => Difficulty::class`; `$fillable` без `id`/`user_id` (mass-assignment защита — см. Безопасность).
- [ ] `app/Models/Ingredient.php`: `belongsTo(Recipe::class)`; cast `quantity => 'float'`.
- [ ] `app/Data/Repositories/RecipeRepository.php` (`final`, extends `BaseRepository`) — единственное место Eloquent для домена: методы CRUD + eager-load ингредиентов + управление ингредиентами (сигнатуры ниже). Арх-барьер зелёный.
- [ ] `app/Data/IngredientData.php` и `app/Data/RecipeData.php` (Spatie `Data`, `final`) существуют; `RecipeData` включает коллекцию `IngredientData`. `steps` — `array<int,string>`; `difficulty` — `Difficulty`.
- [ ] `artisan typescript:transform` генерирует в `resources/js/types/generated.d.ts` типы `App.Data.RecipeData`, `App.Data.IngredientData` и enum `App.Enums.Difficulty` (или строковый union); файл закоммичен.
- [ ] `database/factories/RecipeFactory.php` и `IngredientFactory.php` создают валидные записи; `Recipe::factory()->has(Ingredient::factory()->count(3))` работает.
- [ ] Pest-тесты слоя зелёные (см. Тесты); арх-тест расширен на новые модели (Eloquent `Recipe`/`Ingredient` используются только из `app/Data/Repositories/*`).
- [ ] Гейты: PHPStan L10 (0 подавлений), Pint pass, Pest 0 fail.

## Технический дизайн

### Миграция (контракт схемы — первый шаг)
- `database/migrations/XXXX_create_recipes_table.php`:
  ```
  $table->id();
  $table->foreignId('user_id')->constrained()->cascadeOnDelete();
  $table->string('title');
  $table->text('description');
  $table->unsignedInteger('cooking_time');   // минуты
  $table->unsignedInteger('servings');
  $table->string('difficulty');              // хранится как строка enum low|medium|high
  $table->json('steps');                     // JSON-массив строк
  $table->timestamps();
  ```
  > `difficulty` — `string` (не MySQL-`enum`-тип): значения валидируются на уровне PHP-enum `Difficulty` и FormRequest (010); строковая колонка проще для миграций/эволюции. Зафиксировать этот выбор.
- `database/migrations/XXXX_create_ingredients_table.php`:
  ```
  $table->id();
  $table->foreignId('recipe_id')->constrained()->cascadeOnDelete();
  $table->string('name');
  $table->decimal('quantity', 8, 2);
  $table->string('unit');
  $table->timestamps();
  ```
  > `quantity` — `decimal(8,2)`, не `float`: количество ингредиента не должно страдать от бинарного дрейфа float; в модели кастуется к `float` для DTO (число, а не строка). Зафиксировать.

### Enum
- `app/Enums/Difficulty.php` — `enum Difficulty: string { case Low = 'low'; case Medium = 'medium'; case High = 'high'; }`. Пометить `#[TypeScript]` (или auto-discover каталога `app/Enums`) для генератора типов.

### Eloquent-модели (только для чтения из Repository)
- `Recipe`: `protected $fillable = ['title','description','cooking_time','servings','difficulty','steps'];` (без `user_id` — владелец проставляется явно репозиторием, не из ввода; mass-assignment IDOR-защита). `protected function casts(): array { return ['steps' => 'array', 'difficulty' => Difficulty::class]; }`. Связи `ingredients(): HasMany`, `user(): BelongsTo`.
- `Ingredient`: `$fillable = ['name','quantity','unit']` (без `recipe_id` — проставляется через связь). Cast `quantity => 'float'`. Связь `recipe(): BelongsTo`.
- `User`: добавить `recipes(): HasMany` (обратная связь; правка одной строки в существующей модели).

### RecipeRepository (единственное место Eloquent домена)
**Решение развилки «отдельный `IngredientRepository` vs через `RecipeRepository`» → управление ингредиентами инкапсулируется в `RecipeRepository`, отдельного репозитория НЕ вводим.**
Обоснование: `Ingredient` — не самостоятельный агрегат, а **композиционная часть рецепта** (нет собственного ЖЦ, нет ingredient-level маршрутов, каскадное удаление, `hasMany`). Ингредиенты всегда создаются/меняются/удаляются в контексте своего рецепта — это один агрегат с корнем `Recipe`. Держать их синхронизацию внутри `RecipeRepository` (транзакция «рецепт + его ингредиенты») сохраняет консистентность агрегата и избегает анемичного passthrough-репозитория. Отдельный `IngredientRepository` был бы оправдан только при независимых запросах/мутациях ингредиентов — в скоупе пакета их нет.

**Контракт «наружу — не модели» (следствие арх-барьера).** Арх-тест (`tests/Feature/ArchitectureTest.php`) запрещает `App\Models\*` вне `App\Data\Repositories`/`Database\Factories`/`Database\Seeders` (namespace-wide). Значит слои Task/Controller/Resolver **не имеют права ссылаться на `Recipe`/`Ingredient`** (тип-хинт/`use`/статик-вызов). Поэтому репозиторий отдаёт наружу **DTO и скаляры**, а не Eloquent-модели. Единственное исключение — `findModel()` (для authz-handoff в FEAT-010, см. ниже): модель уходит в контроллер как значение переменной без явной ссылки на класс (паттерн `Authenticatable` из `UserRepository`) и **никогда не доходит до Inertia** (STRICT RULE 4 про границу Inertia/Vue соблюдён).

Сигнатуры (контракт для слоёв 010/011):
```
final class RecipeRepository extends BaseRepository
{
    // Чтение → DTO/скаляр (для Resolver'ов 011)
    public function paginateForUser(int $userId, int $perPage = 12): PaginatedDataCollection; // RecipeData, with('ingredients'), без N+1
    public function findData(int $id): ?RecipeData;                                            // eager 'ingredients' → DTO
    public function findModel(int $id): ?Recipe;                                               // ТОЛЬКО для authz (FEAT-010): owner-проверка Policy

    // Запись (для Task'ов 010) — атомарно рецепт + ингредиенты, возвращает скаляр
    public function createForUser(int $userId, array $recipeAttributes, array $ingredients): int; // id нового рецепта
    public function update(int $id, array $recipeAttributes, array $ingredients): void;           // syncIngredients в транзакции
    public function delete(int $id): void;                                                        // cascade удалит ингредиенты
}
```
- `createForUser`/`update` оборачивают запись в `DB::transaction(...)` (`DB` — легально, это репозиторий); ингредиенты синхронизируются стратегией delete+insert по `recipe_id` (простая консистентная стратегия для композиции без собственного ЖЦ).
- Маппинг модель→DTO (`RecipeData::from`/`::collect`) делается **внутри репозитория** (единственный слой, легально держащий и модель, и DTO) — наружу уходит уже DTO.
- Именование методов — согласовать со стилем существующего `UserRepository` (сверить при импле; там методы `create`/`updateProfile`/`delete` с `Authenticatable` + `assert`).
- `findModel` — узкий метод под авторизацию FEAT-010; в 009 он определён и покрыт тестом (возвращает модель по id или `null`), но потребитель (Policy/контроллер) появляется в 010.

### DTO (Spatie Data — контракт «наружу»)
- `app/Data/IngredientData.php`:
  ```
  final class IngredientData extends Data {
      public function __construct(
          public int $id,
          public string $name,
          public float $quantity,
          public string $unit,
      ) {}
  }
  ```
- `app/Data/RecipeData.php`:
  ```
  final class RecipeData extends Data {
      public function __construct(
          public int $id,
          public string $title,
          public string $description,
          public int $cooking_time,
          public int $servings,
          public Difficulty $difficulty,
          /** @var array<int,string> */
          public array $steps,
          /** @var array<int,IngredientData> */
          public array $ingredients,
          public ?string $created_at,
          public ?string $updated_at,
      ) {}
  }
  ```
  - Сборка — `RecipeData::from($recipe)` (magic `from` Spatie Data; `ingredients` мапится из загруженной связи; `created_at`/`updated_at` — ISO-строки). `user_id` наружу **не** отдаётся (внутреннее поле владения; фронту не нужно).
  - `#[TypeScript]` на обоих DTO (или auto-discover каталога `app/Data`).

### Автоген TS-типов
- Конфиг трансформера **кодовый**, в `app/Providers/TypeScriptTransformerServiceProvider.php` (не `config/*.php`): `transformDirectories(app_path('Data'))`, `EnumTransformer` уже включён, вывод `resource_path('js/types')` → `GlobalNamespaceWriter('generated.d.ts')`, `CarbonImmutable`/`DateTimeInterface → string`. Сканируется **только `app/Data`**.
- Т.к. `Difficulty` живёт в `app/Enums` (конвенция stack-specifics), **добавить `->transformDirectories(app_path('Data'), app_path('Enums'))`** в провайдер, иначе enum-тип не сгенерируется. (Альтернатива — положить enum под `app/Data` — отклонена: ломает конвенцию каталогов.)
- После создания DTO/enum — `artisan typescript:transform`; вывод `resources/js/types/generated.d.ts` → namespace `App.Data.RecipeData`, `App.Data.IngredientData`, `App.Enums.Difficulty`. **Файл коммитится** (детерминированная генерация, чтобы `vue-tsc`/CI не требовали PHP-шага — инвариант из FEAT-006).

### Фабрики
- `RecipeFactory`: `title`/`description` — faker; `cooking_time`/`servings` — `numberBetween`; `difficulty` — `fake()->randomElement(Difficulty::cases())`; `steps` — массив 2–5 строк; `user_id` — `User::factory()`.
- `IngredientFactory`: `name`, `quantity` (float), `unit`; `recipe_id` — `Recipe::factory()`.

## Тесты
**Добавить:**
- `tests/Feature/Recipe/RecipeRepositoryTest.php` (репозиторий резолвится `app(RecipeRepository::class)` в `beforeEach`, как `UserRepositoryTest`) — `createForUser` создаёт рецепт с N ингредиентами (одной транзакцией, `assertDatabaseHas`); `update` синхронизирует ингредиенты (было 3 → стало 2); `delete` удаляет рецепт **и** его ингредиенты (каскад — `assertDatabaseMissing` 0 строк в `ingredients`); `findData` грузит связь без N+1 (`Model::preventLazyLoading()` в тесте — исключение при ленивой загрузке); `paginateForUser` возвращает только рецепты владельца (создать 2 юзеров, проверить изоляцию); `findModel` возвращает модель по id и `null` по несуществующему.
- `tests/Unit/RecipeDataTest.php` — `RecipeData::from(Recipe::factory()->has(Ingredient::factory()->count(2))->create())` даёт корректные поля; `steps` — массив строк; `difficulty` — `Difficulty`; `ingredients` — 2× `IngredientData`; поле `user_id` в `->toArray()` DTO **отсутствует** (негативная проверка утечки владельца). (`tests/Unit` сейчас пуст — `RefreshDatabase` не применяется к Unit по `Pest.php`; если тесту нужна БД для фабрик — размещать в `tests/Feature/Recipe/`.)
- `tests/Feature/Recipe/RecipeCascadeTest.php` (или в RepositoryTest) — удаление `User` → каскад удаляет его рецепты и их ингредиенты (проверка FK-цепочки `users → recipes → ingredients`).
**Обновить:** `tests/Feature/ArchitectureTest.php` — правило `expect('App\Models')->toOnlyBeUsedIn([...])` **namespace-wide**, новые модели `Recipe`/`Ingredient` покрыты автоматически (allow-list не меняется в 009 — репозиторий уже в `App\Data\Repositories`). Правку allow-list (`+App\Policies`) делает **FEAT-010**. Опционально — добавить red→green кейс-нарушитель для домена (по образцу `DummyTask` из FEAT-004), подтверждающий, что барьер ловит утечку `Recipe` в Task.
**Удалить:** нет.

> Слой данных с владельцем: обязателен тест **изоляции по владельцу** (`paginateForUser` не отдаёт чужие рецепты) и **негативная** проверка неутечки `user_id` в DTO. Полные негативные тесты прав (403) — в FEAT-010 (там появляется Policy/маршруты).

## Типизация/качество
- Гейты: `sail bin phpstan analyse` (L10, 0 подавлений — casts/связи типизируются генериками Eloquent-хелперов; при необходимости PHPDoc-generics `HasMany<Ingredient>`), `sail bin pint --test`, `sail artisan test`.
- После создания DTO/enum — **обязательно** `artisan typescript:transform` (иначе TS-типы разъедутся); `generated.d.ts` коммитится.
- 0 `any`/`as`; типы фронта — только из генерации.

## Безопасность
- **Доступы:** новых маршрутов/endpoint нет — это слой данных. Policy/authorize вводятся в FEAT-010. Здесь важно заложить `user_id` для будущей изоляции.
- **Данные (IDOR-фундамент):** `user_id` — FK владельца; `RecipeRepository::paginateForUser` фильтрует по владельцу (изоляция). `RecipeData` **не** экспонирует `user_id` наружу (внутреннее поле). Негативный тест на неутечку — обязателен.
- **Mass assignment:** `user_id` (recipes) и `recipe_id` (ingredients) **исключены из `$fillable`** — владелец/родитель проставляются кодом (репозиторий/связь), а не из пользовательского ввода. Это блокирует попытку подмены владельца через payload.
- **Валидация:** входной валидации ещё нет (FormRequest — FEAT-010); фабрики/репозиторий работают с доверенными данными тестов. Боевые креды в тестах не используются (`.env.testing`).
- **Гигиена §8:** модели/DTO/миграции/тесты — человеческий стиль, без следов системы.

## Пользовательская документация
Внутренний слой данных, user-visible поведения нет. README упоминает `typescript:transform` — проверить актуальность; правок публичной доки не требуется (в `impl.md`: checked, no changes needed).

## Зависимые файлы для изменения
| Файл | Тип изменения |
|---|---|
| `database/migrations/XXXX_create_recipes_table.php` | новая миграция |
| `database/migrations/XXXX_create_ingredients_table.php` | новая миграция |
| `app/Enums/Difficulty.php` | новый enum |
| `app/Models/Recipe.php` | новая модель |
| `app/Models/Ingredient.php` | новая модель |
| `app/Models/User.php` | +связь `recipes(): HasMany` |
| `app/Data/Repositories/RecipeRepository.php` | новый репозиторий (CRUD + ингредиенты) |
| `app/Data/RecipeData.php` | новый DTO |
| `app/Data/IngredientData.php` | новый DTO |
| `app/Providers/TypeScriptTransformerServiceProvider.php` | +`transformDirectories(... app_path('Enums'))` для `Difficulty` |
| `resources/js/types/generated.d.ts` | регенерация (Recipe/Ingredient/Difficulty) |
| `database/factories/RecipeFactory.php` | новая фабрика |
| `database/factories/IngredientFactory.php` | новая фабрика |
| `tests/Feature/Recipe/RecipeRepositoryTest.php` | новые тесты |
| `tests/Unit/RecipeDataTest.php` | новые тесты |
| `tests/Feature/ArchitectureTest.php` | расширение арх-барьера на новые модели |

## Что НЕ входит в эту фичу
- **FormRequest, Tasks, Controller, Policy, маршруты** — FEAT-010 (CRUD + права).
- **Page Resolvers, Inertia Vue-страницы, пагинация в UI** — FEAT-011.
- **Filament 5 Resource** для Recipe (админка) — вне пакета.
- **Изображения рецептов** (`whyme-agency/laravel-media`) — вне пакета.
- **BVI-панель, публичный поиск/каталог** — вне пакета.
- Сидеры демо-данных (только фабрики для тестов).

## Оценка сложности
Средняя. Риски: (1) корректный маппинг связи `ingredients` в `RecipeData` через Spatie Data (коллекция вложенных DTO) — первый вложенный DTO в проекте; (2) детерминированность `generated.d.ts` (порядок типов) для чистого diff; (3) enum `Difficulty` в TS-генерации (union vs enum) — согласовать с настройкой трансформера; (4) L10-строгость на Eloquent-generics связей (`HasMany<Ingredient>` PHPDoc).
