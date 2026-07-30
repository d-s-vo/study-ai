# FEAT-004: Фронтенд-скелет (Breeze: Inertia + Vue 3 + TS) и enterprise-рефактор базовой авторизации

## Статус: SPEC

## Затрагиваемые репозитории

cbook (backend + frontend) — один репозиторий. Мультирепный рецепт §3.5 не применяется.

## Цель

Установить фронтенд-стек (Inertia.js + Vue 3 + TypeScript strict + Tailwind) и базовую аутентификацию
через Laravel Breeze, затем **отрефакторить сгенерированные Breeze контроллеры Auth** под строгую
слоистую архитектуру (STRICT RULE 2): любой доступ к БД по модели `User` — только из
`app/Data/Repositories/*`. Итог — рабочая регистрация/логин в браузере при зелёном arch-барьере,
PHPStan L10 и полном Pest.

## Контекст

База — `develop` @ `2038821` (FEAT-002 greenfield-скелет + FEAT-003 активация Pint): чистый Laravel 12 /
PHP 8.4 / MySQL 8 (Sail), каркас слоёв (`BaseTask::handle(): mixed`, `BaseRepository`, пустые
`app/Data`, `app/Resolvers/Page`), QA-тулчейн (pint.json psr12+strict, phpstan L10 на `app/`), Pest
arch-барьер `tests/Feature/ArchitectureTest.php` (Eloquent-модели `App\Models` → только в
`Repositories`/`Factories`/`Seeders`; фасад `DB` → только в `Repositories`). Фронт-фреймворка ещё нет.

Breeze — первый настоящий поставщик кода поверх скелета: он ставит связку Inertia+Vue+Vite+TS+Tailwind
и генерирует контроллеры Auth, которые **нарушают** наши барьеры (правят `User` через Eloquent вне
репозиториев). Это учебный кейс: показать, как слой `Repositories` защищается на практике.

Ссылки: north-star и 5 STRICT RULES — `memory.md`; изоляция Eloquent — ADR-003; стек — ADR-002;
переписывание с нуля — ADR-006. Инварианты и команды гейтов — `guides/stack-specifics.md`.

## Acceptance Criteria

- [ ] Breeze (vue + inertia + typescript) установлен; `sail pnpm run build` проходит без ошибок.
- [ ] `sail artisan migrate` создаёт таблицы (users, password_reset_tokens, sessions) на MySQL 8.
- [ ] Регистрация в браузере: `POST /register` c валидным payload → пользователь создан в БД, залогинен,
      редирект на `/dashboard`.
- [ ] Логин/логаут работают в браузере (`/login`, `/logout`).
- [ ] `tests/Feature/ArchitectureTest.php` **зелёный**: ни один Auth-контроллер / Task / Resolver не
      импортирует `App\Models\User` и не зовёт фасад `DB` вне `app/Data/Repositories/*`.
- [ ] Создание пользователя вынесено: `UserRepository::create()` (единственное место `User::create`)
      вызывается из `RegisterUserTask`, который зовётся из `RegisteredUserController@store`.
- [ ] **Любая** запись/чтение `User` в БД (регистрация, сброс пароля, смена пароля, апдейт профиля,
      удаление аккаунта) идёт через `UserRepository` — прямых `User::`/`$user->save()/update()/delete()`
      вне репозитория нет.
- [ ] `sail artisan test` (весь Pest) — зелёный, 0 fail, 0 непокрытых skipped.
- [ ] `sail bin pint --test` — чисто; в каждом новом `.php` стоит `declare(strict_types=1)`.
- [ ] `sail bin phpstan analyse` (L10) — без ошибок в наших файлах (`UserRepository`, `RegisterUserTask`,
      отрефакторенные контроллеры). Baseline — только для нетронутого framework-scaffolding Breeze (если
      вообще потребуется), не для нашей бизнес-логики.
- [ ] `pint.json` без точки (проверить/переименовать при регрессе); `tsconfig.json` — `"strict": true`.
- [ ] `resources/js/Pages/Dashboard.vue` — очищен от дефолта Breeze, показывает заголовок «Cookbook:
      Greenfield Enterprise» внутри `AuthenticatedLayout`.
- [ ] 0 следов ИИ/системы в коде, комментариях, коммите, ветке (§8).

## Технический дизайн

### Установка (Breeze)

1. `sail composer require laravel/breeze --dev`
2. `sail artisan breeze:install vue --typescript` (стек Vue, TypeScript, тест-раннер Pest; SSR не нужен).
3. `sail pnpm install && sail pnpm run build` (node-менеджер — **pnpm** через Sail-passthrough, не npm).
4. `sail artisan migrate`.

> Инструмент Node — **pnpm** (`sail pnpm ...`). Если в Sail-образе pnpm недоступен — включить corepack
> (`sail root-shell -c "corepack enable pnpm"`) до install. Лок-файл `pnpm-lock.yaml` коммитится,
> `package-lock.json` (если Breeze/npm его создаст) — удалить, чтобы не смешивать менеджеры.

### Backend-рефактор (слои: Controller → Task → Repository)

**`app/Data/Repositories/UserRepository.php`** (extends `BaseRepository`) — единственное место Eloquent
по `User`. Методы (сигнатуры — под PHPStan L10, внутри репозитория тип `User` разрешён):
- `create(string $name, string $email, string $plainPassword): User` — оборачивает `User::create([...])`
  с `Hash::make`. Возвращает модель (нужна вызывающему для `Auth::login`/`event(Registered)`).
- `updatePassword(User $user, string $plainPassword): void` — `forceFill(['password'=>Hash::make])`,
  `setRememberToken(Str::random(60))`, `save()` (для NewPasswordController — сброс по токену).
- `changePassword(User $user, string $plainPassword): void` — смена пароля залогиненного (PasswordController).
  (Можно объединить с `updatePassword`, если поведение идентично — решить при реализации; по умолчанию
  один метод `setPassword(User $user, string $plainPassword, bool $withRememberToken): void`.)
- `updateProfile(User $user, array $attributes): void` — `fill($attributes)`; при изменении email —
  сбросить `email_verified_at = null`; `save()` (ProfileController@update).
- `delete(User $user): void` — `$user->delete()` (ProfileController@destroy).

> **Граница контракта.** Контроллеры и Tasks **не импортируют** `App\Models\User`. Там, где нужен
> экземпляр текущего пользователя, берётся `Auth::user()` / `$request->user()` — статический тип
> `Illuminate\Contracts\Auth\Authenticatable`. Методы репозитория, принимающие `User`, вызываются с
> объектом от `$request->user()`; на границе — узкая приводка типа через **assert** helper (см. ниже),
> чтобы PHPStan L10 не ругался и без каста `as`.

**Хелпер приводки** — вместо `/** @var User */`-хаков ввести маленький типобезопасный мост, живущий
внутри слоя данных, например `UserRepository::fromAuthenticatable(Authenticatable $user): User` (внутри
репозитория `App\Models\User` разрешён; `assert($user instanceof User)` + возврат). Контроллер:
`$this->users->changePassword($this->users->fromAuthenticatable($request->user()), $plain)`. Так `User`
не «протекает» типом в контроллер: аргумент — `Authenticatable`, наружу метод возвращает `void`. Это
устраняет и arch-нарушение, и «undefined method on Authenticatable» PHPStan.

**`app/Tasks/RegisterUserTask.php`** (extends `BaseTask`):
- `handle(...): Authenticatable` — принимает провалидированные name/email/password (простыми скалярами
  или узким DTO — см. ниже), вызывает `UserRepository::create()`, возвращает `Authenticatable` (контракт,
  **не** `App\Models\User` — иначе Task импортирует модель и нарушит барьер). `BaseTask::handle(): mixed`
  ковариантно допускает уточнение `: Authenticatable`.

> DTO входа: по умолчанию Task принимает три скаляра (`string $name, string $email, string $plainPassword`)
> — без Spatie Data, т.к. это не «наружу в Inertia» контракт, а внутренний вход бизнес-операции. Плодить
> DTO ради трёх полей — over-engineering; DTO вводим доменным сущностям (Recipe) позже.

**Контроллеры Auth (тонкие, после рефактора):**
- `RegisteredUserController@store`: валидация (оставить как у Breeze — inline `$request->validate` или
  вынести во FormRequest, см. «решить при реализации»), затем
  `$user = $this->registerUserTask->handle($request->name, $request->email, $request->password);`
  `event(new Registered($user)); Auth::login($user);` → redirect `route('dashboard')`. Импорта `User` нет.
- `NewPasswordController@store`: `Password::reset` c замыканием `function (Authenticatable $user) use (...)
  { $this->users->setPassword($this->users->fromAuthenticatable($user), $request->password, true);
  event(new PasswordReset($user)); }`. Тип параметра замыкания — `Authenticatable`, не `User`.
- `PasswordController@update`: `$this->users->setPassword($this->users->fromAuthenticatable(
  $request->user()), $validated['password'], false);` вместо `$request->user()->update(...)`.
- `ProfileController@update`: `$this->users->updateProfile($this->users->fromAuthenticatable(
  $request->user()), $request->validated());` (сброс email_verified_at — внутри репозитория).
- `ProfileController@destroy`: `Auth::logout()` → `$this->users->delete($this->users->fromAuthenticatable(
  $request->user()))` → инвалидация сессии → redirect `/`.
- Остальные Auth-контроллеры (`AuthenticatedSessionController`, `ConfirmablePasswordController`,
  `EmailVerification*`, `PasswordResetLinkController`, `RegisteredUserController@create`) — Eloquent по
  `User` не трогают (работают через `Auth`/`Password` фасады, контракты) → **не рефакторить**, только
  прогнать через Pint (strict_types).

> DI: репозиторий и Task внедряются через конструктор контроллера (type-hint классов; Laravel резолвит
> автоматически, биндинг в провайдере не нужен — конкретные классы). `BaseRepository` пуст — оставить.

### Frontend

- `breeze:install vue --typescript` разворачивает `resources/js/{app.ts,Pages,Components,Layouts}`,
  `tsconfig.json`, `AuthenticatedLayout.vue`, страницы Auth и `Dashboard.vue`.
- `tsconfig.json`: убедиться `"strict": true` (Breeze ставит по умолчанию — подтвердить).
- `resources/js/Pages/Dashboard.vue`: заменить дефолт на каркас из ТЗ (Head «Cookbook» +
  AuthenticatedLayout + заголовок «Cookbook: Greenfield Enterprise» + строка про скелет). 0 `any`/`as`.
- Vue-страницы Auth — как генерирует Breeze (типизированы), правки не требуют.

## Тесты

**Добавить:**
- `tests/Feature/Auth/*` — Breeze генерирует набор (registration, authentication, password reset,
  password confirmation, email verification, password update, profile). Оставить и добиться зелёного
  прогона на MySQL 8 (RefreshDatabase, `.env.testing`).
- `tests/Feature/UserRepositoryTest.php` (**наш**) — позитив: `create()` пишет пользователя с хешированным
  паролем; `setPassword()` меняет хеш и remember_token; `updateProfile()` сбрасывает email_verified_at при
  смене email; `delete()` удаляет. (Unit/feature на репозиторий — доказать, что бизнес-мутации работают
  вне контроллера.)
- Регресс-якорь arch: `ArchitectureTest.php` уже покрывает изоляцию — убедиться, что он **red** на
  сыром Breeze (до рефактора) и **green** после (зафиксировать в impl.md как red→green).

**Обновить:** генерируемые Breeze тесты, если наши сигнатуры контроллеров изменили контракт (не должны —
маршруты/редиректы сохраняются). Если тест дёргал внутренности — привести к публичному поведению.

**Удалить:** ничего (кроме дефолтных `ExampleTest`, если Breeze их не трогает — оставить как есть).

> Права/чувствительные данные: аутентификация — чувствительный контур. Обязателен **негативный** тест:
> регистрация с невалидным/дублирующим email → 422/redirect-back с ошибками (Breeze покрывает —
> подтвердить, что проходит). Изоляция по владельцу для профиля (чужой аккаунт) — Breeze-профиль работает
> только над `$request->user()`, чужой доступ структурно невозможен; отметить в impl.

## Типизация/качество (минимальный набор гейтов)

- Гейты вручную (сериализовать тяжёлые через `gate.sh`): `sail artisan test` · `sail bin phpstan analyse`
  (L10) · `sail bin pint --test`. Фронт: `sail pnpm run build` (+ `vue-tsc` если Breeze подключит).
- Новый код чист: 0 новых подавлений типов/линтера в наших файлах. `phpstan-baseline.neon` — только для
  нетронутого framework-scaffolding Breeze, и минимально; каждая строка baseline объясняется в impl.md.
- TS-типы DTO доменных сущностей (`typescript:transform`) в этой фиче не нужны (User — не Spatie Data DTO
  наружу; данные о юзере отдаёт Inertia middleware Breeze как есть).

## Безопасность

- **Доступы:** новые маршруты — стандартные Breeze (`/register`,`/login`,`/logout`,`/dashboard`,
  `/profile`, сброс/смена пароля). `/dashboard` и `/profile` — под `auth`-middleware (Breeze ставит).
  Гость на `/dashboard` → редирект на `/login`. Проверить, что middleware не потеряны при рефакторе.
- **Данные:** пароли — только `Hash::make` (внутри репозитория), в БД не plaintext; `password`/
  `remember_token` — в `$hidden` модели (уже есть). Профиль/удаление — строго над `$request->user()`.
- **Валидация:** весь вход — через Breeze-валидацию/FormRequest **до** бизнес-логики (Task/Repository).
  Репозиторий не валидирует — получает уже чистые данные.
- **Секреты:** боевые креды не тащить; тесты — на `.env.testing` (test_*-значения), не на боевой `.env`.

## Пользовательская документация

User-visible: появляется регистрация/логин/дашборд. Клиентский `cbook/README.md` уже переписан под
целевой стек (Laravel) — проверить, нужна ли строка про доступную теперь авторизацию; при необходимости
добавить нейтрально (без следов системы). Клиентского `CLAUDE.md` в целевой репе нет как AI-артефакта —
не создавать.

## Зависимые файлы для изменения

| Файл | Тип |
|---|---|
| `composer.json` / `composer.lock` | + laravel/breeze (dev) |
| `package.json` / `pnpm-lock.yaml` | + inertia/vue/ts/tailwind toolchain (Breeze) |
| `app/Data/Repositories/UserRepository.php` | **новый** |
| `app/Tasks/RegisterUserTask.php` | **новый** |
| `app/Http/Controllers/Auth/RegisteredUserController.php` | рефактор store |
| `app/Http/Controllers/Auth/NewPasswordController.php` | рефактор store (замыкание reset) |
| `app/Http/Controllers/Auth/PasswordController.php` | рефактор update |
| `app/Http/Controllers/ProfileController.php` | рефактор update/destroy |
| `app/Http/Requests/*` | как генерирует Breeze (ProfileUpdateRequest и т.п.) |
| `resources/js/**` (app.ts, Pages, Layouts, Components, Dashboard.vue) | Breeze + правка Dashboard |
| `tsconfig.json`, `vite.config.js`, `resources/css/app.css` | Breeze |
| `routes/auth.php`, `routes/web.php` | Breeze (dashboard/profile маршруты) |
| `database/migrations/*` | Breeze (users, password_reset_tokens, sessions — если не было) |
| `tests/Feature/Auth/*`, `tests/Feature/UserRepositoryTest.php` | Breeze + наш репозиторий-тест |
| `phpstan-baseline.neon` | только при необходимости, минимально |

## Что НЕ входит

- Доменные сущности Recipe/Ingredient, их миграции/DTO/Resolvers — следующая задача (1b+).
- Filament 5 админка, media (`whyme-agency/laravel-media`).
- SSR Inertia, e2e-тесты фронта (Vitest), кастомный дизайн — только дефолтный Breeze-UI + правка Dashboard.
- Смена/добавление доменной логики User сверх того, что даёт Breeze.

## Оценка сложности

Средняя. Риски: (1) генерируемый Breeze код под PHPStan L10 может дать шум по нетронутым местам — держать
baseline минимальным, наши файлы — идеально типизированы; (2) pnpm в Sail-образе (corepack); (3)
порт-конфликты с останками старого Sail-проекта — гасить перед подъёмом; (4) arch-тест может ловить не
только 2 очевидных контроллера — эмпирически прогнать red→green и вычистить все всплывшие места.
