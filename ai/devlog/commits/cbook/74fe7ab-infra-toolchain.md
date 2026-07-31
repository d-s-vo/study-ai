---
repo: cbook
authored_hash: 74fe7ab903d627ec6ea9d3fceaefc70849113b96
patch_id: d108f08cd5716c884e1d626fba313fea0e60df50
branch: feat/infra-toolchain
feat: FEAT-005
date: 2026-07-31
final_hash:
fix_chain:
  - hash: cc3df94f9ca4ef22e87e33dfe6c32e9a12632804
    patch_id: 4cf21d0b3c4a7f0a5f3554a5b2cea30c760f190c
    message: 'fix: указать версию pnpm в CI'
  - hash: 1ff25dfe1089ac52b14919f1ae712e8f1c66e78c
    patch_id: 2fed2fa22856b95ecd05d0b2769e6f705f2f3101
    message: 'ci: прогонять линт и проверку типов фронтенда'
---

# cbook@74fe7ab — chore: поднять redis и mailpit, выровнять окружение под mysql и завести CI

> Коммит-сообщение (как в клиентском репо): `chore: поднять redis и mailpit, выровнять окружение под mysql и завести CI`
> Итоговая цепочка: `74fe7ab` (фича, 8 файлов, +189/−21) + `cc3df94`
> (`fix: указать версию pnpm в CI` — закрытие блокера ревью, +4) + `1ff25df`
> (`ci: прогонять линт и проверку типов фронтенда` — энфорс гейтов смежной фичи, +4).

## Кратко (для инженера)

- **compose.yaml** — добавлены сервисы `redis` (`redis:alpine`, том `sail-redis:/data`, healthcheck
  `redis-cli ping`) и `mailpit` (`axllent/mailpit:latest`, SMTP `:1025` + UI `:8025`);
  `laravel.test.depends_on` += `redis`; том `sail-redis` в `volumes`. Блок сборки/runtime
  `laravel.test` (PHP 8.4) не тронут.
- **.env.example** — переведён на целевой стек: `DB_CONNECTION=sqlite→mysql`, `DB_HOST=mysql`,
  `DB_DATABASE=cbook`, плейсхолдер-креды; `CACHE_STORE=redis`, `QUEUE_CONNECTION=redis`,
  `SESSION_DRIVER=database` (как было); `REDIS_HOST=redis`; почта `smtp`/`mailpit`/`1025`.
- **.env.testing.example** (НОВЫЙ) — тестовый профиль: `DB_CONNECTION=mysql`, `DB_HOST=mysql`,
  `DB_DATABASE=testing`, `test_user`/`test_secret`; `CACHE_STORE=array`, `SESSION_DRIVER=array`,
  `QUEUE_CONNECTION=sync`, `MAIL_MAILER=array`, `BCRYPT_ROUNDS=4`, `APP_KEY=` (генерится). Только
  `test_*` — боевых кред нет.
- **.gitignore** — += `.env.testing` (живой локальный профиль копией из `.example`).
- **phpunit.xml** — добавлен явный `<env name="DB_CONNECTION" value="mysql"/>` — прогон тестов больше
  не зависит от локального `.env`.
- **composer.json** (блок `scripts`) — добавлены `lint` (`pint --test`) и `analyse`
  (`phpstan analyse`); `setup`/`dev` переведены с `npm`/`npx` на `pnpm`/`pnpm dlx`. `require`/
  `require-dev` не тронуты.
- **README.md** — `npm`→`pnpm` (install/dev/build); строка «`sail up` поднимает MySQL 8, Redis,
  Mailpit (UI :8025)»; шаг `cp .env.testing.example .env.testing` перед тестами.
- **.github/workflows/ci.yml** (НОВЫЙ) — триггеры `pull_request`/`push` в `develop`; job'ы
  `code-style` (Pint `--test`), `static-analysis` (PHPStan L10), `tests` (Pest на service `mysql:8.4`,
  job-env `DB_HOST=127.0.0.1` поверх шаблона), `frontend` (`pnpm build`).

## Детально (для новичка)

### Зачем Redis и Mailpit в compose
Целевой стек ТЗ держит кэш и очереди на **Redis** (быстрое key-value хранилище), а почту в разработке
перехватывает **Mailpit** (локальный SMTP-сервер с веб-интерфейсом — письма никуда реально не уходят,
их видно в браузере на `:8025`). До этого коммита Sail поднимал только MySQL — приложение по стеку ТЗ
не могло работать. Добавлены два сервиса и приватный том `sail-redis`, чтобы данные Redis переживали
рестарт контейнера. `depends_on: [mysql, redis]` у `laravel.test` — чтобы приложение стартовало после БД
и кэша.

### Почему `.env.testing.example`, а не `.env.testing`
Тесты обязаны ходить в отдельную БД `testing` на MySQL (не в локальную/sqlite), иначе «поведение тестов
зависит от машины». Профиль хранится в репозитории как **шаблон** `.env.testing.example`; живой
`.env.testing` создаётся копией и **игнорируется git** (`.gitignore`). Так в репо не попадают даже
тестовые значения под именем реального env-файла — это требование эшелона безопасности (никакие `.env.*`
кроме `*.example` не коммитятся). CI копирует шаблон сам.

### Зачем явный `DB_CONNECTION=mysql` в phpunit.xml
Раньше `phpunit.xml` задавал `DB_DATABASE=testing`, но не задавал **тип соединения** — он наследовался
из локального `.env`. На машине с `DB_CONNECTION=sqlite` тесты молча уходили в sqlite. Явная строка
приколачивает соединение к MySQL независимо от машины.

### CI (GitHub Actions)
Четыре независимых job'а — стиль кода (Pint), статический анализ (PHPStan L10), тесты (Pest) и сборка
фронта (pnpm build). Job `tests` поднимает service-контейнер `mysql:8.4` рядом с раннером; т.к. шаги
job'а бегут **на раннере**, а не внутри mysql-контейнера, DNS-имя `mysql` там не резолвится — поэтому
job переопределяет `DB_HOST=127.0.0.1` (сервис проброшен на localhost раннера) поверх скопированного
шаблона. Красный любой гейт → красный CI.

## Почему так, а не иначе (отклонения от spec)

- **`.env.testing` → `.env.testing.example`** — вынужденно: клиентский pre-commit guard безусловно
  блокирует любой staged `.env.*` кроме `*.example` (hard-rule «`.env`-файлы не коммитятся никуда»);
  `--no-verify` запрещён, правка security-хука — только владелец. Интент спеки (закоммиченный
  несекретный `test_*`-профиль, который потребляет CI) сохранён полностью.
- **`pnpm build` в job `tests`** (добавлено поверх спеки) — Inertia Feature-тесты рендерят страницы и
  требуют Vite-манифест; без сборки CI покраснел бы на «Vite manifest not found». Добавлены setup
  pnpm/Node + `pnpm install --frozen-lockfile` + `pnpm build` перед `artisan test`. Закрывает
  заявленный риск #1 фичи.
- **Драйверы** (cache=redis, queue=redis, session=database) — по решению спеки (session в БД переживает
  сброс Redis и не требует Redis в тестовом контуре).

## Цепочка после ревью

### `cc3df94` — fix: указать версию pnpm в CI (блокер ревью)
Оба шага `uses: pnpm/action-setup@v4` (job'ы `tests` и `frontend`) были без входа `version:`, а
`package.json` не содержит поля `packageManager` → по документации action-setup v4 шаг падает, CI
красный на любом PR/push. Фикс: `with: version: 10` к обоим шагам. Мажор выбран по факту: локально
pnpm 10.30.3, `pnpm-lock.yaml` `lockfileVersion: '9.0'` — pnpm 10 читает его (зелёный
`pnpm install --frozen-lockfile` локально). `package.json` не тронут (зона смежной фичи).

### `1ff25df` — ci: прогонять линт и проверку типов фронтенда (расширение по итогам ревью смежной фичи)
**Мотив:** параллельная ветка гигиены фронта вводит npm-скрипты `lint` (eslint flat-config) и
`typecheck` (`vue-tsc --noEmit`); обе ветки уйдут в `develop`, и CI обязан энфорсить эти гейты после
её merge. В job `frontend` между `Install dependencies` и `Build` добавлены шаги `Lint`
(`pnpm run --if-present lint`) и `Typecheck` (`pnpm run --if-present typecheck`).

**Почему `--if-present`:** до merge смежной ветки скриптов в `package.json` нет, а шаги не должны
валить CI. Флаг `--if-present` даёт no-op с exit 0 при отсутствии скрипта; после появления скриптов
шаги начинают реально исполняться и энфорситься — без повторной правки workflow.

**Доказательство no-op:** локальный прогон pnpm 10.30.3 на текущем `package.json` (скриптов нет):
`pnpm run --if-present lint` → exit 0, `pnpm run --if-present typecheck` → exit 0. YAML провалидирован
(`yq`): порядок шагов job `frontend` — checkout → Setup pnpm → Setup Node → Install dependencies →
Lint → Typecheck → Build.

## Связи

- Фича: `../../features/FEAT-005-infra-toolchain/impl.md` · `spec.md`.
- Стек/инварианты: `../../guides/stack-specifics.md` (адреса БД/хранилищ, тесты), `../../ops/local-setup.md`.
- Гигиена клиентского репо (§8) — CI-файл особо: `../../architecture.md` §8.
