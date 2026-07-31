---
repo: cbook
authored_hash: c48543f8f38d82e666c3daf1417b09f79e7dae42
patch_id: 634101e0ef36c6bcab02beb740bdb2a6730664e2
branch: feat/recipe-data-layer
feat: FEAT-009
date: 2026-07-31
final_hash:
---

# cbook@c48543f — feat: слой данных рецептов и ингредиентов

> Коммит-сообщение (как в клиентском репо): `feat: слой данных рецептов и ингредиентов`

## Кратко (для инженера)

- `database/migrations/2026_07_31_000001_create_recipes_table.php` — таблица `recipes`; `user_id` FK `cascadeOnDelete`; `difficulty` строкой; `steps` json.
- `database/migrations/2026_07_31_000002_create_ingredients_table.php` — таблица `ingredients`; `recipe_id` FK `cascadeOnDelete`; `quantity` decimal(8,2).
- `app/Enums/Difficulty.php` — backed enum `string` (low/medium/high), `#[TypeScript]`.
- `app/Models/Recipe.php` / `Ingredient.php` — модели, связи, casts; `$fillable` без `user_id`/`recipe_id` (mass-assignment защита).
- `app/Models/User.php` — `recipes(): HasMany`.
- `app/Data/Repositories/RecipeRepository.php` — единственное место Eloquent домена; CRUD + синхронизация ингредиентов в `DB::transaction`; наружу — DTO/скаляры, `findModel` — модель под authz.
- `app/Data/RecipeData.php` / `IngredientData.php` — DTO Spatie Data; вложенная коллекция через `#[DataCollectionOf]`.
- `app/Providers/TypeScriptTransformerServiceProvider.php` — +`app_path('Enums')` в скан.
- `resources/js/types/generated.d.ts` — регенерация типов.
- `database/factories/*` — фабрики Recipe/Ingredient.
- `tests/Feature/Recipe/*` — тесты репозитория и DTO.
- `tests/Feature/ArchitectureTest.php` — allow-list +`App\Models` (межмодельные связи).

## Детально (для новичка)

### `database/migrations/2026_07_31_00000{1,2}_*`
Миграция — это версионируемый скрипт, создающий/меняющий структуру таблиц БД (вместо ручных SQL в консоли). `foreignId('user_id')->constrained()->cascadeOnDelete()` создаёт внешний ключ на `users.id` с правилом: удалили пользователя — БД сама удалит его рецепты (каскад). Аналогично `recipe_id` в ингредиентах. `difficulty` хранится строкой (а не MySQL-типом `enum`) — так проще эволюционировать схему; допустимые значения гарантирует PHP-enum. `quantity` — `decimal(8,2)`: точное десятичное, чтобы количество не «плавало» из-за двоичного представления float. `steps` — колонка `json`: список шагов рецепта не имеет своего id/жизненного цикла, ему не нужна отдельная таблица.

### `app/Enums/Difficulty.php`
Backed enum — перечисление с привязанным скалярным значением (`Low = 'low'`). Модель кастует строку из БД в этот enum, а генератор типов превращает его в TS-объединение `'low' | 'medium' | 'high'`. Атрибут `#[TypeScript]` помечает enum для выгрузки во фронтовые типы.

### `app/Models/Recipe.php`, `app/Models/Ingredient.php`
Eloquent-модель — PHP-класс, отображающий строку таблицы. `casts()` объявляет автоматические преобразования: `steps` ↔ массив, `difficulty` ↔ enum, `quantity` ↔ float. Связи `hasMany`/`belongsTo` описывают «у рецепта много ингредиентов» и «ингредиент принадлежит рецепту». `$fillable` — белый список полей для массового заполнения; `user_id` и `recipe_id` в него НЕ входят: владелец/родитель проставляются кодом, а не из пользовательского ввода — это защита от подмены владельца (класс уязвимостей IDOR).

### `app/Data/Repositories/RecipeRepository.php`
Репозиторий — единственный слой, которому разрешено обращаться к Eloquent/`DB` (архитектурное правило проекта, проверяется статанализом и arch-тестом). Он инкапсулирует все запросы к БД для домена. Записи (`createForUser`/`update`) обёрнуты в `DB::transaction` — либо всё сохранилось (рецепт + ингредиенты), либо ничего (атомарность). Наружу репозиторий отдаёт DTO (через `RecipeData::collect`/`from`) и скаляры, а не модели — чтобы Eloquent не «протёк» в контроллеры/страницы. Исключение — `findModel`: возвращает модель для будущей проверки прав (Policy, FEAT-010).

### `app/Data/RecipeData.php`, `app/Data/IngredientData.php`
DTO (Data Transfer Object) на Spatie Laravel Data — неизменяемое описание «формы данных наружу». Из одного определения полей рождается и PHP-тип, и TS-тип (командой `typescript:transform`), поэтому фронт и бэк не расходятся. `#[DataCollectionOf(IngredientData::class)]` подсказывает, что `ingredients` — массив вложенных DTO (первый вложенный DTO в проекте). `user_id` в DTO намеренно отсутствует — это внутреннее поле владения, фронту не нужно.

### `app/Providers/TypeScriptTransformerServiceProvider.php`
Провайдер конфигурирует генератор TS-типов кодом. Генератор сканирует каталоги; `Difficulty` лежит в `app/Enums`, поэтому каталог добавлен в `transformDirectories`, иначе enum-тип не сгенерировался бы.

### `database/factories/RecipeFactory.php`, `IngredientFactory.php`
Фабрика — генератор фейковых, но валидных записей для тестов. `Recipe::factory()->has(Ingredient::factory()->count(3))` создаёт рецепт сразу с тремя ингредиентами.

### `tests/Feature/ArchitectureTest.php`
Arch-тест проверяет архитектурные правила как код. Правило «модели используются только в репозиториях/фабриках/сидерах» теперь дополнено `App\Models`: связи между самими моделями — часть Eloquent и не считаются утечкой. Барьер по-прежнему ловит обращение к моделям из контроллеров/Task/резолверов.

## Почему так, а не иначе

- **Отдельный `IngredientRepository` — отклонён.** Ингредиент не самостоятельный агрегат (нет своего ЖЦ/маршрутов, каскадное удаление) — его синхронизация живёт внутри `RecipeRepository` одной транзакцией.
- **`difficulty` как MySQL-`enum` — отклонён** в пользу строки: проще миграции/эволюция, значения валидирует PHP-enum.
- **Прямое присваивание `$recipe->user_id = $userId` — отклонено:** Larastan L10 типизирует FK как `int<0, max>` и падает на присваивании обычного `int`. Создание через связь `User::recipes()->create()` идиоматично и проходит L10 без каста/подавления.
- **`App\Models` в allow-list арх-теста** — вынужденное расхождение со spec (тот считал правку ненужной): межмодельные связи иначе валят namespace-wide правило.

## Связи

- Фича: `../features/FEAT-009-recipe-data-layer/impl.md` · `../features/FEAT-009-recipe-data-layer/spec.md`.
- Смежные фичи пакета: FEAT-010 (CRUD/Policy), FEAT-011 (Resolver/Inertia).
- Арх-инварианты: `../../adr/003-layered-architecture.md`.
