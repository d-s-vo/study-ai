---
repo: cbook
authored_hash: f4a9d63c6fd11a002333ea8ad78ec06a5f214a1a
patch_id: 767ec0ee3f7bf94ad27b93978f416abcf8eb3ed4
branch: feat/auth-hardening
feat: FEAT-007
date: 2026-07-31
final_hash:
---

# cbook@f4a9d63 — feat: включить обязательное подтверждение email при регистрации

> Коммит-сообщение (как в клиентском репо): `feat: включить обязательное подтверждение email при регистрации`
> Контекст: фикс-звено цепочки `a1f6c53` (FEAT-007) — закрывает блокер ревью `a1f6c53-review.md`
> по spec-дельте владельца (см. `spec.md` §«Дельта: email-верификация»). 4 файла, +39/−14.

## Кратко (для инженера)

- **`app/Models/User.php`** — `class User extends Authenticatable implements MustVerifyEmail`
  (контракт `Illuminate\Contracts\Auth\MustVerifyEmail`); удалён Breeze-комментарий-подсказка
  `// use ...MustVerifyEmail;`. Методы контракта (`hasVerifiedEmail()`, `markEmailAsVerified()`,
  `sendEmailVerificationNotification()`, `getEmailForVerification()`) уже были — их даёт одноимённый
  **трейт** в базовом `Illuminate\Foundation\Auth\User`; коммит добавляет только интерфейс.
- **`app/Http/Controllers/Auth/VerifyEmailController.php`** — тело `__invoke` сведено к
  `$request->fulfill()` + один redirect на `dashboard?verified=1`. Убраны: ручная ветка
  hasVerified/markEmailAsVerified + `event(new Verified(...))`, обращение `$request->user()` и —
  главное — **ложное в рантайме** сужение `assert($user instanceof MustVerifyEmail)` из `a1f6c53`.
- **`tests/Feature/Auth/RegistrationTest.php`** — +1 тест «a verification email is sent on registration»:
  `Notification::fake()` → POST register → юзер не верифицирован, нотификация
  `Illuminate\Auth\Notifications\VerifyEmail` отправлена.
- **`tests/Feature/Auth/EmailVerificationTest.php`** — +2 теста: неверифицированный на `/dashboard` →
  redirect `verification.notice`; верифицированный (дефолт фабрики) → 200.

## Детально (для новичка)

### Блокер, который закрывает этот коммит
В `a1f6c53` для типизации `new Verified($user)` стояло `assert($user instanceof MustVerifyEmail)`.
Предикат был **ложен**: базовый класс модели подключает одноимённый *трейт* (даёт методы), но не
*интерфейс* (даёт тип) — `instanceof` по интерфейсу в рантайме возвращал false. В Sail это маскировалось
(`zend.assertions=-1` — assert скомпилирован в no-op), но при `zend.assertions=1` (дефолт
php.ini-development) каждый переход по ссылке верификации падал бы AssertionError→500. Урок FEAT-007:
assert-сужение допустимо только со всегда-истинным предикатом.

### Почему «включить верификацию», а не другое сужение
Продуктовое решение владельца (spec-дельта): дремлющий verification-флоу Breeze не консервируем, а
включаем по-настоящему. С контрактом на модели типовая ложь исчезает сама — `$request->user()` теперь
статически и фактически `MustVerifyEmail`. Альтернативы отвергнуты: (а) честная ветка
`if ($user instanceof MustVerifyEmail)` вокруг события — при невключённом контракте событие переставало
бы диспатчиться → красный `EmailVerificationTest` и смена поведения; (б) `@var`/`@phpstan-ignore` —
запрещённые подавления; (в) оставить как было — блокер.

### Почему контроллер теперь `fulfill()`
`EmailVerificationRequest::fulfill()` — штатный метод фреймворка (им пользуется Fortify): внутри та же
логика «не верифицирован → пометить + `event(new Verified(...))`». Контроллеру не нужно ни доставать
юзера, ни сужать типы — меньше поверхности для ошибок. Наблюдаемое поведение идентично прежнему
(already-verified → redirect без события; unverified → mark + событие + redirect); единственная
микро-разница — событие не гейтится булевым результатом `save()` (тот практически всегда true, сбой БД
даёт throw, а не false).

### Что включилось вместе с контрактом (ожидаемые последствия, покрыты тестами)
1. **Письмо при регистрации.** Фреймворк автоподписывает листенер `SendEmailVerificationNotification`
   на событие `Registered` (`Foundation\Support\Providers\EventServiceProvider:226`), а листенер шлёт
   письмо только юзерам-`MustVerifyEmail`. До контракта — молчал, теперь работает.
2. **Middleware `verified` стал боевым.** `/dashboard` объявлен `->middleware(['auth','verified'])` ещё
   скаффолдом, но `EnsureEmailIsVerified` пропускает всех, кто не `instanceof MustVerifyEmail` — т.е.
   до этого коммита проверка была инертной. Теперь неверифицированный редиректится на
   `verification.notice` до клика по ссылке из письма.
3. **Слои не тронуты:** `RegisterUserTask`/`UserRepository` не менялись — дельта не требует новых
   мутаций модели (пометку верификации делает трейт внутри штатного флоу, зона Breeze-scaffold).

## Почему так, а не иначе (отклонения от spec)

Коммит реализует spec-дельту (владелец, 2026-07-31) — отклонений от неё нет. От исходной спеки FEAT-007
это отход по решению владельца: исходно предлагалось assert-сужение (оказалось ложным), теперь —
внедрение верификации. User-visible следствие (регистрация требует подтверждения) отражено в README
следующим звеном цепочки (`6605919`).

## Гейты

- Pest — **39 passed** (106 assertions), 0 fail; прогон под `php -d zend.assertions=1 -d assert.exception=1`
  (assert'ы активны) — доказательство, что ложных предикатов в цепочке не осталось.
- PHPStan **L10 без baseline** — `[OK] No errors`; Pint — passed; арх-барьер зелёный.
- Живая приёмка (стенд :8130, снят): register → `/dashboard` → 302 `/verify-email` (notice 200);
  signed-ссылка из реального письма (log-mailer) → 302 → `/dashboard` **200**; повторный `/verify-email`
  → 302 на dashboard; второй неверифицированный юзер после login блокируется на notice;
  throttle-регресс FEAT-007: `POST /forgot-password` 1–6 → 302, 7-я → **429**.

## Связи

- Головной разбор цепочки: `a1f6c53-auth-hardening.md` (fix_chain).
- Ревью: `a1f6c53-review.md` (блокер-первоисточник), `f4a9d63-review.md` (PASS этого звена).
- Фича: `../../features/FEAT-007-auth-hardening/` (`spec.md` §Дельта, `impl.md` §3b).
