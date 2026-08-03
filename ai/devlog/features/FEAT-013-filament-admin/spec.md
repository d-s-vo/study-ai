# FEAT-013: Filament-админка `/admin` + STRICT-ревиз сгенерированного

## Статус: SPEC (specs-first — до реализации требуется СТОП-точка утверждения владельцем)

## Затрагиваемые репозитории
`cbook` (backend + frontend-админка) — один репозиторий. Мультирепный рецепт §3.5 не применяется.

## Цель
Установить **Filament 5** (админ-панель по адресу `/admin`) в существующий Laravel 12-проект cbook и провести **STRICT-ревиз всего сгенерированного кода** так, чтобы он проходил жёсткие гейты проекта (PHPStan Level 10 без подавлений, Pint psr12+strict, Pest, арх-барьер изоляции Eloquent) и выглядел «как писал бы человек». Панель даёт управление доменом **Recipe / Ingredient / User** поверх уже существующей строгой слоистой архитектуры (ADR-003), не ломая её инвариантов и публичный Inertia-фронт.

## Контекст
База — `origin/develop` поверх доменного пакета **FEAT-009…011** (Recipe/Ingredient: слой данных, DTO, `RecipeRepository`, Tasks Create/Update/Delete, `RecipePolicy`, Inertia-страницы) и auth-пакета **FEAT-004…008** (Breeze Inertia, `User implements MustVerifyEmail`, email-верификация включена, `UserData`-DTO наружу). Инициатива — **ADR-006** (переписывание cbook на Laravel), следующий этап после закрытого доменного пакета; целевой стек по **ADR-002** прямо называет **Filament 5** как админку.

**Факты кода на момент спеки** (worktree `tasks/filament-admin/`, проверено):
- Filament **отсутствует** в `composer.json`/`composer.lock`; каталога `app/Filament/` нет; в `bootstrap/providers.php` только `AppServiceProvider`; `config/filament.php` нет; в `routes/web.php` `/admin` не занят.
- `app/Models/User.php`: `extends Authenticatable implements MustVerifyEmail`; traits `HasFactory, Notifiable`; `$fillable = [name, email, password]`; `$hidden = [password, remember_token]`; `casts: email_verified_at→datetime, password→hashed`. **Роли/поля `is_admin` НЕТ**; `canAccessPanel()` НЕ реализован.
- `app/Models/Recipe.php`: `$fillable = [title, description, cooking_time, servings, difficulty, steps]`; `casts: steps→array, difficulty→Difficulty::class`; связи `ingredients(): HasMany`, `user(): BelongsTo`. `Ingredient`: `$fillable = [name, quantity, unit]`; `casts: quantity→float`; `recipe(): BelongsTo`.
- DTO (Spatie Data, `#[TypeScript]`, `final extends Data`): `RecipeData` (без `user_id`), `IngredientData`, `UserData` (`id, name, email, ?email_verified_at` — без `password`/`user_id`).
- `RecipePolicy` (`final`): `viewAny/view/create → true` (общий каталог), `update/delete → $user->id === $recipe->user_id` (анти-IDOR). **admin-override отсутствует.**
- `RecipeRepository extends BaseRepository` (пустой abstract): `paginate(int $perPage=12)`, `findModel(int): ?Recipe`, `createForUser(int,array,array): int`, `update(int,array,array): void`, `delete(int): void` — все мутации в `DB::transaction`, транзакционная синхронизация ингредиентов. Есть `UserRepository`.
- **`tests/Feature/ArchitectureTest.php`** — арх-барьер (дословно две проверки):
  1. `expect('App\Models')->toOnlyBeUsedIn(['App\Models','App\Data\Repositories','App\Policies','Database\Factories','Database\Seeders'])`;
  2. `expect('Illuminate\Support\Facades\DB')->toOnlyBeUsedIn('App\Data\Repositories')`.
- `phpstan.neon`: `level: 10`, `paths: [app]`, **baseline отсутствует**. `pint.json`: `preset psr12` + `declare_strict_types: true`.
- Фронт: Tailwind **v3** (`tailwindcss ^3.2.1`, `@tailwindcss/forms`, **не v4** — нет `@tailwindcss/vite`/`postcss`), Vite `^7`, `laravel-vite-plugin ^2`, вход `resources/js/app.ts` (Vue 3 + Inertia + TS). `tailwind.config.js` content не включает `vendor/filament/**`.

**Версия Filament (проверено по вебу 2026-08-03):** актуальный стабильный мажор — **Filament v5** (последний релиз `v5.7.5`, 2026-07-31; `require php: ^8.2`; выпущен вместе с Laravel 12, нативная совместимость). Проект: PHP `^8.2` (lock 8.4), Laravel `v12.64`. **Расхождения с «Filament 5» из ADR-002 НЕТ** — ставим v5; точный минор пиннуется на этапе impl (как Laravel `12.64` в FEAT-002). Открытый вопрос Q3 остаётся формальным подтверждением (низкий риск).

## Открытые вопросы владельцу (блокеры СТОП-точки) ⛔
> Спека написана под **рекомендованные дефолты** ниже; реализация НЕ стартует до явного «утверждено» по каждому пункту. Дефолты помечены **[рек.]**.

1. **Кто админ?** У `User` нет роли/флага. Варианты: (а) bool-поле `is_admin` + миграция + сидер первого админа; (б) enum/поле роли; (в) пакет ролей (Spatie Permission). **[рек.] (а) `is_admin` bool** — минимально для учебного этапа, без веса Spatie Permission. Нужна миграция `add_is_admin_to_users` (default `false`) + сидер/artisan-команда назначения первого админа. Подтвердить вариант и способ бутстрапа первого админа (сидер vs. команда vs. ручной tinker).
2. **Граница Filament ⟷ изоляция Eloquent** (см. «Технический дизайн» §Конфликт): подход **A / B / C**? **[рек.] C (гибрид)**: чтение — через модель в Resource (в рамках расширенного allow-list арх-барьера), мутации/бизнес-правила — через существующие Tasks (`Create/Update/DeleteRecipeTask` → `RecipeRepository`, транзакции сохраняются), авторизация — через Policies. **Заводим ли decision-ADR-011** под расширение инварианта ADR-003 + allow-list? **[рек.] Да** (меняется машинно-энфорсимый инвариант — критерий adr/README «меняется принятое решение»).
3. **Версия Filament:** ставим **v5** (актуальный стабильный, совместим с Laravel 12 / PHP 8.4; расхождения с ADR-002 нет). Подтвердить пин минорной версии на impl; уточнять ADR-002 не требуется.
4. **Состав ресурсов и глубина:** **[рек.]** Recipe (полный CRUD) + Ingredient (**RelationManager** под Recipe, не top-level) + User (**read-only**: список+просмотр, без create/edit/delete). Достаточно ли? Нужен ли User-Resource вообще (или только Recipe)? Какие поля User показывать (без `password`/`remember_token`; предлагается `id, name, email, email_verified_at, recipes_count, created_at`)?
5. **Доступ панели и верификация:** `/admin` под web-guard + `canAccessPanel()` = `is_admin && hasVerifiedEmail()` (email-верификация включена). Админ **видит и правит ВСЕ рецепты всех пользователей** (супер-доступ поверх `RecipePolicy` — реализуется через `RecipePolicy::before()` для админа). Подтвердить, что это ожидаемо (а не дыра изоляции).
6. **Медиа/загрузка изображений** рецептов в админке (`whyme-agency/laravel-media`) — **вне** этой фичи (следующий этап). Подтвердить исключение из scope.
7. **Формулировка в клиентском README** про админку (user-visible, без следов системы) — согласовать текст (напр. «Administration panel is available at `/admin` for users with administrator access»).

## Acceptance Criteria
> AC под рекомендованные дефолты (вариант is_admin + подход C). При ином решении владельца — скорректировать до реализации.

**Установка и загрузка панели**
- [ ] `composer require filament/filament:"^5.0"` установлен; точная версия зафиксирована в `impl.md` (пин в `composer.json`/lock).
- [ ] `php artisan filament:install --panels` отработал: создан `app/Providers/Filament/AdminPanelProvider.php`, зарегистрирован в `bootstrap/providers.php`; панель по `path('admin')`.
- [ ] `GET /admin/login` доступен; ассеты Filament публикуются собственным пайплайном Filament (`filament:assets`), **публичный Inertia-фронт (`resources/js/app.ts`, Vite, Tailwind v3) не затронут**: `pnpm build` зелёный, публичные страницы (`/`, `/recipes`) рендерятся как раньше.

**Доступ**
- [ ] Миграция добавляет `users.is_admin` (bool, default `false`, not null); `User` кастует `is_admin→bool`, поле в `$fillable` **не добавляется** (mass-assignment-защита), назначение — через сидер/команду.
- [ ] `User implements FilamentUser`; `canAccessPanel(Panel): bool` → `$this->is_admin && $this->hasVerifiedEmail()`.
- [ ] Админ (is_admin + verified) → `GET /admin` = **200**. Не-админ (авторизован, `is_admin=false`) → **403**. Гость → redirect на `/admin/login`. Верифицированный, но `is_admin=false` → **403**. **(негативы обязательны)**.

**Ресурсы**
- [ ] `RecipeResource` (`app/Filament/Resources/`): таблица (title, difficulty, cooking_time, servings, user, ingredients_count), формы create/edit (title, description, cooking_time, servings, difficulty[enum], steps[repeater], ingredients[RelationManager]).
- [ ] `IngredientRelationManager` под RecipeResource: hasMany, добавление/редактирование/удаление ингредиентов рецепта (name, quantity, unit); каскад при удалении рецепта сохраняется (FK cascade из FEAT-009).
- [ ] `UserResource` (**read-only**): таблица (id, name, email, email_verified_at, recipes_count, created_at); просмотр записи; **create/edit/delete отключены**; `password`/`remember_token` **не выводятся** ни в таблице, ни в форме.
- [ ] Админ видит **все** рецепты всех пользователей (супер-доступ); create/update/delete рецепта в панели — через существующие Tasks (см. дизайн), не прямой `->save()` на модели.

**STRICT-ревиз**
- [ ] Каждый сгенерированный `.php` (Provider, Resources, Pages, RelationManager) начинается с `declare(strict_types=1)`.
- [ ] `./vendor/bin/sail bin phpstan analyse` — **L10, 0 ошибок, 0 новых подавлений/baseline** (по `app/`, включая `app/Filament`).
- [ ] `./vendor/bin/sail bin pint --test` — зелёный (psr12+strict) по всем новым файлам.
- [ ] Арх-барьер (`ArchitectureTest`) зелёный после **явного** расширения allow-list (red→green доказан, см. дизайн); правило `DB`-фасада **не расширяется** (Filament к `DB` не обращается).
- [ ] Ноль следов ИИ/генератора/системы в коде, комментариях, ветке, коммитах (§8).

**Гейты/приёмка**
- [ ] Pest 0 fail (новые тесты доступа + CRUD + изоляция полей User); PHPStan L10; Pint; `pnpm build` зелёный.
- [ ] Живая приёмка `/admin` на изолированном стенде брони (свой порт, эфемерная БД) — сценарии ниже пройдены живьём, включая негатив доступа.

## Технический дизайн

### 1. Установка Filament 5 и взаимодействие с Vite/Inertia/Tailwind v3
- **Пакет:** `filament/filament:"^5.0"` через Sail-composer (`./vendor/bin/sail composer require ...`), т.к. PHP-тулчейн только в контейнере. Точная версия — пин в impl.
- **Инициализация:** `sail artisan filament:install --panels` → генерирует `App\Providers\Filament\AdminPanelProvider` (панель `admin`, path `/admin`), прописывает провайдер в `bootstrap/providers.php`. `sail artisan filament:assets` публикует ассеты.
- **Изоляция от публичного фронта (ключевое — «не сломать публичный фронт»):** Filament v5 несёт **собственный** скомпилированный CSS/JS и свой пайплайн ассетов, **независимый** от `vite.config.js`/`resources/js/app.ts`/`tailwind.config.js` проекта. Рекомендация: **использовать дефолтную тему Filament**, `vite.config.js` и `tailwind.config.js` публичного фронта **НЕ трогать** (не добавлять `vendor/filament/**` в content, не подмешивать Filament в общий Vite-bundle). Так публичный Inertia-фронт (Tailwind v3) и админка живут на раздельных ассет-пайплайнах — нулевой риск конфликта утилит/сборки. Кастомная Filament-тема (интеграция в общий Tailwind) — **вне scope** (при желании — отдельная фича).
- **Совместимость:** Filament v5 требует PHP `^8.2` (у нас 8.4 ✓), нативно под Laravel 12 (✓), Inertia v2 сосуществует (разные роут-группы, разные ассеты).

### 2. Доступ к панели `/admin`
- **Миграция** `database/migrations/*_add_is_admin_to_users_table.php`: `$table->boolean('is_admin')->default(false);`.
- **Модель `User`:** `implements MustVerifyEmail, FilamentUser`; в `casts()` добавить `'is_admin' => 'boolean'`; `is_admin` **вне** `$fillable` (защита от mass-assignment — назначается сидером/командой, не формой).
  ```php
  public function canAccessPanel(Panel $panel): bool
  {
      return $this->is_admin && $this->hasVerifiedEmail();
  }
  ```
- **Бутстрап первого админа:** сидер `AdminUserSeeder` или artisan-команда `app:make-admin {email}` (обновляет `is_admin=true` через `UserRepository` — Eloquent остаётся в репозитории). Способ — на выбор владельца (Q1). Пароль/email первого админа — из `.env`/интерактивно, не хардкод.
- **Middleware:** панель наследует web-guard; email-верификация форсится и в `canAccessPanel`, и (опц.) через `->authMiddleware([..., EnsureEmailIsVerified::class])` в конфиге панели.

### 3. Ресурсы Filament (обоснование состава)
- **RecipeResource** (top-level, полный CRUD) — центральная доменная сущность, ради неё и ставится панель.
- **Ingredient → `IngredientRelationManager` под RecipeResource** (не отдельный top-level Resource): ингредиент — **композиционная часть агрегата Recipe** (`hasMany`, FK cascade, нет самостоятельного ЖЦ вне рецепта — ровно как трактует его `RecipeRepository`, синхронизируя ингредиенты внутри транзакции рецепта). Top-level-ресурс ингредиента навязал бы независимый CRUD, противоречащий агрегату. RelationManager редактирует ингредиенты **в контексте** рецепта — семантически верно.
- **UserResource — read-only** (просмотр/список, без мутаций): админке полезно видеть пользователей и их рецепты, но управление учётками (сброс пароля, удаление) — чувствительная поверхность вне scope учебной фичи; `password`/`remember_token`/токены **не экспонируются** (в форме/таблице — только безопасные поля из перечня Q4, по образцу `UserData`-DTO). Отключить `canCreate/canEdit/canDelete` на ресурсе.

### 4. КЛЮЧЕВОЙ конфликт: Filament ⟷ изоляция Eloquent (ADR-003 rule 2)
**Суть.** Filament Resource привязан к Eloquent-модели (`protected static ?string $model = Recipe::class`, `getEloquentQuery()`, формы/таблицы строят запросы к модели). Но арх-барьер проекта разрешает `App\Models` только в `App\Models / App\Data\Repositories / App\Policies / Database\{Factories,Seeders}`. Любой Resource в `App\Filament\*`, назвавший `App\Models\Recipe`, **краснит `ArchitectureTest` rule #1** (и, как правило, не проходит L10/strict «из коробки»).

**Рассмотренные подходы и цена:**

| Подход | Суть | Цена |
|---|---|---|
| **A. Санкционированное исключение** | Признать `App\Filament` легитимным местом работы с Eloquent; добавить `'App\Filament'` в allow-list rule #1. Resource читает/пишет модель напрямую. | Проще всего, но **дублирует бизнес-логику**: `RecipeRepository::createForUser/update` делает транзакционную синхронизацию ингредиентов; прямой `->save()` из Filament обойдёт её (риск рассинхрона агрегата) и размажет мутации по Resource (анти-паттерн «бизнес-логика в Filament Resource»). Максимально ослабляет инвариант. |
| **B. Всё через Repository/Task** | Кастомные `getTableQuery`/actions, делегирующие в Repository/Task; модель в Resource не появляется. | Тяжёлая борьба с фреймворком (Filament ждёт Eloquent-query для сортировки/фильтров/пагинации/relation-manager), много хрупкого кастома; педагогически спорно; часть возможностей панели теряется. |
| **C. Гибрид (рекомендуется)** | **Чтение** (table query, form fill, relation-manager) — через модель в Resource, в рамках расширенного allow-list. **Мутации** (create/update/delete) — делегируются существующим Tasks через хуки Filament (`handleRecordCreation`/`handleRecordUpdate`/`handleRecordDeletion` или `mutateFormDataBeforeSave` + вызов Task). **Авторизация** — через существующие Policies. | Умеренный кастом на мутационных хуках, но **единый источник правды** мутаций (Tasks/Repository, транзакции сохранены), инвариант ослаблен точечно (только чтение из модели в админ-слое). Соответствует роли `app/Filament` из ADR-003 («Resource без бизнес-логики, делегирует в Task/Repository»). |

**Рекомендация — C.** Обоснование: сохраняет транзакционную целостность агрегата Recipe+Ingredients (не дублирует `RecipeRepository`), держит бизнес-логику в Tasks (канон), а Eloquent-чтение в админ-слое — осознанное точечное послабление, а не размывание правила. Граница фиксируется явно:
- **Filament можно:** ссылаться на модель для чтения (table/form/relation query, `getEloquentQuery`), объявлять `$model`.
- **Filament нельзя:** прямые мутации `->save()/->create()/->delete()` с бизнес-смыслом и **любое обращение к фасаду `DB`** — мутации идут через Tasks; **правило `DB`-фасада в арх-барьере НЕ расширяется** и остаётся машинным guard'ом против сырых записей в Filament.

**Расширение allow-list (red→green, по образцу FEAT-009 `App\Models`, FEAT-010 `App\Policies`):**
```php
// tests/Feature/ArchitectureTest.php, rule #1 → добавить 'App\Filament'
->toOnlyBeUsedIn([
    'App\Models','App\Data\Repositories','App\Policies',
    'App\Filament',                      // ← админ-слой: чтение моделей в Resource/RelationManager
    'Database\Factories','Database\Seeders',
]);
```
Доказать **red→green**: без строки `'App\Filament'` — `ArchitectureTest` краснеет на первом Resource; со строкой — зеленеет. Правило #2 (`DB` → только репозитории) **не трогаем** — оно продолжает ловить попытку сырого `DB`-доступа из Filament.

**PHPStan L10:** `app/Filament` остаётся в `paths` (не исключаем, не заводим baseline) — сгенерированный код доводится до 0 ошибок вручную (типы hooks, сигнатуры, generics Filament v5). Это и есть основной объём STRICT-ревиза.

**Супер-доступ админа vs. RecipePolicy (анти-IDOR).** Filament автоприменяет Policy модели. `RecipePolicy::update/delete` проверяют владельца → админ получил бы 403 на чужой рецепт. Решение: добавить в `RecipePolicy` хук
```php
public function before(User $user): ?bool
{
    return $user->is_admin ? true : null; // админ — супер-доступ ко всем рецептам
}
```
Это **осознанный супер-доступ** (админ по замыслу видит/правит всё), а не дыра изоляции: для обычных пользователей owner-scoping (FEAT-010) без изменений (`before` возвращает `null`). Правка `RecipePolicy` — затрагивает файл с тестами FEAT-010 → существующие негативные IDOR-тесты **должны остаться зелёными** (не-админ чужой → 403), добавляется позитив «админ → доступ». Флаг на подтверждение владельцу (Q5).

**decision-ADR-011** (рекомендуется завести): фиксирует выбор подхода C, точную границу «Filament можно/нельзя», расширение allow-list rule #1 при сохранении rule #2, супер-доступ админа через `Policy::before`. Статус «Принят»; ссылки на ADR-003 (уточняет инвариант изоляции для админ-слоя) и ADR-002. Коммит через `ai-commit.sh` (номер — `coord.sh book filament-admin --adr`, ожидаемый **ADR-011**). Критерий adr/README: «меняется уже принятое машинно-энфорсимое архитектурное решение» + «неочевидный компромисс между подходами» → ADR нужен.

### 5. STRICT-ревиз сгенерированного (основной объём)
Каждый файл после генерации доводится вручную:
- `declare(strict_types=1)` первой строкой (генераторы Filament не ставят) — Pint это чинит/проверяет.
- Типобезопасность L10: явные типы аргументов/возвратов в hooks (`mutateFormDataBeforeCreate(array $data): array`, `handleRecordCreation(array $data): Model` и т.п.), корректная работа с generics таблиц/форм Filament v5; 0 подавлений.
- Стиль/комментарии — по-человечески, по стилю окружающих файлов; без ссылок на внутренние доки/FEAT.
- `pint --test` зелёный; ноль следов генератора/ИИ; ноль `~wip~` в финале.

### 6. Порядок реализации (снизу-вверх, атомарно)
(миграция `is_admin` → каст+`FilamentUser`/`canAccessPanel` в `User` → сидер/команда админа) → `composer require filament` + `filament:install` + провайдер панели → `RecipePolicy::before` (супер-доступ) → расширение allow-list арх-барьера (red→green) → RecipeResource (чтение) → мутационные хуки через Tasks → IngredientRelationManager → UserResource (read-only) → STRICT-ревиз каждого файла → тесты → живая приёмка. Тесты — после каждого блока.

## Тесты

**Добавить:**
- `tests/Feature/Admin/AdminPanelAccessTest.php`:
  - позитив: `actingAs(admin_verified)->get('/admin')` → **200**.
  - негатив (обязательно): не-админ (`is_admin=false`, verified) → **403**; гость → redirect `/admin/login`; админ-флаг без верификации email → **403** (проверка `hasVerifiedEmail` в `canAccessPanel`).
- `tests/Feature/Admin/RecipeResourceTest.php` (Livewire-хелперы Filament, `Filament\...\livewire()` / `Livewire::test`):
  - список: админ видит рецепты **разных** владельцев (супер-доступ; создать рецепты от 2 юзеров).
  - create через форму панели → запись в БД **через Task** (проверить, что ингредиенты синхронизированы транзакционно, как в FEAT-009: рецепт + N ингредиентов, каскад).
  - update/delete через панель → изменения применены; delete каскадит ингредиенты.
  - IngredientRelationManager: добавление/удаление ингредиента рецепта.
- `tests/Feature/Admin/UserResourceTest.php`:
  - список/просмотр пользователя администратором → **200**.
  - **изоляция чувствительных полей (обязательно, позитив+негатив):** в ответе таблицы/формы/Infolist ресурса **нет** `password`, `remember_token` (ассерт отсутствия); create/edit/delete-экшены недоступны (read-only).
- `tests/Feature/ArchitectureTest.php` — правило #1: PoC red→green расширения allow-list зафиксировать в impl (тест остаётся зелёным с `App\Filament`).

**Обновить:**
- `tests/Feature/*RecipeCrud*`/policy-тесты FEAT-010: остаются зелёными (owner-scoping для не-админа не изменился); добавить кейс «админ → доступ к чужому рецепту» после `RecipePolicy::before`.

**Удалить:** нет.

> Права и чувствительные данные → **позитив И негатив** обязательны: доступ к панели (админ 200 / не-админ 403 / гость redirect), изоляция полей User (нет `password`/токенов), супер-доступ vs. owner-scoping.

## Типизация/качество (минимальный набор гейтов)
- Backend: `sail bin phpstan analyse` (**L10, 0 ошибок, 0 новых подавлений/baseline** — включая `app/Filament`), `sail bin pint --test` (psr12+strict), `sail artisan test` (Pest, 0 fail). Тяжёлые прогоны — через `gate.sh <ресурс>`.
- Frontend: `pnpm build` (вкл. `vue-tsc`) зелёный — доказать, что публичный фронт не задет установкой Filament. DTO не меняются → `typescript:transform` не требуется.
- Новый код чист: 0 новых подавлений типов/линтера; сгенерированный Filament-код доводится до гейтов вручную (не подавляется).

## Безопасность
- **Доступы:** единственная новая поверхность — панель `/admin`. Гейт: `canAccessPanel()` = `is_admin && hasVerifiedEmail()` (least privilege — по умолчанию `is_admin=false` у всех). Негативные тесты обязательны (не-админ → 403).
- **Супер-доступ:** админ видит/правит все рецепты (осознанно, через `RecipePolicy::before`) — задокументировано как супер-доступ, а не обход изоляции; для обычных пользователей owner-scoping (FEAT-010) не ослаблен. Подтверждение владельца — Q5.
- **Данные:** `is_admin` вне `$fillable` (нет mass-assignment-эскалации прав через формы). UserResource не экспонирует `password`/`remember_token`/токены (тест изоляции). Мутации рецептов — через Tasks/Repository (валидация/транзакции сохранены), а не сырой `->save()`.
- **Изоляция Eloquent:** ослабляется точечно (чтение моделей в `App\Filament`, allow-list rule #1); правило `DB`-фасада (rule #2) сохранено как guard против сырых записей из Filament. Мутации бизнес-смысла — только через Tasks.
- **Секреты:** креды первого админа — из env/интерактивно, не хардкод; в логах — без паролей/токенов.
- **Гигиена §8:** сгенерированный код, комментарии, ветка `feat/filament-admin`, коммиты — без следов системы/ИИ/FEAT; финальное «ревью чистоты» свежим субагентом без доступа к `ai/`.

## Пользовательская документация (user-visible)
Появляется админ-панель `/admin` (user-visible для админов). По правилу публичной доки: проверить клиентские `README`/`CLAUDE.md` (клиентский `CLAUDE.md` удалён — правила в `ai/`), при необходимости добавить нейтральное упоминание админки (формулировку согласовать — Q7, напр. «Administration panel at `/admin` for administrator users»); в `impl.md` зафиксировать `updated …` / `needs product-owner review`. Без следов системы.

## Зависимые файлы для изменения
| Файл | Тип изменения |
|---|---|
| `composer.json` / `composer.lock` | +`filament/filament ^5.0` (пин версии) |
| `database/migrations/*_add_is_admin_to_users_table.php` | новая миграция (`is_admin` bool default false) |
| `app/Models/User.php` | +`implements FilamentUser`, +каст `is_admin→bool`, +`canAccessPanel()` |
| `app/Providers/Filament/AdminPanelProvider.php` | новый (генерируется `filament:install`, STRICT-ревиз) |
| `bootstrap/providers.php` | +регистрация `AdminPanelProvider` |
| `app/Filament/Resources/RecipeResource.php` (+ Pages) | новый ресурс (чтение через модель; мутации через Tasks) |
| `app/Filament/Resources/RecipeResource/RelationManagers/IngredientRelationManager.php` | новый RelationManager |
| `app/Filament/Resources/UserResource.php` (+ Pages) | новый read-only ресурс |
| `app/Policies/RecipePolicy.php` | +`before()` — супер-доступ админа |
| `database/seeders/AdminUserSeeder.php` **или** `app/Console/Commands/MakeAdminCommand.php` | бутстрап первого админа (способ — Q1) |
| `tests/Feature/ArchitectureTest.php` | allow-list rule #1 += `App\Filament` (red→green) |
| `tests/Feature/Admin/AdminPanelAccessTest.php` | новые тесты доступа (позитив+негатив) |
| `tests/Feature/Admin/RecipeResourceTest.php` | новые CRUD-тесты (Livewire-хелперы) |
| `tests/Feature/Admin/UserResourceTest.php` | новые тесты (read-only + изоляция полей) |
| `README.md` (клиентский) | +упоминание `/admin` (Q7) |
| `ai/adr/011-filament-admin-boundary.md` | новый decision-ADR (если утверждён Q2) |
| `ai/process-metrics/adr-006.jsonl` | **завести файл** + первая строка (см. ниже) |

## Что НЕ входит в эту фичу
- Загрузка изображений рецептов в админке / `whyme-agency/laravel-media` и дисковый бэкенд — следующий этап (Q6).
- BVI-панель, кастомные Filament-виджеты/дашборды сверх CRUD, кастомная Filament-тема (интеграция в общий Tailwind).
- Spatie Permission / система ролей сверх `is_admin`, мультиязычность/локализация панели.
- Управление учётками пользователей (сброс пароля, создание/удаление User) — UserResource read-only.
- Мутации рецептов «в обход» Tasks; изменение публичного Inertia-фронта.

## Метрик-леджер (M7, обязателен с этой инициативы)
Фича **заводит** `ai/process-metrics/adr-006.jsonl` (инициатива ADR-006) — до неё файла нет. При закрытии фичи — первая строка (append-only, схема process-retro §б; обязательные ключи `feat/adr/role/model`, числовые допускают `null`). В делегированном режиме `tokens` дописывает оркестратор (usage субагента виден ему); исполнитель отдаёт `role/model/red_green_loops/defect_catch_stage/canon_violations`. Полнота — `./scripts/ledger-check.sh --ledger ai/process-metrics/adr-006.jsonl FEAT-013` (warn-only). Пример строки:
```json
{"feat":"FEAT-013","adr":"ADR-006","role":"impl","model":"opus-4.8","tokens":null,"red_green_loops":null,"merge_conflicts":0,"defect_catch_stage":null,"canon_violations":0,"notes":"filament-admin; allow-list App\\Filament red→green; ADR-011"}
```

## Оценка сложности
**Высокая.** Ключевые риски:
1. **STRICT-ревиз сгенерированного** — Filament-классы из коробки не проходят L10/strict; довести до 0 ошибок без подавлений — основной объём (генерики форм/таблиц Filament v5, типы hooks).
2. **Граница C** — корректно завести мутации через Tasks (`handleRecordCreation/Update/Deletion`), не сломав транзакционную синхронизацию ингредиентов; не «протечь» в прямой `->save()`.
3. **Арх-барьер** — точное расширение allow-list (rule #1 += `App\Filament`) с доказанным red→green, сохранив rule #2 (`DB`).
4. **Ассеты** — не сломать публичный Vite/Tailwind-v3-фронт при установке Filament (раздельные пайплайны).
5. **Супер-доступ** — `RecipePolicy::before` не должен ослабить owner-scoping не-админа (сохранить негативные IDOR-тесты FEAT-010 зелёными).
6. **Livewire-тесты** Filament (новый для проекта класс тестов — Filament testing helpers на Pest).

---

## Итог тройной проверки (feature-workflow Шаг 5)

**Итерация 1 — Полнота:** ✓ Цель самодостаточна. AC покрывают установку/доступ/ресурсы/STRICT-ревиз/гейты/приёмку + backend-тесты + user-doc. Поле «Затрагиваемые репозитории» заполнено (один репо). Все затронутые файлы — в «Зависимые файлы». Scope-creep отсечён («Что НЕ входит»). Миграция описана (`is_admin`, default false, вне `$fillable`). Env-переменных новых нет (кроме опц. кред первого админа — из env, не значением). **Исправлено при проверке:** явно добавлено, что `is_admin` вне `$fillable` (иначе — эскалация прав через mass-assignment); добавлен пункт метрик-леджера.

**Итерация 2 — Логика/архитектура:** ✓ Нет противоречий дизайн↔AC. Инварианты ADR-003: изоляция Eloquent ослабляется **точечно и осознанно** (ADR-011, только чтение в `App\Filament`), `DB`-guard сохранён, мутации — через Tasks (канон «Filament без бизнес-логики»). Порядок снизу-вверх зафиксирован. Есть фаза red→green арх-барьера. Нет циклов зависимостей. **Проверено:** RelationManager под RecipeResource covered `App\Filament`-префиксом allow-list; `RecipePolicy::before` не ломает owner-scoping (возврат `null` для не-админа).

**Итерация 3 — Безопасность+гигиена:** ✓ Новый endpoint `/admin` — явный гейт `canAccessPanel` (least privilege, default `is_admin=false`), негативные тесты обязательны. Чувствительные поля User изолированы (тест). `is_admin` не mass-assignable. Секреты первого админа — из env. Супер-доступ админа задокументирован и вынесен владельцу (Q5). §8: код/комментарии/ветка/коммиты без следов системы; финальное «ревью чистоты». **Открытый риск, вынесен владельцу:** способ бутстрапа админа и подтверждение супер-доступа — блокеры СТОП-точки (Q1, Q5).

**Вердикт:** спека готова к СТОП-точке утверждения владельцем. Реализация — после явного «утверждено» по открытым вопросам (в первую очередь Q1 — кто админ, Q2 — подход C + ADR-011).
