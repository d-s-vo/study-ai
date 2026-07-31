# FEAT-007: Упрочнение auth — throttle, FormRequest-валидация, снятие PHPStan-baseline

## Статус: SPEC

## Затрагиваемые репозитории
cbook (backend) — один репозиторий. Мультирепный рецепт §3.5 не применяется.

## Цель
Закрыть три класса долга в Breeze-авторизации: (1) отсутствие rate-limit на публичных auth-POST (register/forgot/reset); (2) инлайн `$request->validate()` вместо FormRequest в 5 контроллерах (нарушение инварианта «вся серверная валидация — FormRequest»); (3) PHPStan-baseline (8 записей) — погасить точечными фиксами и удалить baseline-файл из `phpstan.neon`.

## Контекст
База — `origin/develop @ e0c8ee3`, поверх FEAT-005 (гейты/CI) и FEAT-006 (DTO). Текущее состояние:
- `routes/auth.php`: `POST register` (20), `POST forgot-password` (30), `POST reset-password` (36) — **без throttle**. `login` защищён внутри `LoginRequest` (RateLimiter, 5 попыток); `verification.verify`/`verification.send` — `throttle:6,1`.
- Инлайн-валидация `$request->validate([...])` в: `RegisteredUserController@store:39`, `NewPasswordController@store:43`, `PasswordResetLinkController@store:34`, `PasswordController@update:24`, `ProfileController@destroy:52`. Инвариант ТЗ (`stack-specifics.md` §Backend) — вся серверная валидация во FormRequest.
- `phpstan-baseline.neon` — 8 записей (по факту; в брифе упоминалось ~9 — уточнить при импле): 7× «method/property on `App\Models\User|null`» в email-verification-контроллерах (`ConfirmablePasswordController`, `EmailVerificationNotificationController`, `EmailVerificationPromptController`, `VerifyEmailController`) + аргумент `Verified` конструктора; 1× `Str::lower()` ждёт `string`, получил `Illuminate\Support\Stringable` в `LoginRequest:86` (`throttleKey()`). `phpstan.neon` подключает baseline через `includes`.
- FEAT-004 ревью пометило baseline как «только нетронутый Breeze-scaffold»; теперь чистим scaffold до нуля подавлений.

Инварианты: `ai/memory.md` North Star (STRICT), `stack-specifics.md` §Backend/§Тесты.

## Acceptance Criteria
- [ ] `POST register`, `POST forgot-password`, `POST reset-password` имеют throttle-middleware (напр. `throttle:6,1` — согласовать лимит с verification); после N попыток → HTTP **429**.
- [ ] Валидация вынесена во FormRequest в 5 местах:
  - [ ] `RegisteredUserController@store` → `RegisterRequest` (name/email/password правила).
  - [ ] `NewPasswordController@store` → `NewPasswordRequest` (token/email/password).
  - [ ] `PasswordResetLinkController@store` → `PasswordResetLinkRequest` (email).
  - [ ] `PasswordController@update` → `UpdatePasswordRequest` (current_password/password).
  - [ ] `ProfileController@destroy` → `ProfileDeleteRequest` (password/current_password).
  Контроллеры — тонкие: принимают FormRequest, `->validated()`, делегируют; инлайн `$request->validate()` в этих методах отсутствует.
- [ ] `phpstan-baseline.neon` удалён; `includes` в `phpstan.neon` его не подключает; `sail bin phpstan analyse` (L10) → **No errors** без baseline.
- [ ] Нарушения из baseline погашены **по коду**: nullable `$request->user()` сужен (assert/guard, как в `ProfileController`); `LoginRequest::throttleKey()` — `Str::lower((string) $this->string('email'))` (или `->value()`), тип `string`.
- [ ] Все существующие Breeze-тесты (`tests/Feature/Auth/*`, `ProfileTest`) — зелёные; добавлены регрессионные throttle-тесты (429 после лимита).
- [ ] Pint pass; Pest 0 fail; арх-барьер (изоляция Eloquent) — зелёный.

## Технический дизайн

### Throttle (routes/auth.php)
- Навесить `->middleware('throttle:6,1')` (или именованный лимитер) на три `guest`-POST. Значение лимита: согласовать с verification (`6,1`) — единый профиль; при желании отдельный лимитер `RateLimiter::for('auth', ...)` в `AppServiceProvider`/bootstrap (решение импла — не усложнять без нужды, дефолт `throttle:6,1`).
- `login` **не** дублировать throttle (уже покрыт `LoginRequest`); избегать двойного лимита.

### FormRequest (5 новых, `app/Http/Requests/Auth/` и `app/Http/Requests/`)
- Перенести массивы правил из контроллеров 1:1 в `rules()`; `authorize(): true` (маршруты уже под нужными мидлварами `guest`/`auth`).
- `RegisterRequest`: `name`, `email` (`unique:users,email`, `lowercase`), `password` (`confirmed`, `Rules\Password::defaults()`).
- `NewPasswordRequest`: `token` (`required`), `email` (`required|email`), `password` (`confirmed`, `Password::defaults()`).
- `PasswordResetLinkRequest`: `email` (`required|email`).
- `UpdatePasswordRequest`: `current_password` (`required|current_password`), `password` (`required|Password::defaults()|confirmed`).
- `ProfileDeleteRequest`: `password` (`required|current_password`).
- Контроллеры: заменить `Request $request` → соответствующий FormRequest, использовать `$request->validated()`; сохранить существующую бизнес-логику (вызовы `RegisterUserTask`/`UserRepository`/`Password::reset` неизменны). Именование FormRequest — согласовать с уже существующими `LoginRequest`/`ProfileUpdateRequest`.

> STRICT: любые мутации `User` остаются в `UserRepository`/`RegisterUserTask` (не регрессировать enterprise-рефактор FEAT-004). Контроллеры — только валидация(FormRequest)→делегирование.

### Снятие baseline
- **nullable user** (7 записей): в затронутых email-verification-контроллерах сузить `$request->user()` — `$user = $request->user(); assert($user !== null);` (маршруты под `auth`, user гарантирован) перед вызовом `hasVerifiedEmail()`/`markEmailAsVerified()`/`sendEmailVerificationNotification()`; для `new Verified($user)` — тот же assert/сужение до `MustVerifyEmail`.
- **Stringable→string** (`LoginRequest:86`): `Str::lower((string) $this->string('email'))` либо `$this->string('email')->value()`.
- Удалить `phpstan-baseline.neon`; из `phpstan.neon` убрать строку `- phpstan-baseline.neon` в `includes`.
- Если при импле всплывёт «+1 прочее» (брифовые 9 vs фактические 8) — погасить по коду тем же принципом (сужение/каст), не возвращать baseline.

## Тесты
**Добавить:** `tests/Feature/Auth/*` — регрессия throttle:
- register: N+1 POST с невалидными/повторными данными → 429 (проверить заголовок/статус).
- forgot-password / reset-password: превышение лимита → 429.
**Обновить:** существующие `RegistrationTest`/`PasswordResetTest`/`PasswordUpdateTest`/`ProfileTest` — убедиться, что переход на FormRequest не сломал assertion-ы (ошибки валидации по тем же ключам). При необходимости — поправить ожидания под FormRequest (сообщения/redirect).
**Удалить:** нет.

> Auth/чувствительные данные — обязателен негативный кейс: неверный `current_password` при смене/удалении → ошибка валидации (не 500); чужие/битые токены сброса → отказ.

## Типизация/качество
- Гейты: `sail bin phpstan analyse` — **L10 No errors без baseline** (ключевой AC фичи); `sail bin pint --test`; `sail artisan test` (0 fail); арх-барьер зелёный.
- 0 новых подавлений типов/линтера. Касание Breeze-scaffold сопровождается сохранением/добавлением характеризующих тестов (существующие Breeze-тесты фиксируют поведение до правки).

## Безопасность
- **Доступы:** throttle закрывает brute-force/спам на публичных auth-POST (register/forgot/reset) — прямое усиление least-privilege поверхности.
- **Данные:** FormRequest централизует валидацию до бизнес-логики; правила (unique/lowercase/current_password) не ослабляются. Пароли — через `UserRepository` (Hash), в логи не пишутся.
- **Валидация:** после фичи вся серверная валидация auth — во FormRequest (инвариант соблюдён).
- **Гигиена §8:** FormRequest/тесты — человеческий стиль, без следов системы.

## Пользовательская документация
User-visible изменение поведения: превышение попыток → 429 с сообщением о лимите. Незначительно для конечного пользователя; правки публичной доки не требуются (отметить в `impl.md`). Внутренний контракт валидации не меняет UX успешных сценариев.

## Зависимые файлы для изменения
| Файл | Тип изменения |
|---|---|
| `routes/auth.php` | throttle на register/forgot/reset POST |
| `app/Http/Requests/Auth/RegisterRequest.php` | новый FormRequest |
| `app/Http/Requests/Auth/NewPasswordRequest.php` | новый FormRequest |
| `app/Http/Requests/Auth/PasswordResetLinkRequest.php` | новый FormRequest |
| `app/Http/Requests/Auth/UpdatePasswordRequest.php` | новый FormRequest |
| `app/Http/Requests/ProfileDeleteRequest.php` | новый FormRequest |
| `app/Http/Controllers/Auth/RegisteredUserController.php` | инлайн-валидация → FormRequest |
| `app/Http/Controllers/Auth/NewPasswordController.php` | инлайн-валидация → FormRequest |
| `app/Http/Controllers/Auth/PasswordResetLinkController.php` | инлайн-валидация → FormRequest |
| `app/Http/Controllers/Auth/PasswordController.php` | инлайн-валидация → FormRequest |
| `app/Http/Controllers/ProfileController.php` | `destroy` инлайн → FormRequest |
| `app/Http/Controllers/Auth/*Verification* / VerifyEmail / ConfirmablePassword` | сужение `$request->user()` (снятие baseline) |
| `app/Http/Requests/Auth/LoginRequest.php` | `throttleKey()` — `(string)`-каст |
| `phpstan.neon` | убрать `- phpstan-baseline.neon` из includes |
| `phpstan-baseline.neon` | удалить файл |
| `tests/Feature/Auth/*` | throttle-регрессия + сверка FormRequest |

## Зависимости/границы (сверка с 005/006/008)
- **Порядок:** реализуется **после FEAT-006**, до FEAT-008. Единственный владелец правок auth-контроллеров/requests/baseline.
- **`HandleInertiaRequests.php`:** FEAT-007 **не трогает** (это зона FEAT-006). Разграничение чёткое: 006 = middleware + фронт-типы; 007 = контроллеры/requests/baseline.
- **`phpstan-baseline.neon` / `phpstan.neon`:** удаляет только FEAT-007. FEAT-005/006 baseline не трогали и оставляли гейты зелёными с baseline; после 007 baseline исчезает и L10 чист без него.
- **`ProfileController.php`:** трогает FEAT-007 (метод `destroy` → FormRequest). FEAT-006 этот файл не касается (профильный DTO — вне скоупа обеих; 006 работает только с `auth.user`-пропом). Конфликта нет.
- **Оставляет систему зелёной:** после 007 — phpstan L10 без baseline, pint, pest (вкл. новые throttle-тесты) зелёные.

## Что НЕ входит
- Инфраструктура/CI/pnpm (FEAT-005).
- UserData DTO / автоген типов (FEAT-006).
- Фронт-гигиена, ESLint/tsconfig, чистка скаффолда, Tailwind (FEAT-008).
- Новые auth-фичи (2FA, соц-логин), политики Filament — вне скоупа.

## Дельта: email-верификация (решение владельца 2026-07-31)

Принято при закрытии блокера ревью `a1f6c53` (ложное в рантайме сужение `assert($user instanceof MustVerifyEmail)`
в `VerifyEmailController` — `App\Models\User` подключал лишь одноимённый трейт, но не контракт). Владелец решил
не консервировать дремлющий флоу, а **внедрить верификацию email по-настоящему**:

- `App\Models\User implements Illuminate\Contracts\Auth\MustVerifyEmail` (методы уже есть через трейт базового
  `Foundation\Auth\User`).
- `VerifyEmailController` — через штатный `EmailVerificationRequest::fulfill()` (канон Fortify): без обращения
  к `$request->user()` в контроллере, без сужений/assert вовсе.
- Осознанные последствия включения (ожидаемое новое поведение):
  - `Registered` → фреймворковый листенер `SendEmailVerificationNotification` шлёт письмо верификации;
  - middleware `verified` (dashboard) начинает работать: неверифицированный → redirect на `verification.notice`;
    после подтверждения по ссылке из письма — dashboard.
- AC дельты: регрессия «письмо при регистрации отправляется» (`Notification::fake` + `VerifyEmail`);
  «неверифицированный не попадает на dashboard» (redirect на notice); «верифицированный проходит»;
  существующие `EmailVerificationTest` становятся содержательными (middleware `verified` теперь боевой).
- Слои НЕ трогаются: `RegisterUserTask`/`UserRepository` без изменений — меняется только модель + тесты.
- Живая приёмка обязательна (поведение auth меняется): register → notice; ссылка из письма → верификация →
  dashboard; вход неверифицированным → notice; throttle-регресс остаётся зелёным.

## Оценка сложности
Средняя. Риски: (1) throttle-тесты чувствительны к состоянию RateLimiter между тестами (изолировать/чистить лимитер, чтобы не флейкать); (2) сужение nullable-user не должно менять рантайм-поведение verification-flow (маршруты под `auth` — user есть, но проверить edge с `MustVerifyEmail`); (3) переход на FormRequest не должен сломать redirect/ошибки существующих Breeze-тестов.
