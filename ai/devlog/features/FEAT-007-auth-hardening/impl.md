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
## Коммиты (цепочка): `a1f6c53` (фича) + `f4a9d63` (`feat: включить обязательное подтверждение email при регистрации` — закрытие блокера ревью по spec-дельте владельца) + `6605919` (`docs: отметить обязательное подтверждение email в инструкции запуска` — README, по согласованию)
## Ветка: `feat/auth-hardening` от `origin/develop @ e0c8ee3`

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
- **nullable `$request->user()`** — сужение в стиле `ProfileController` (`$user = $request->user();
  assert($user !== null)`): `ConfirmablePasswordController`, `EmailVerificationNotificationController`,
  `EmailVerificationPromptController`. Все три — под `auth`-middleware, предикат всегда-истинный.
- **`VerifyEmailController`** — итоговое решение (после фикса `f4a9d63`): контроллер сведён к штатному
  `$request->fulfill()` (`EmailVerificationRequest::fulfill()` — тот же канон, что в Fortify) + redirect.
  Обращения к `$request->user()` и каких-либо assert/сужений в контроллере нет вовсе.
  ⚠ История блокера: в `a1f6c53` здесь стоял `assert($user instanceof MustVerifyEmail)` — предикат был
  **ложен в рантайме** (модель подключала только одноимённый трейт, не контракт); при `zend.assertions=1`
  (дефолт php.ini-development) это дало бы AssertionError→500. Sail с `zend.assertions=-1` маскировал.
  Урок: assert-сужение допустимо только со всегда-истинным предикатом.
- **1× Stringable→string** (`LoginRequest::throttleKey()`) — `Str::lower((string) $this->string('email'))`.
- `phpstan-baseline.neon` удалён; строка `- phpstan-baseline.neon` убрана из `includes` в `phpstan.neon`.

> Все оставшиеся в цепочке assert-сужения — всегда-истинные (`!== null` под `auth`; `instanceof User` в
> `UserRepository` из FEAT-004). **Доказательство:** полный Pest-прогон с принудительным
> `php -d zend.assertions=1 -d assert.exception=1` — 39 passed, ни одного AssertionError.

### 3b. Email-верификация (spec-дельта владельца, коммит `f4a9d63`)
Владелец решил не консервировать дремлющий флоу, а включить верификацию по-настоящему (см. spec.md §Дельта):
- `app/Models/User.php` — `implements Illuminate\Contracts\Auth\MustVerifyEmail` (методы уже были через трейт
  базового класса); убран Breeze-комментарий-подсказка.
- Последствия включения (проверены): `Registered` → фреймворковый листенер `SendEmailVerificationNotification`
  (регистрируется автоматически, `Foundation\Support\Providers\EventServiceProvider:226`) шлёт письмо;
  middleware `verified` на dashboard становится боевым — неверифицированный редиректится на
  `verification.notice`.
- Слои не тронуты: `RegisterUserTask`/`UserRepository` без изменений (мутаций модели дельта не требует).
- Новые тесты: `RegistrationTest` — «a verification email is sent on registration» (`Notification::fake` +
  `VerifyEmail`, юзер после регистрации не верифицирован); `EmailVerificationTest` — «unverified users are
  redirected to the verification notice» и «verified users can access the dashboard». Существовавшие
  `EmailVerificationTest`-кейсы не были вакуумными по механике verify-роута (трейт-методы работали и до
  контракта), но middleware `verified` до дельты был инертен — теперь покрыт явными тестами.

### 4. Регрессионные тесты (`tests/Feature/Auth/AuthThrottleTest.php`)
Три кейса: register / forgot-password / reset-password — 6× запросов проходят (302), 7-й → **429**.
Изоляция RateLimiter между тестами обеспечена штатно: `TestCase` пересоздаёт приложение (и `array`-кэш-стор)
на каждый тест, поэтому счётчик лимитера чист на входе каждого теста; накопление — только внутри одного теста.
Существующие Breeze-тесты (`RegistrationTest`/`PasswordResetTest`/`PasswordUpdateTest`/`ProfileTest`,
негативные кейсы неверного `current_password` при смене/удалении) остались зелёными без правок — переход на
FormRequest не изменил ключи ошибок/redirect.

## Гейты (все зелёные; итог цепочки a1f6c53+f4a9d63)
- **Pest (полный, через `gate.sh backend-tests`):** **39 passed** (106 assertions) — было 33, +3 throttle,
  +3 верификация. 0 fail/skip. Прогон выполнен с `php -d zend.assertions=1 -d assert.exception=1` —
  одновременно доказательство всегда-истинности всех assert-предикатов.
- **PHPStan L10 БЕЗ baseline (`sail bin phpstan analyse`):** **No errors** (ключевой AC — 8 подавлений сняты
  по коду; после фикса — без единого assert-обмана).
- **Pint (`sail bin pint --test`):** `passed`. Арх-барьер (изоляция Eloquent) — в составе Pest, зелёный.
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

**Вторая живая приёмка (после `f4a9d63`, верификация; тот же изолированный стенд, снят после):**
- register → 302 `/dashboard` → middleware `verified` → 302 `/verify-email`; notice-страница → 200;
- письмо верификации реально уходит (log-mailer): signed-ссылка `verify-email/{id}/{hash}` извлечена из лога,
  GET по ней → 302 → `/dashboard` → **200** (верифицирован); повторный `/verify-email` → 302 на dashboard;
- второй (неверифицированный) пользователь: login → 302, `/dashboard` → 302 `/verify-email` (блок работает);
- throttle-регресс: 7× `POST /forgot-password` → попытки 1–6 302, **7-я 429** (не сломан).

## Отклонения / замечания для оркестратора
1. **pnpm `allowBuilds` (тот же паттерн, что в FEAT-004).** В свежем worktree под pnpm 11.18 `onlyBuiltDependencies`
   уже недостаточно: сборка esbuild гейтится новым полем `allowBuilds`; без него `pnpm build` падает на deps-status-check.
   Для зелёного билда локально выставлял `allowBuilds: { esbuild: true }`, **перед коммитом восстановил**
   `pnpm-workspace.yaml` к committed-версии (в коммит FEAT-007 фронт-конфиг НЕ входит). Это toolchain-долг фронт/
   infra-контура (есть worktree `tasks/infra-toolchain`) — кандидат туда/в FEAT-008; в скоуп FEAT-007 не тащу.
2. **Mailpit отсутствует в compose.yaml проекта** (только `laravel.test`+`mysql`) — живой сброс проверен через
   log-mailer + парсинг лога (эквивалент по сути: реальное отрендеренное письмо с рабочей ссылкой). Если целевой
   локальный стенд должен включать Mailpit/redis — это отдельный infra-вопрос.
3. **User-visible (обновлено дельтой):** (а) превышение лимита → 429; (б) **регистрация теперь требует
   подтверждения email** — после register пользователь попадает на notice-страницу, dashboard доступен после
   клика по ссылке из письма. По согласованию отражено в README клиента (docs-коммит `6605919`, строка в
   секции локального запуска рядом с упоминанием Mailpit).
4. **Блокер ревью a1f6c53 закрыт по существу** (`f4a9d63`): ложное сужение `instanceof MustVerifyEmail`
   устранено не заплаткой, а внедрением верификации (решение владельца) + переводом контроллера на штатный
   `fulfill()`. Ложных в рантайме assert-ов в цепочке не осталось — доказано полным Pest-прогоном под
   `zend.assertions=1`.

## Файлы
Коммит `a1f6c53`: изменены `routes/auth.php`, `phpstan.neon`, `app/Http/Requests/Auth/LoginRequest.php`,
`app/Http/Controllers/Auth/{RegisteredUser,NewPassword,PasswordResetLink,Password,ConfirmablePassword,
EmailVerificationNotification,EmailVerificationPrompt,VerifyEmail}Controller.php`,
`app/Http/Controllers/ProfileController.php`; добавлены 5 FormRequest (см. таблицу),
`tests/Feature/Auth/AuthThrottleTest.php`; удалён `phpstan-baseline.neon`.
Коммит `f4a9d63`: изменены `app/Models/User.php` (implements `MustVerifyEmail`),
`app/Http/Controllers/Auth/VerifyEmailController.php` (→ `fulfill()`),
`tests/Feature/Auth/RegistrationTest.php` (+1 тест), `tests/Feature/Auth/EmailVerificationTest.php` (+2 теста).
Коммит `6605919`: `README.md` (+3 строки — user-visible заметка о подтверждении email, Mailpit).
