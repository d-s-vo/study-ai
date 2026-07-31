---
repo: cbook
authored_hash: a1f6c53b45907f6525e51a0e5c1281c08f7a563e
patch_id: e9ada681a6ca3122e8754156c17f341c47daf349
branch: feat/auth-hardening
feat: FEAT-007
date: 2026-07-31
final_hash:
fix_chain:
  - hash: f4a9d63c6fd11a002333ea8ad78ec06a5f214a1a
    patch_id: 767ec0ee3f7bf94ad27b93978f416abcf8eb3ed4
    message: 'feat: включить обязательное подтверждение email при регистрации'
  - hash: 6605919034728fc55a520cda782848a102c160ef
    patch_id: 49d4f3e30e8c403a8a1b2b3b6c4f0ac26882332e
    message: 'docs: отметить обязательное подтверждение email в инструкции запуска'
---

# cbook@a1f6c53 — feat: усилить auth — троттлинг публичных роутов, валидация во FormRequest, снятие PHPStan-baseline

> Коммит-сообщение (как в клиентском репо): `feat: усилить auth — троттлинг публичных роутов, валидация во FormRequest, снятие PHPStan-baseline`
> Итоговая цепочка: `a1f6c53` (фича, 19 файлов, +229/−98) + `f4a9d63`
> (`feat: включить обязательное подтверждение email при регистрации` — закрытие блокера ревью по spec-дельте владельца, 4 файла, +39/−14)
> + `6605919` (`docs: отметить обязательное подтверждение email в инструкции запуска` — user-visible строка в README, +3).

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
    `EmailVerificationPromptController@__invoke`; в `VerifyEmailController@__invoke` в `a1f6c53` стоял
    `assert($user instanceof MustVerifyEmail)` — **это блокер ревью** (предикат ложен в рантайме), снят
    фикс-коммитом, см. ниже;
  - 1× Stringable→string — `LoginRequest::throttleKey()`: `Str::lower((string) $this->string('email'))`.
- **`tests/Feature/Auth/AuthThrottleTest.php`** (НОВЫЙ) — 3 регрессии: register / forgot-password /
  reset-password — 6 POST подряд проходят (302), 7-й → **429**.

**Фикс-коммит `f4a9d63` (spec-дельта владельца — email-верификация внедряется по-настоящему):**
- **`app/Models/User.php`** — `implements Illuminate\Contracts\Auth\MustVerifyEmail` (методы уже были через
  трейт базового `Foundation\Auth\User`); удалён Breeze-комментарий-подсказка.
- **`VerifyEmailController`** — сведён к штатному `$request->fulfill()` (`EmailVerificationRequest::fulfill()`,
  канон Fortify) + redirect; обращений к `$request->user()` и любых assert в контроллере больше нет.
- **`tests/Feature/Auth/RegistrationTest.php`** — +1: «a verification email is sent on registration»
  (`Notification::fake` + `VerifyEmail`; юзер после регистрации не верифицирован).
- **`tests/Feature/Auth/EmailVerificationTest.php`** — +2: неверифицированный на `/dashboard` →
  redirect `verification.notice`; верифицированный → 200.

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
`UserRepository` из FEAT-004); предикат `!== null` под `auth` всегда-истинный.

### Блокер ревью и фикс `f4a9d63` (email-верификация)
В `a1f6c53` восьмую запись (`new Verified($user)` ждёт контракт `MustVerifyEmail`) я закрыл через
`assert($user instanceof MustVerifyEmail)` — и это оказалось **ложным в рантайме** сужением:
`App\Models\User` (через базовый `Foundation\Auth\User`) подключает одноимённый **трейт**, но не
**интерфейс**. В Sail (`zend.assertions=-1`) assert скомпилирован в no-op и ложь маскировалась, но при
`zend.assertions=1` (дефолт php.ini-development) каждый GET по signed-ссылке `/verify-email/{id}/{hash}`
падал бы AssertionError→500, а `EmailVerificationTest` в такой среде краснел. Урок: assert-сужение
допустимо **только** со всегда-истинным предикатом; «работает у нас» ≠ «истинно».

Закрытие — не заплаткой, а по существу (продуктовое решение владельца, spec-дельта FEAT-007):
верификация email **внедряется**. `User implements MustVerifyEmail` — и типовая дыра исчезает сама:
у Laravel всё уже готово (трейт-методы, роуты Breeze, листенер). Контроллер при этом сведён к штатному
`EmailVerificationRequest::fulfill()` — так делает Fortify; в контроллере не остаётся ни `$request->user()`,
ни сужений (vendor-код PHPStan-ом проекта не анализируется, а главное — после контракта и сам `fulfill()`
типово честен). Наблюдаемое поведение verify-роута то же (already-verified → redirect без события;
unverified → mark + `Verified` + redirect); единственная микро-разница — событие больше не гейтится
булевым результатом `save()` (практически всегда true, при сбое БД был бы throw).

**Последствия включения контракта — ожидаемое новое поведение (проверено):**
1. `Registered` → фреймворковый листенер `SendEmailVerificationNotification` (автоподписка в
   `Foundation\Support\Providers\EventServiceProvider:226`) — при регистрации уходит письмо верификации.
2. Middleware `verified` (на `/dashboard`) становится боевым: неверифицированный → redirect
   `verification.notice`; до контракта `EnsureEmailIsVerified` пропускал всех (не-`MustVerifyEmail`
   считается верифицированным).
3. Слои не тронуты: `RegisterUserTask`/`UserRepository` без изменений — дельта меняет только модель
   (+контракт) и тесты.

### Изоляция RateLimiter в тестах (риск №1 спеки)
Throttle-тесты флейкают, когда счётчик лимитера переживает границу теста. Здесь изоляция штатная:
`phpunit.xml` задаёт `CACHE_STORE=array`, а тестовый `TestCase` пересоздаёт приложение на каждый тест —
array-стор умирает вместе с ним. Отдельного `RateLimiter::clear()` не требуется; накопление попыток
происходит только внутри одного теста (6×302 → 7-я 429).

## Почему так, а не иначе (отклонения от spec)

База `a1f6c53` — по дефолтам спеки: профиль `throttle:6,1` (а не именованный лимитер — «не усложнять
без нужды»), `(string)`-каст в `throttleKey()` (вариант, названный спекой), сужение assert-ом в стиле
`ProfileController`. Брифовое «~9 записей baseline» подтвердилось как 8 — пункт «+1 прочее» не понадобился.

Главное отклонение — **spec-дельта после ревью** (`f4a9d63`): спека предлагала assert-сужение до
`MustVerifyEmail`, ревью доказало ложность предиката; владелец решил внедрить верификацию вместо
консервации. Дельта задокументирована в `spec.md` §«Дельта: email-верификация (решение владельца
2026-07-31)». User-visible следствие — регистрация теперь требует подтверждения email — по согласованию
отражено в README клиента отдельным docs-коммитом `6605919` (строка в секции локального запуска: notice
до перехода по ссылке из письма; локально письма перехватывает Mailpit `:8025`).

Замечание за пределами диффа: в свежем worktree `pnpm build` под pnpm 11.18 требует нового поля
`allowBuilds` в `pnpm-workspace.yaml` (иначе esbuild не собирается) — тот же паттерн, что фиксировал
FEAT-004. Локально ставилось `allowBuilds: {esbuild: true}` и **восстанавливалось до коммита**:
фронт-конфиг в этот коммит не входит (зона infra/FEAT-008).

## Гейты (итог цепочки a1f6c53 + f4a9d63)

- Pest (полный, `gate.sh backend-tests`) — **39 passed** (106 assertions), 0 fail/skip; было 33,
  +3 throttle, +3 верификация. Прогон под `php -d zend.assertions=1 -d assert.exception=1` —
  одновременно доказательство: все оставшиеся assert-предикаты всегда-истинны (ни одного AssertionError).
- PHPStan **L10 без baseline** — `[OK] No errors` (ключевой AC: ноль подавлений, ноль ложных сужений).
- Pint `--test` — passed. Арх-барьер (ArchitectureTest, изоляция Eloquent) — в составе Pest, зелёный.
- `pnpm build` (`gate.sh frontend-build`) — ✓ (фронт не менялся, сборка не регрессировала).
- Живая приёмка №1 (после `a1f6c53`, стенд :8130, снят): register → 302 `/dashboard` → 200; logout/login
  живые; сброс пароля по реальному письму (log-mailer, токен 64 симв.) → login новым паролем → 200;
  throttle фактический: `POST /forgot-password` — попытки 1–6 → 302, **7-я → 429**.
- Живая приёмка №2 (после `f4a9d63`, тот же стенд, снят): register → `/dashboard` → 302 `/verify-email`
  (notice 200); письмо верификации реально уходит — signed-ссылка из лога → 302 → `/dashboard` **200**;
  повторный `/verify-email` верифицированным → 302 на dashboard; второй неверифицированный юзер:
  login → `/dashboard` → 302 `/verify-email`; throttle-регресс: 1–6 → 302, **7-я → 429**.

## Связи

- Фича: `../../features/FEAT-007-auth-hardening/` (`spec.md` — вкл. §Дельта email-верификации, `impl.md`).
- Ревью коммита: `a1f6c53-review.md` (блокер — ложное сужение; закрыт `f4a9d63` по spec-дельте).
- Базис: `e0c8ee3-breeze-inertia-auth.md` (FEAT-004 — происхождение baseline и канона assert-сужения).
- Инварианты: `../../guides/stack-specifics.md` §Backend (FormRequest, тонкие контроллеры), `../../memory.md` North Star.
