---
repo: cbook
authored_hash: f4a9d63c6fd11a002333ea8ad78ec06a5f214a1a
patch_id: 767ec0ee3f7b
feat: FEAT-007
branch: feat/auth-hardening
reviewer_model: Opus 4.8
review_date: 2026-07-31
verdict: PASS
blockers_total: 0
blockers_open: 0
resolved_by: []
---

# cbook@f4a9d63 — REVIEW — feat: включить обязательное подтверждение email при регистрации

**Verdict:** PASS
**Blocking findings:**
- нет
**Non-blocking notes:**
- `routes/web.php:23-27` — `/profile`-роуты остаются только под `auth` (без `verified`): неверифицированный пользователь может редактировать/удалять профиль до подтверждения email. Это дефолт Breeze, pre-existing и не менялось этим коммитом (parity сохранён); спека-дельта требует `verified` только для dashboard. Если владелец захочет гейтить и профиль — отдельное продуктовое решение (severity: nit).
- Процесс: разборы ADR-009 автора для `f4a9d63`/`6605919` в `ai/devlog/commits/cbook/` на момент ревью **отсутствуют** — по канону §6 «тихие фиксы запрещены» разбор обязателен до merge; это обязательство автора/оркестратора, корректность кода не затрагивает (severity: minor, процессный).

**Evidence:**
- Прочитано ПЕРЕД diff: spec-дельта «email-верификация» (решение владельца 2026-07-31), исходный `a1f6c53-review.md` (мой блокер), `git show f4a9d63` построчно, vendor-исходники (`EmailVerificationRequest`, `EnsureEmailIsVerified`, `SendEmailVerificationNotification`, `Events\Verified`).
- **Блокер a1f6c53 закрыт по существу, root-cause:** `App\Models\User implements Illuminate\Contracts\Auth\MustVerifyEmail` (методы уже были через трейт базового `Foundation\Auth\User`) + `VerifyEmailController` сведён к штатному `$request->fulfill()` — **assert-ов в verify-контуре не осталось вовсе** (не «перепрятано», а устранено). `fulfill()` — точный поведенческий эквивалент прежнего кода: `if (! hasVerifiedEmail()) { markEmailAsVerified(); event(new Verified(...)); }`, redirect `?verified=1` в обеих ветках сохранён.
- **Гейты перепрогнал сам** (контейнер `laravelsail/php84-composer`, worktree tasks/auth-hardening @ 6605919): `php -d zend.assertions=1 -d assert.exception=1 vendor/bin/pest` → **39 passed (106 assertions), 0 AssertionError** — именно та среда, что валила старый ложный assert (репро моего контрпримера: red до фикса по построению, green после — подтверждено). `phpstan analyse --memory-limit=1G` → **L10 [OK] No errors** (без baseline). `pint --test` → **PASS 60 files**. Оставшиеся в кодовой базе `assert()` — только всегда-истинные (`!== null` под auth-middleware, `is_string`), вычищенные ещё ревью e0c8ee3. Прогон — на sqlite in-memory (для вопроса assert/маршрутов/middleware СУБД-фактор нейтрален); MySQL-высота — CI job tests.
- **OWASP-линза нового поведения:** `verification.verify` остался под `['signed', 'throttle:6,1']` (роуты этим коммитом не тронуты); `EmailVerificationRequest::authorize()` — `hash_equals` и по `id`, и по `sha1(getEmailForVerification())` → подписанная ссылка не подделывается, чужой id/hash → 403 (существующий тест «email is not verified with invalid hash» это держит); `verification.send` — под `auth` + `throttle:6,1` (спам писем ограничен); dashboard под `['auth', 'verified']` — обхода notice нет: `EnsureEmailIsVerified` редиректит любого `MustVerifyEmail`-юзера без верификации. Утечки enumeration не добавлено (письмо шлётся только своему юзеру после регистрации/по своей сессии).
- **Тесты мутационно (3 новых):** «a verification email is sent on registration» — убрать `implements MustVerifyEmail` → листенер `SendEmailVerificationNotification` (гард `instanceof MustVerifyEmail`) молчит → `assertSentTo` красный; убрать `event(new Registered(...))` из контроллера → красный. «unverified users are redirected to the verification notice» — убрать `implements` или `verified` из роута → красный. «verified users can access the dashboard» — ловит over-blocking (например, редирект всех подряд). Существующий «email can be verified» теперь боевой: убрать `$request->fulfill()` → `hasVerifiedEmail()` останется false → красный. Ни один не вакуумен.
- **Чужая среда (§3 п.8):** CI-профиль (`.env.testing.example`: `MAIL_MAILER=array`, `CACHE_STORE=array`) — `Notification::fake` от мейлера не зависит; новых asserts нет → настройка `zend.assertions` раннера больше не влияет; изменения DB-агностичны (новых запросов в прод-коде нет; `User::where` — только в тесте). Прод `--no-dev`: dev-пакеты не затронуты.
- **Слои/parity:** `RegisterUserTask`/`UserRepository` не тронуты (соответствует спека-дельте «слои НЕ трогаются»); throttle-контур a1f6c53 не задет.
- Гигиена: следов системы/стоп-слов в diff и сообщении коммита не замечено; conventional `feat:`.

**Suggested next:** none (для кода); авторские разборы ADR-009 на f4a9d63/6605919 — добить до merge (процессная нота выше).

## Рубрика (бинарно, commit-review.md §3)

☑ Атомарность/целостность (один смысл — включение верификации; 3 файла; гейты зелёные) · ☑ Логика vs спека-дельта (все AC дельты покрыты: письмо/notice/dashboard) · ☑ Business-security (signed+hash_equals, throttle сохранён, обхода notice нет) · ☑ Тихие регрессии/parity (`fulfill()` ≡ прежней логике; слои/роуты не тронуты) · ☑ Тесты (мутационно — каждый ловит конкретную мутацию, см. Evidence) · ☑ N+1/перф (нет) · ☑ Over-engineering (минимальный канонический фикс) · ☑ Чужая среда (asserts устранены; CI-профиль сверен)

## Журнал закрытия находок

- Находок нет. Этот коммит закрывает blocker исходного `a1f6c53` (отметка — в `a1f6c53-review.md`).

## Связи

- Исходное ревью с блокером: `a1f6c53-review.md` (FAIL-veto снят этим фиксом).
- Фича: `../../features/FEAT-007-auth-hardening/spec.md` (раздел «Дельта: email-верификация») · `impl.md`.
- Гайд ревью: [`../../guides/commit-review.md`](../../guides/commit-review.md) (§6 фикс-цикл, §3 п.8).
