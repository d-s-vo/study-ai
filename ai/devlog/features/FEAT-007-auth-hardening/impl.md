---
feat: FEAT-007
repos: [cbook]
tags: [backend, auth, security, validation, phpstan, throttle]
class: 'упрочнение Breeze-auth: rate-limit публичных POST, инлайн-валидация → FormRequest, снятие PHPStan-baseline по коду'
prevention: 'регрессионные throttle-тесты (429 после лимита) + PHPStan L10 без baseline как гейт снятия подавлений'
---

# FEAT-007: Упрочнение auth — throttle, FormRequest-валидация, снятие PHPStan-baseline — Implementation

## Статус: DONE (передано оркестратору/пользователю на доставку)
## Дата: 2026-07-31
## Коммит: `a1f6c53` (ветка `feat/auth-hardening` от `origin/develop @ e0c8ee3`)

## Step-0 — вердикт свежести базиса
База свежая: `HEAD == merge-base(HEAD, origin/develop) == e0c8ee3`. Расхождений нет, rebase не требуется.
Зависимости восстановлены в чистом worktree: `composer install` (через образ `laravelsail/php84-composer`),
`pnpm install`. Стартовый прогон (после `pnpm build`) — зелёный: Pest **33 passed**, PHPStan L10 **No errors**
(с baseline), Pint pass.

## Что сделано

### 1. Throttle на публичных auth-POST (`routes/auth.php`)
`->middleware('throttle:6,1')` навешен на три `guest`-POST: `register`, `forgot-password` (`password.email`),
`reset-password` (`password.store`). Единый профиль `6,1`, согласованный с verification-роутами
(`verification.verify` / `verification.send`). `login` **не** дублируется — он уже покрыт лимитером внутри
`LoginRequest` (5 попыток); двойной лимит не вводится.

### 2. Инлайн-валидация → FormRequest (5 мест; инвариант «вся серверная валидация во FormRequest»)
Правила перенесены 1:1, `authorize(): true`, контроллеры стали тоньше (сигнатура → FormRequest, `$request->validated()`
через штатный resolve; поведение и тексты ошибок не изменены). Именование — по существующей конвенции
(`LoginRequest` в `Auth/`, `ProfileUpdateRequest` в корне).

| Новый FormRequest | Контроллер | Правила |
|---|---|---|
| `app/Http/Requests/Auth/RegisterRequest.php` | `RegisteredUserController@store` | name / email(`unique`,`lowercase`) / password(`confirmed`,`Password::defaults()`) |
| `app/Http/Requests/Auth/NewPasswordRequest.php` | `NewPasswordController@store` | token / email / password(`confirmed`,`Password::defaults()`) |
| `app/Http/Requests/Auth/PasswordResetLinkRequest.php` | `PasswordResetLinkController@store` | email(`required|email`) |
| `app/Http/Requests/Auth/UpdatePasswordRequest.php` | `PasswordController@update` | current_password(`current_password`) / password(`Password::defaults()`,`confirmed`) |
| `app/Http/Requests/ProfileDeleteRequest.php` | `ProfileController@destroy` | password(`current_password`) |

STRICT сохранён: мутации `User` остаются в `UserRepository`/`RegisterUserTask`, контроллеры — только
FormRequest→делегирование. `use Illuminate\Validation\Rules`/лишние `Request`-импорты вычищены.

### 3. Снятие PHPStan-baseline (8 записей — все по коду, файл удалён)
- **7× nullable `$request->user()`** — сужение в стиле `ProfileController` (`$user = $request->user(); assert(...)`):
  `ConfirmablePasswordController` (`assert($user !== null)`), `EmailVerificationNotificationController`,
  `EmailVerificationPromptController`, `VerifyEmailController`.
  Для `new Verified($user)` — `assert($user instanceof MustVerifyEmail)` (конструктор события ждёт контракт
  `MustVerifyEmail`; `App\Models\User` не `final`, поэтому пересечение `User&MustVerifyEmail` для PHPStan
  допустимо и покрывает и `hasVerifiedEmail()`/`markEmailAsVerified()`, и аргумент события).
- **1× Stringable→string** (`LoginRequest::throttleKey()`) — `Str::lower((string) $this->string('email'))`.
- `phpstan-baseline.neon` удалён; строка `- phpstan-baseline.neon` убрана из `includes` в `phpstan.neon`.

> Рантайм-безопасность `assert(...)`: в Sail-контейнере `zend.assertions => -1` — `assert()` скомпилирован в no-op,
> служит **только** для сужения типов PHPStan (тот же приём, что уже в `ProfileController`/`UserRepository`
> из FEAT-004). Поэтому `assert($user instanceof MustVerifyEmail)` в дремлющем verification-flow (наш `User`
> не реализует контракт) рантайм не ломает — подтверждено живым прогоном `verify-email` через тесты.

### 4. Регрессионные тесты (`tests/Feature/Auth/AuthThrottleTest.php`)
Три кейса: register / forgot-password / reset-password — 6× запросов проходят (302), 7-й → **429**.
Изоляция RateLimiter между тестами обеспечена штатно: `TestCase` пересоздаёт приложение (и `array`-кэш-стор)
на каждый тест, поэтому счётчик лимитера чист на входе каждого теста; накопление — только внутри одного теста.
Существующие Breeze-тесты (`RegistrationTest`/`PasswordResetTest`/`PasswordUpdateTest`/`ProfileTest`,
негативные кейсы неверного `current_password` при смене/удалении) остались зелёными без правок — переход на
FormRequest не изменил ключи ошибок/redirect.

## Гейты (все зелёные)
- **Pest (полный, через `gate.sh backend-tests`):** **36 passed** (101 assertions) — было 33, +3 throttle-регрессии. 0 fail/skip.
- **PHPStan L10 БЕЗ baseline (`sail bin phpstan analyse`):** **No errors** (ключевой AC — 8 подавлений сняты по коду).
- **Pint (`sail bin pint --test`):** `passed`.
- **Frontend build (`gate.sh frontend-build` → `pnpm build`):** зелёный, `public/build/manifest.json` собран
  (фронт не трогался; сборка не регрессировала).

## Живая приёмка (изолированный стенд, снят после)
Стенд: `COMPOSE_PROJECT_NAME=cbook_authhardening`, `APP_PORT=8130`, `VITE_PORT=5203`, `FORWARD_DB_PORT=3130`
(этот compose держит только `laravel.test`+`mysql`; отдельного redis нет). Прогон curl с CSRF (XSRF-cookie →
`X-XSRF-TOKEN`):
- **Register** → 302 `/dashboard`, `GET /dashboard` (authed) → 200.
- **Logout** → 302 `/`, `GET /dashboard` (guest) → 302.
- **Login** → 302 `/dashboard`, dashboard → 200.
- **Сброс пароля по реальному письму** — Mailpit-сервиса в compose нет → `MAIL_MAILER=log`; ссылка сброса
  извлечена из `storage/logs/laravel.log` (снят quoted-printable перенос), токен 64 символа; `POST /reset-password`
  → 302 `/login`; логин с **новым** паролем → 302 `/dashboard` → 200. End-to-end сброс подтверждён.
- **Throttle (фактический 429):** после `cache:clear`, 7× `POST /forgot-password`: попытки **1–6 → 302, 7-я → 429**
  (ровно `throttle:6,1`).

## Отклонения / замечания для оркестратора
1. **pnpm `allowBuilds` (тот же паттерн, что в FEAT-004).** В свежем worktree под pnpm 11.18 `onlyBuiltDependencies`
   уже недостаточно: сборка esbuild гейтится новым полем `allowBuilds`; без него `pnpm build` падает на deps-status-check.
   Для зелёного билда локально выставлял `allowBuilds: { esbuild: true }`, **перед коммитом восстановил**
   `pnpm-workspace.yaml` к committed-версии (в коммит FEAT-007 фронт-конфиг НЕ входит). Это toolchain-долг фронт/
   infra-контура (есть worktree `tasks/infra-toolchain`) — кандидат туда/в FEAT-008; в скоуп FEAT-007 не тащу.
2. **Mailpit отсутствует в compose.yaml проекта** (только `laravel.test`+`mysql`) — живой сброс проверен через
   log-mailer + парсинг лога (эквивалент по сути: реальное отрендеренное письмо с рабочей ссылкой). Если целевой
   локальный стенд должен включать Mailpit/redis — это отдельный infra-вопрос.
3. **User-visible:** превышение лимита → 429 с сообщением о лимите. Незначительно для конечного пользователя;
   правки публичной доки не требуются (соответствует §Пользовательская документация spec).

## Файлы
Изменены: `routes/auth.php`, `phpstan.neon`, `app/Http/Requests/Auth/LoginRequest.php`,
`app/Http/Controllers/Auth/{RegisteredUser,NewPassword,PasswordResetLink,Password,ConfirmablePassword,
EmailVerificationNotification,EmailVerificationPrompt,VerifyEmail}Controller.php`,
`app/Http/Controllers/ProfileController.php`.
Добавлены: 5 FormRequest (см. таблицу), `tests/Feature/Auth/AuthThrottleTest.php`.
Удалён: `phpstan-baseline.neon`.
