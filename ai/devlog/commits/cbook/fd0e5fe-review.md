---
repo: cbook
authored_hash: fd0e5fea37819c0e3f507738629bc9d2ce0ef416
patch_id: f870bb6f43f98fcd6b5cf51d70c1881c0a4cfff2
feat: FEAT-006
branch: feat/user-dto
reviewer_model: Opus 4.8
review_date: 2026-07-31
verdict: FAIL
blockers_total: 1
blockers_open: 1
resolved_by: []
---

# cbook@fd0e5fe — REVIEW — feat: отдавать текущего пользователя в Inertia через DTO и генерировать TS-типы из слоя данных

**Verdict:** FAIL
**Blocking findings:**
- `bootstrap/providers.php:10` (+ `app/Providers/TypeScriptTransformerServiceProvider.php:14`) — провайдер зарегистрирован **безусловно**, но его базовый класс `Spatie\LaravelTypeScriptTransformer\TypeScriptTransformerApplicationServiceProvider` живёт в пакете `spatie/laravel-typescript-transformer`, который в `composer.lock` числится в **`packages-dev`** (require-dev). В прод-сборке (`composer install --no-dev`) пакет удаляется → базового класса в `vendor/` нет. Laravel инстанцирует ВСЕ провайдеры из `bootstrap/providers.php` безусловно (на каждом запросе и в `artisan optimize`/`config:cache`/`package:discover`); PHP обязан разрешить родительский класс в момент объявления дочернего → автолоад падает → **Fatal error: Class "Spatie\LaravelTypeScriptTransformer\TypeScriptTransformerApplicationServiceProvider" not found**. Evidence-контрпример: `composer install --no-dev` сам запускает post-autoload-dump `@php artisan package:discover` → бут фреймворка → инстанцирование провайдера → фатал ещё на этапе установки зависимостей; далее — любой HTTP-запрос в проде не поднимается. Это прямо **противоречит собственному AC спеки** («require-dev … прод не нужен, т.к. `generated.d.ts` коммитится»): интент — прод НЕ зависит от пакета, а реализация делает прод-бут ЖЁСТКО зависимым от dev-пакета и роняет его без него.

**Non-blocking notes:**
- `tests/Feature/UserDataTest.php:49-57` — altitude-gap покрытия (severity: minor). Негативные ассерты Inertia-теста `->missing('auth.user.password')` / `->missing('auth.user.remember_token')` **не ловят** регрессию STRICT RULE 4 «DTO → сырая модель»: у модели `User` `$hidden = ['password','remember_token']`, поэтому даже при мутации кода назад к `'user' => $user` (сырой Eloquent) эти поля в Inertia-сериализации отсутствуют, а `id/name/email` присутствуют, guest = `null` — все текущие ассерты остаются зелёными. Поле, которое сырая модель РЕАЛЬНО протекла бы (`created_at`/`updated_at`), тест на отсутствие не проверяет. Рекомендация: добавить `->missing('auth.user.created_at')` (или проверку точного набора ключей) — тогда тест начнёт стеречь именно контракт «DTO, а не модель». Код корректен; замечание только к сторожевой силе теста.

**Evidence:**
- Прочитано ДО diff (§2): `spec.md` (AC), `impl.md` (2 задокументированных отклонения), `ai/memory.md` (5 STRICT RULES, канон Task, gotchas), `ai/architecture.md §8` (гигиена).
- `git show fd0e5fe` построчно по всем файлам (кроме `composer.lock`, сверен секционно).
- **Провайдер/прод (blocker):** базовый класс — `vendor/spatie/laravel-typescript-transformer/src/TypeScriptTransformerApplicationServiceProvider.php`; `composer.lock`: `spatie/laravel-typescript-transformer 3.3.0` и `spatie/typescript-transformer 3.3.0` — оба в секции **`packages-dev`**. `bootstrap/providers.php` возвращает провайдер безусловно (нет `class_exists`-гарда, нет env-условия). Родитель резолвится при объявлении класса → недостижим под `--no-dev`. Reachability: путь НЕ за OFF-флагом и НЕ за неактивированной фазой — это стандартный прод/CI-install и документированный деплой (`develop`→`main`, CLAUDE.md); Evidence «спящего» статуса отсутствует → по §4.2 downgrade до WARN неприменим.
- **`UserData.php`:** `final extends Data`, `#[TypeScript]`, поля `id:int / name:string / email:string / email_verified_at:?CarbonImmutable` — пароля/remember_token нет. OK.
- **`HandleInertiaRequests.php`:** ссылки на `App\Models\User` НЕТ (STRICT RULE 2 соблюдён); `UserData::from($user)` принимает `Authenticatable`, null-guard `$user !== null ? … : null` корректен для гостя. STRICT RULE 4 удовлетворён. OK.
- **Отклонение №2 (`?CarbonImmutable` вместо `?string`):** обосновано и **прямо предусмотрено спекой** («или `?CarbonImmutable` с TS-маппингом в string|null»); `replaceType(CarbonImmutable/DateTimeInterface → 'string')` даёт в TS `string | null`; на выходе Inertia — ISO-строка. Критерии спеки не нарушены.
- **Отклонение №1 (трансформер v3 вместо v2):** функциональные AC (require-dev, конфиг, коллектор на `app/Data`, команда `typescript:transform`, коммит `generated.d.ts`) выполнены. НО именно v3-подход «конфиг = провайдер, наследующий dev-класс» и породил blocker выше — само отклонение допустимо, дефектна лишь **безусловная регистрация** провайдера.
- **`generated.d.ts`:** `App.Data.UserData = { id:number, name:string, email:string, email_verified_at:string|null }` — точно соответствует `UserData`. `index.d.ts`: рукописный `interface User` удалён, `auth.user: App.Data.UserData | null` (глобальный ambient, без рукописного дубля). Null-safety Vue — только `?.` и `?? ''`, 0 `any`/`as`/`!`. Гейты (impl.md) зелёные: Pint/PHPStan L10/Pest 38 passed/pnpm build (vue-tsc).
- **Гигиена §8 / чистота:** стоп-словарь `githooks/stopwords.txt` по клиентскому дифу (`grep -iE`) — **чисто, 0 совпадений**. Сообщение коммита `feat: отдавать текущего пользователя в Inertia через DTO и генерировать TS-типы из слоя данных` — conventional (`feat:`), «от лица человека», без следов системы/FEAT-номеров.
- **Атомарность:** один логический смысл (DTO наружу + автоген типов + null-safety потребителей + тесты); фикс+фича не смешаны. OK.

**Suggested next:** fix-now (fix-forward-FEAT-006, та же ветка)

## Рубрика (бинарно, commit-review.md §3)

☑ Атомарность/целостность (один смысл, компилируется, гейты зелёные)
☒ Логика vs спека/интент — **нарушен собственный AC спеки** (require-dev «прод не нужен»): прод-бут падает без dev-пакета (blocker)
☑ Business-security (OWASP) — RULE 4/RULE 2 соблюдены; password/remember_token не покидают backend
☑ Тихие регрессии/parity — форма пропа `auth.user` изменена осознанно, потребители null-safe
◑ Тесты (мутационно) — негативные ассерты утечки не ловят регрессию DTO→модель (minor altitude-gap, см. ноту)
☑ N+1/перф — `UserData::from()` в middleware не делает запрос к БД
☑ Over-engineering — сложность соразмерна; `withoutManifest()` уместен

## Журнал закрытия находок

- **Blocking #1** (`bootstrap/providers.php:10` — безусловная регистрация провайдера с dev-only базовым классом) → ОТКРЫТ. Направление фикса (мелкий, в той же фиче, приводит к уже записанному AC — спека-дельта не нужна): регистрировать провайдер условно — например только вне production (`App::runningUnitTests()`/`!app()->isProduction()`) или через `class_exists(...)`-гард, либо вынести регистрацию из безусловного `bootstrap/providers.php` в `AppServiceProvider::register()` под условием. `generated.d.ts` коммитится → прод кодоген не нужен, потому провайдер в проде не требуется вовсе. После фикс-коммита — узкое ревью §6 (закрыта ли находка + нет ли регрессии), снятие FAIL-veto — только исходным ревьюером.
- **Nit/minor** (altitude-gap теста) → advisory: закрыть тем же фикс-коммитом (`->missing('auth.user.created_at')`) либо принять с записью.

## Связи

- Разбор «почему» (автор, ADR-009): `fd0e5fe-user-dto.md` (файл-разбор рядом; ревьюером не трогается).
- Фича: `../../features/FEAT-006-user-dto/impl.md` · `spec.md`.
- Долг-первоисточник: `e0c8ee3-review.md` (advisory FEAT-004 — сырой `User` в Inertia).
- Гайд ревью: [`../../guides/commit-review.md`](../../guides/commit-review.md).
