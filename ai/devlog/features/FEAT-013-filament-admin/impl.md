---
feat: FEAT-013
repos: [cbook]
tags: [backend, frontend, admin, filament, authz, security, tests, adr]
class: 'админ-панель Filament 5 /admin поверх строгой слоистой архитектуры: доступ по is_admin, ресурсы Recipe/User, мутации через Tasks, супер-доступ админа'
prevention: 'обязательные негативы доступа (не-админ/гость/неверифицированный → отказ), изоляция чувствительных полей User (нет password/токенов), is_admin вне $fillable, red→green расширения allow-list App\Filament при сохранении DB-guard'
---

# FEAT-013: Filament-админка `/admin` — Implementation

## Статус: 🚧 передано пользователю на доставку (до merge в develop)
## Дата: 2026-08-03

## Step-0
База develop — `8db26fa` (docs README-раздел «Рецепты») поверх `6116cff` (FEAT-011). Worktree свежий,
вердикт **FRESH**. Окружение поднято (Sail: app :8110, Vite :5183, MySQL :3110, redis_db 5); тестовая
БД `testing`/`test_user` заведена, `.env.testing` APP_KEY проставлен; baseline зелёный
(Pest 82, PHPStan L10 0 err, Pint pass, `pnpm build` ok).

## Версия Filament
**filament/filament `v5.7.5`** (пин в `composer.json` `^5.0`, lock `v5.7.5`; PHP `^8.2`, нативно под
Laravel 12). Расхождений с ADR-002 («Filament 5») нет.

## Что сделано

| Файл | Изменение |
|---|---|
| `composer.json`/`composer.lock` | +`filament/filament ^5.0` (v5.7.5) и транзитивные (filament/*, livewire) |
| `app/Providers/Filament/AdminPanelProvider.php` | новый (генератор `filament:install --panels`), STRICT-ревиз: `declare(strict_types=1)`; панель `admin`, path `/admin`, `->login()` |
| `bootstrap/providers.php` | +регистрация `AdminPanelProvider` |
| `.gitignore` | +`/public/css/filament`, `/public/js/filament`, `/public/fonts/filament` (vendor-ассеты Filament; регенерируются `filament:upgrade` в `post-autoload-dump`) |
| `eslint.config.js` | +ignore `public/js/filament` (vendor-JS Filament — не исходники проекта) |
| `database/migrations/2026_08_03_000001_add_is_admin_to_users_table.php` | новая миграция `users.is_admin` (bool, default false) |
| `app/Models/User.php` | `implements FilamentUser`; каст `is_admin→boolean`; `canAccessPanel()` = `is_admin && hasVerifiedEmail()`; `is_admin` **вне** `$fillable` |
| `app/Policies/RecipePolicy.php` | +`before(User): ?bool` — админ `true` (супер-доступ), иначе `null` (owner-scoping не ослаблен) |
| `database/factories/UserFactory.php` | +state `admin()` |
| `app/Console/Commands/GrantAdminCommand.php` | новая команда `app:grant-admin {email}` → `UserRepository::grantAdminByEmail` |
| `app/Data/Repositories/UserRepository.php` | +`grantAdminByEmail` (forceFill, is_admin не fillable); +`selectOptions` (выбор автора) |
| `app/Data/Repositories/RecipeRepository.php` | +`ingredientsAsFormData` (гидрация ингредиентов в форму панели) |
| `app/Filament/Resources/Recipes/*` | RecipeResource + Pages (Create/Edit/List) + Schemas/RecipeForm + Tables/RecipesTable; чтение через модель, мутации через Tasks |
| `app/Filament/Resources/Users/*` | UserResource (read-only) + Pages (List/View) + Tables/UsersTable + Schemas/UserInfolist |
| `tests/Feature/ArchitectureTest.php` | allow-list rule #1 += `App\Filament` (red→green); rule #2 (`DB`) не тронуто |
| `tests/Feature/Admin/*` | AdminPanelAccessTest, RecipeResourceTest, UserResourceTest (новые) |
| `tests/Feature/Recipe/RecipeCrudTest.php` | +позитив «админ правит/удаляет чужой рецепт» (супер-доступ) |
| `README.md` | +раздел «Панель администратора» |

## Решения владельца (СТОП-точка — все 7 «как рекомендовано»)
Реализованы: (1) bool `is_admin`, миграция + команда `app:grant-admin`; (2) подход **C** + decision-ADR-011;
(3) Filament v5; (4) Recipe CRUD + User read-only; (5) `canAccessPanel = is_admin && verified`, супер-доступ
через `RecipePolicy::before`; (6) медиа вне scope; (7) нейтральная формулировка README.

## Граница ADR-011 (подход C) — как реализована
- **Чтение** моделей в `App\Filament` разрешено (allow-list rule #1 += `App\Filament`, red→green доказан).
- **Мутации** домена — только через существующие Tasks:
  - `CreateRecipe::handleRecordCreation` → `CreateRecipeTask` (рецепт + ингредиенты одной транзакцией);
  - `EditRecipe::handleRecordUpdate` → `UpdateRecipeTask` (транзакционная синхронизация ингредиентов);
  - удаление (header-action + bulk-action) → `DeleteRecipeTask` (каскад ингредиентов по FK).
- **`DB`-фасад** (rule #2) в барьере НЕ расширялся — остаётся guard против сырых записей из Filament.
- **Супер-доступ** админа — `RecipePolicy::before` (`true` для админа, `null` иначе). Owner-scoping FEAT-010
  не ослаблен (негативные IDOR-тесты зелёные).

### PoC red→green арх-барьера
Без строки `'App\Filament'` в allow-list rule #1 — `ArchitectureTest` краснеет:
`Expecting 'App\Models\Recipe' not to be used on 'App\Filament\Resources\Recipes\RecipeResource'`
(`RecipeResource.php:10 use App\Models\Recipe`). Со строкой — зелёный (2 passed). Правило #2 (`DB`)
неизменно.

## Отклонение от spec (обосновано)
**Ингредиенты — form Repeater, а не отдельный `IngredientRelationManager`.** Спека называла RelationManager,
но реализован Repeater в форме рецепта. Причины: (а) RelationManager недоступен на create-экране, а
AC требует «create через форму → рецепт + N ингредиентов через Task» атомарно; (б) `UpdateRecipeTask`
делает полную delete+recreate-синхронизацию ингредиентов (совпадает с сабмитом всего списка формой,
но конфликтовал бы с независимым RelationManager, затирая его правки); (в) сама спека трактует Ingredient
как композиционную часть агрегата Recipe «без самостоятельного ЖЦ вне рецепта» — Repeater в форме
рецепта архитектурно консистентнее независимого CRUD RelationManager. Все AC про Tasks/транзакции/каскад
выполнены и покрыты тестами (create+edit+delete через панель). Файл
`IngredientRelationManager.php` из «зависимых файлов» не создаётся — заменён Repeater'ом.

## STRICT-ревиз сгенерированного
Каждый сгенерированный `.php` доведён вручную: `declare(strict_types=1)` первой строкой; Pint psr12+strict;
PHPStan **L10, 0 ошибок, 0 подавлений/baseline** (включая `app/Filament`). Ключевые правки под L10:
- id берутся из типизированной модели (`assert($record instanceof Recipe); $record->id` — int по Larastan),
  а НЕ кастом `(int) getKey()` (каст mixed→int запрещён как подавление — как в FEAT-010);
- `UserRepository::selectOptions` — `get(['id','name'])->mapWithKeys(...)` вместо `pluck` (иначе
  `array<mixed>` не сходится с `array<int,string>`); без inline-`@var`-оверрайда (Larastan это запрещает);
- `UserResource::getEloquentQuery(): Builder<User>` через локальный `@var` только на `parent::` (тип-хинт,
  не подавление).

## Гейты
- **Pest: 95 passed** (410 assertions), 0 fail (было 82 на baseline; +13: 4 access, 4 recipe-resource,
  3 user-resource, 2 recipe-crud супер-доступ).
- **PHPStan L10: No errors** (0 подавлений, 0 baseline; `app/Filament` в `paths`).
- **Pint --test: passed** (psr12+strict).
- Фронт: **`pnpm build` зелёный**, **`pnpm lint` зелёный** (после исключения vendor-JS Filament из ESLint),
  **`vue-tsc --noEmit` зелёный**. Публичный Inertia-фронт (Tailwind v3) не затронут — Filament на своём
  ассет-пайплайне. DTO не менялись — `typescript:transform` не требовался.

## Сводка для приёмки
- Окружение: поднято (Sail :8110, эфемерная БД задачи), health зелёный (`/` = 200).
- Сценарий (curl, структурный exit-код 0): гость `/admin` → **302 /admin/login** ✓ · `/admin/login` = 200 ✓ ·
  админ (verified) вход через Breeze `/login` (Inertia, XSRF-заголовок) → `/admin` = **200** ✓ ·
  `/admin/recipes` = 200 и виден рецепт ДРУГОГО владельца (супер-доступ) ✓ · `/admin/users` = 200,
  хеш пароля в выдаче **отсутствует** ✓ · рецепт для приёмки создан реальным `CreateRecipeTask`
  (2 ингредиента синхронизированы) — путь мутаций через Task подтверждён на живой БД.
- Адверсариально: не-админ (verified) `/admin` → **403** ✓ · чужие чувствительные поля не видны ✓ ·
  публичный фронт цел (`/recipes` под auth → 302, как и раньше).
- Дефекты в ходе приёмки: нет. Тестовые данные приёмки из dev-БД удалены.
- Слои проверки: unit/integration (Pest + Filament Livewire-хелперы) + живой curl-прогон.

## Артефакты `ai/`
- `ai/adr/011-filament-admin-boundary.md` (Принят → Реализован).
- `ai/devlog/features/FEAT-013-filament-admin/{spec,impl}.md`.
- `ai/devlog/commits/cbook/<hash>-*.md` — по-коммитные разборы (ADR-009), 6 файлов.
- `ai/process-metrics/adr-006.jsonl` — заведён, первая строка.
- Реестры: `ai/memory.md`, `ai/architecture.md` §10, `ai/devlog/features/README.md`.

## Клиентские коммиты (ветка `feat/filament-admin`)
| Хеш | Сообщение |
|---|---|
| `4491034` | chore: установка админ-панели Filament |
| `b0a56ff` | feat: доступ администратора к панели и супер-доступ к рецептам |
| `e847f28` | feat: управление рецептами через админ-панель |
| `7965bbd` | feat: раздел пользователей в админ-панели (только чтение) |
| `1869e8f` | test: проверки доступа и ресурсов админ-панели |
| `41267e7` | docs: описание админ-панели в README |

## НЕ сделано (зона оркестратора/пользователя)
Независимое коммит-ревью ADR-010 и финальное «ревью чистоты» свежими субагентами; push/deliver (MR в
develop — пользователь); уборка worktree/брони/стенда — после доставки.

## Итог
Админ-панель `/admin` работает поверх строгой слоистой архитектуры без нарушения её инвариантов:
Eloquent-чтение точечно легализовано в `App\Filament` (ADR-011), мутации домена — через Tasks/Repository
(транзакции сохранены), `DB`-guard цел. Доступ — least privilege (`is_admin && verified`, default false),
негативы обязательны; чувствительные поля User изолированы; `is_admin` не mass-assignable; супер-доступ
админа осознанный. Все гейты зелёные, живая приёмка пройдена.
