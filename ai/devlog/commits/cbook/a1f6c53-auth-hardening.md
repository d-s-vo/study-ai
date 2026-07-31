---
repo: cbook
authored_hash: a1f6c53b45907f6525e51a0e5c1281c08f7a563e
patch_id: e9ada681a6ca3122e8754156c17f341c47daf349
branch: feat/auth-hardening
feat: FEAT-007
date: 2026-07-31
final_hash:
---

# cbook@a1f6c53 — feat: усилить auth — троттлинг публичных роутов, валидация во FormRequest, снятие PHPStan-baseline

> Коммит-сообщение (как в клиентском репо): `feat: усилить auth — троттлинг публичных роутов, валидация во FormRequest, снятие PHPStan-baseline`
> Один коммит (19 файлов, +229/−98), fix-цепочки нет.

## Кратко (для инженера)

- **`routes/auth.php`** — `->middleware('throttle:6,1')` на трёх `guest`-POST: `register`,
  `forgot-password` (`password.email`), `reset-password` (`password.store`). Профиль `6,1` единый
  с существующими verification-роутами. `POST login` намеренно **без** throttle-middleware — он уже
  лимитируется внутри `LoginRequest` (RateLimiter, 5 попыток по email+IP); двойной лимит не вводится.
- **5 новых FormRequest** (правила перенесены из контроллеров 1:1, `authorize(): true` — маршруты уже
  под `guest`/`auth`): `app/Http/Requests/Auth/RegisterRequest.php`, `Auth/NewPasswordRequest.php`,
  `Auth/PasswordResetLinkRequest.php`, `Auth/UpdatePasswordRequest.php` и
  `app/Http/Requests/ProfileDeleteRequest.php` (размещение — по конвенции соседей `LoginRequest` /
  `ProfileUpdateRequest`).
- **5 контроллеров стали тоньше** — сигнатура `Request` → FormRequest, блок `$request->validate([...])`
  удалён: `RegisteredUserController@store`, `NewPasswordController@store`,
  `PasswordResetLinkController@store`, `PasswordController@update`, `ProfileController@destroy`.
  Бизнес-делегирование не тронуто: `RegisterUserTask::run()`, `UserRepository::setPassword()/delete()`,
  `Password::reset()/sendResetLink()` — как были (STRICT: мутации `User` остаются в слое Repository/Task).
- **`phpstan-baseline.neon` УДАЛЁН** (8 записей), из `phpstan.neon` убрана строка `- phpstan-baseline.neon`
  в `includes`. Все подавления погашены по коду:
  - 7× «method/property on `User|null`» — сужение `$user = $request->user(); assert($user !== null);`
    в `ConfirmablePasswordController@store`, `EmailVerificationNotificationController@store`,
    `EmailVerificationPromptController@__invoke`; в `VerifyEmailController@__invoke` —
    `assert($user instanceof MustVerifyEmail)` (закрывает и nullable-вызовы, и аргумент `new Verified($user)`);
  - 1× Stringable→string — `LoginRequest::throttleKey()`: `Str::lower((string) $this->string('email'))`.
- **`tests/Feature/Auth/AuthThrottleTest.php`** (НОВЫЙ) — 3 регрессии: register / forgot-password /
  reset-password — 6 POST подряд проходят (302), 7-й → **429**.

## Детально (для новичка)

### Зачем throttle на register/forgot/reset
Это единственные публичные (гостевые) POST-точки приложения без rate-limit: без него бот бесплатно
брутфорсит регистрацию, спамит письмами сброса пароля и перебирает reset-токены. `throttle:6,1` —
стандартный middleware Laravel: максимум 6 запросов в минуту с одного клиента, дальше HTTP 429
(Too Many Requests). Значение выбрано не произвольно, а тем же профилем, что Breeze уже ставит на
verification-роуты — единая политика для всех «письмо-шлющих»/чувствительных точек. `login` не трогали:
у него собственный, более умный лимитер в `LoginRequest` (считает только *неудачные* попытки, ключ
email+IP, сбрасывается при успехе) — навесить сверху ещё и `throttle:6,1` значило бы лимитировать в двух
местах с разными окнами и путать пользователя.

### Зачем FormRequest вместо `$request->validate()`
Инвариант проекта (`stack-specifics.md` §Backend): **вся** серверная валидация — во FormRequest,
контроллер тонкий. Инлайн-`validate()` в теле метода смешивает слои: правила нельзя переиспользовать,
контроллер знает о деталях ввода, а единый поток Request→Controller→Task→Repository ломается на первом
же шаге. FormRequest резолвится контейнером до входа в метод: к моменту выполнения тела запрос уже
провалидирован, при ошибке Laravel сам вернёт redirect с ошибками по тем же ключам — поэтому поведение
и тексты ошибок не изменились, что и фиксируют оставшиеся зелёными Breeze-тесты (включая негативные
кейсы неверного `current_password`).

### Почему baseline можно (и нужно) было снять по коду
Baseline — это список «известных ошибок», который PHPStan молча пропускает; FEAT-004 оставил его
осознанно (только нетронутый Breeze-scaffold). Все 8 записей — один класс: `$request->user()` типизирован
как `User|null` (guest-запрос — null), но на маршрутах под `auth`-middleware user гарантирован. Приём
сужения — локальная переменная + `assert()` — уже канонический в проекте (`ProfileController`,
`UserRepository` из FEAT-004). Важно: в рантайме Sail `zend.assertions = -1`, т.е. `assert()`
скомпилирован в no-op и **ничего не проверяет в проде** — это чисто статическая подсказка типов для
PHPStan. Поэтому и `assert($user instanceof MustVerifyEmail)` в `VerifyEmailController` безопасен:
`App\Models\User` контракт `MustVerifyEmail` сейчас не реализует (verification-flow дремлет), но код
этого контроллера недостижим без включения контракта, а рантайм-поведение assert не меняет. Делать
`User implements MustVerifyEmail` было бы неверно — это включило бы обязательную верификацию email
для всего приложения (middleware `verified` на dashboard начал бы отсекать всех неверифицированных),
т.е. смену продуктового поведения под видом типового фикса.

### Изоляция RateLimiter в тестах (риск №1 спеки)
Throttle-тесты флейкают, когда счётчик лимитера переживает границу теста. Здесь изоляция штатная:
`phpunit.xml` задаёт `CACHE_STORE=array`, а тестовый `TestCase` пересоздаёт приложение на каждый тест —
array-стор умирает вместе с ним. Отдельного `RateLimiter::clear()` не требуется; накопление попыток
происходит только внутри одного теста (6×302 → 7-я 429).

## Почему так, а не иначе (отклонения от spec)

Отклонений от спеки нет — реализация по дефолтам спеки: профиль `throttle:6,1` (а не именованный
лимитер — «не усложнять без нужды»), `(string)`-каст в `throttleKey()` (вариант, названный спекой),
сужение assert-ом в стиле `ProfileController`. Брифовое «~9 записей baseline» подтвердилось как 8 —
пункт спеки «+1 прочее» не понадобился.

Замечание за пределами диффа: в свежем worktree `pnpm build` под pnpm 11.18 требует нового поля
`allowBuilds` в `pnpm-workspace.yaml` (иначе esbuild не собирается) — тот же паттерн, что фиксировал
FEAT-004. Локально ставилось `allowBuilds: {esbuild: true}` и **восстанавливалось до коммита**:
фронт-конфиг в этот коммит не входит (зона infra/FEAT-008).

## Гейты

- Pest (полный, `gate.sh backend-tests`) — **36 passed** (101 assertions), 0 fail/skip; было 33, +3 throttle.
- PHPStan **L10 без baseline** — `[OK] No errors` (ключевой AC: ноль подавлений).
- Pint `--test` — passed. Арх-барьер (ArchitectureTest, изоляция Eloquent) — в составе Pest, зелёный.
- `pnpm build` (`gate.sh frontend-build`) — ✓ (фронт не менялся, сборка не регрессировала).
- Живая приёмка (изолированный стенд :8130, снят): register → 302 `/dashboard` → 200; logout/login живые;
  сброс пароля по реальному письму (log-mailer, токен 64 симв.) → login новым паролем → 200;
  throttle фактический: `POST /forgot-password` — попытки 1–6 → 302, **7-я → 429**.

## Связи

- Фича: `../../features/FEAT-007-auth-hardening/` (`spec.md`, `impl.md`).
- Базис: `e0c8ee3-breeze-inertia-auth.md` (FEAT-004 — происхождение baseline и канона assert-сужения).
- Инварианты: `../../guides/stack-specifics.md` §Backend (FormRequest, тонкие контроллеры), `../../memory.md` North Star.
