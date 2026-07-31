# FEAT-005: Инфраструктура окружения и гейты качества (compose / env / composer / CI)

## Статус: SPEC

## Затрагиваемые репозитории
cbook (backend / инфраструктура) — один репозиторий. Мультирепный рецепт §3.5 не применяется.

## Цель
Довести локальный стенд и тулчейн качества до состояния ТЗ: поднять недостающие сервисы (Redis, Mailpit), выровнять `.env`/`.env.testing`/`phpunit.xml` под MySQL 8 + Redis + SMTP-Mailpit, добавить в `composer.json` скрипты гейтов (lint/analyse/test) и перевести setup/dev с npm на pnpm, включить CI (Pint + PHPStan + Pest + сборка фронта) на PR/push в `develop`.

## Контекст
База — `origin/develop @ e0c8ee3` (Breeze Inertia/Vue, слои Task/Repository/DTO заложены). Текущее состояние противоречит ТЗ и ловит грабли:
- `compose.yaml` поднимает только `mysql:8.4` (+ healthcheck); Redis и Mailpit отсутствуют, хотя стек ТЗ и `ai/ops/local-setup.md` их предполагают (кэш/очереди на Redis, перехват почты Mailpit).
- `.env.example`: `DB_CONNECTION=sqlite`, `MAIL_MAILER=log`, `MAIL_PORT=2525`, драйверы кэша/сессий/очередей на `database` — не соответствует целевому MySQL 8 + Redis + Mailpit.
- `phpunit.xml` задаёт `DB_DATABASE=testing`, но **не задаёт `DB_CONNECTION`** → соединение наследуется из локального `.env` (готча: поведение тестов зависит от машины). `.env.testing` отсутствует.
- `composer.json`: скрипты `setup`/`dev` завязаны на `npm`/`npx`; нет скриптов `lint`/`analyse`/`test`-обёрток под гейты. README описывает `npm`, не `pnpm`, и не упоминает redis/mailpit.
- CI отсутствует. Владелец подтвердил включение CI на `develop`.

Связанные инварианты: `ai/guides/stack-specifics.md` §«Адреса БД/хранилищ» (K-db precedence, DNS-имена сервисов Sail), §«Тесты» (ephemeral MySQL 8 по `.env.testing` + `RefreshDatabase`); жёсткое правило 5 (боевые креды в тесты не тащить). Гигиена §8 действует на CI-файл особо (см. ниже).

## Acceptance Criteria
- [ ] `./vendor/bin/sail up -d` поднимает контейнеры `laravel.test`, `mysql`, `redis`, `mailpit`; все healthy; `laravel.test` имеет `depends_on: [mysql, redis]`.
- [ ] Redis доступен на `:6379` (сервис `redis`, образ `redis:alpine`, свой healthcheck `redis-cli ping`, том для персистентности); Mailpit — SMTP `:1025` и UI `:8025` (образ `axllent/mailpit`).
- [ ] PHP-runtime остаётся **8.4** (`sail-8.4/app`, `runtimes/8.4`) — добавление сервисов не меняет runtime (готча «Sail дефолтит на свежий PHP»).
- [ ] `.env.example`: `DB_CONNECTION=mysql`, `DB_HOST=mysql`, `DB_PORT=3306`, `DB_DATABASE=cbook`, `DB_USERNAME`/`DB_PASSWORD` — плейсхолдеры; `REDIS_HOST=redis`; `MAIL_MAILER=smtp`, `MAIL_HOST=mailpit`, `MAIL_PORT=1025`; драйверы — по решению ниже.
- [ ] `.env.testing` присутствует: `DB_CONNECTION=mysql`, `DB_HOST=mysql`, `DB_DATABASE=testing`, креды `test_*`; кэш/сессии/очереди/почта — небоевые (`array`/`sync`/эфемерные). Боевых кред нет.
- [ ] `phpunit.xml` задаёт **явный** `DB_CONNECTION=mysql` (env-блок) — прогон тестов не зависит от локального `.env`.
- [ ] `composer.json` содержит скрипты `lint` (`pint --test`), `analyse` (`phpstan analyse`), `test` (уже есть — сохранить); `setup`/`dev` используют `pnpm`/`pnpm dlx`, не `npm`/`npx`.
- [ ] README приведён к `pnpm` (install/dev/build) и упоминает, что `sail up` поднимает MySQL + Redis + Mailpit; команды гейтов (`pint`/`phpstan`/`test`) присутствуют.
- [ ] `.github/workflows/ci.yml` на PR и push в `develop` прогоняет: Pint (`--test`), PHPStan (L10), Pest (на service-MySQL 8 через `DB_HOST=127.0.0.1` — override поверх `.env.testing`), `pnpm build` (через `pnpm install --frozen-lockfile` — `pnpm-lock.yaml` уже в репо). Красный гейт → красный CI. В workflow-файле — **ноль следов системы** (§8).
- [ ] После всех правок локально зелено: `sail artisan test`, `sail bin phpstan analyse`, `sail bin pint --test`, `pnpm build`.

## Технический дизайн

### compose.yaml
- Сервис `redis`: `image: redis:alpine`, порт `${FORWARD_REDIS_PORT:-6379}:6379`, том `sail-redis:/data`, healthcheck `redis-cli ping` (retries 3, timeout 5s), сеть `sail`.
- Сервис `mailpit`: `image: axllent/mailpit:latest`, порты `${FORWARD_MAILPIT_PORT:-1025}:1025` и `${FORWARD_MAILPIT_DASHBOARD_PORT:-8025}:8025`, сеть `sail`.
- `laravel.test.depends_on`: добавить `redis` (и `mailpit` по желанию — почта не блокирует старт; healthcheck-условие для mysql/redis).
- Том `sail-redis` в блок `volumes`. **Не трогать** блок сборки/runtime `laravel.test` (остаётся 8.4).

### .env.example (драйверы — РЕШЕНИЕ)
Зафиксировать под добавленный Redis, согласуясь со `stack-specifics.md` («Redis — как есть, кэш/очереди»):
- `CACHE_STORE=redis`
- `QUEUE_CONNECTION=redis`
- `SESSION_DRIVER=database` (сессии — в БД: переживают сброс Redis; таблица `sessions` есть в дефолтных миграциях Laravel 12; Breeze/тесты уже это предполагают)
- `REDIS_CLIENT=phpredis` (как есть), `REDIS_HOST=redis`
- Почта: `MAIL_MAILER=smtp`, `MAIL_HOST=mailpit`, `MAIL_PORT=1025`, `MAIL_USERNAME=null`, `MAIL_PASSWORD=null`.

> Обоснование выбора: cache/queue → redis (быстро, целевой стек); session → database (устойчивость + не требует дополнительной инфраструктуры в тестах/CI, т.к. тесты гоняют `array`-драйверы). Тестовый контур Redis не задействует → Redis-сервис в CI **не требуется**.

### .env.testing (новый)
- `APP_ENV=testing`, `APP_KEY=` (генерится в CI/локально), `DB_CONNECTION=mysql`, **`DB_HOST=mysql`** (коммитим значение под Sail — основной локальный путь `sail artisan test`, код внутри контейнера ходит к сервису по DNS-имени `mysql`), `DB_PORT=3306`, `DB_DATABASE=testing`, `DB_USERNAME=test_user`, `DB_PASSWORD=test_secret` — эфемерные `test_*`.
- ⚠️ **CI-контур ходит к MySQL иначе:** в GitHub Actions service-контейнер проброшен на `localhost` раннера, а шаги job'а бегут НА раннере (не внутри mysql-контейнера) → `DB_HOST=mysql` там не резолвится. Поэтому **CI-job `tests` переопределяет `DB_HOST=127.0.0.1`** (env job'а поверх скопированного `.env.testing`). Иначе — классика «зелено локально, красно в CI» (риск #1 фичи).
- `CACHE_STORE=array`, `SESSION_DRIVER=array`, `QUEUE_CONNECTION=sync`, `MAIL_MAILER=array`, `BCRYPT_ROUNDS=4`. Redis не задействован.
- Эфемерную БД `testing` создаёт `create-testing-database.sh` (уже смонтирован в `mysql`).

### phpunit.xml
- В `<php>` добавить `<env name="DB_CONNECTION" value="mysql"/>` (явно), сохранить `DB_DATABASE=testing`. Прочие env (`CACHE_STORE=array`, `SESSION_DRIVER=array`, `QUEUE_CONNECTION=sync`, `MAIL_MAILER=array`) уже есть — оставить. Precedence: значения `phpunit.xml`/`.env.testing` перекрывают `.env`.

### composer.json (владелец блока `scripts`)
- Добавить: `"lint": ["@php vendor/bin/pint --test"]`, `"analyse": ["@php vendor/bin/phpstan analyse"]`. `"test"` — сохранить.
- `setup`: `npm install`/`npm run build` → `pnpm install`/`pnpm build`.
- `dev`: `npx concurrently` → `pnpm dlx concurrently` (или локальный `concurrently` через `pnpm exec`), `npm run dev` → `pnpm dev` в строке concurrently.
- **Не трогать** блок `require`/`require-dev` (см. Зависимости/границы — это зона FEAT-006).

### README.md (единственный владелец правок README — FEAT-005)
- Секции запуска/команд: `npm install`→`pnpm install`, `npm run dev`→`pnpm dev`, `npm run build`→`pnpm build`.
- Явно: «`sail up -d` поднимает MySQL 8, Redis, Mailpit (UI `:8025`)».

### .github/workflows/ci.yml (новый; §8 — ноль следов системы)
- Триггеры: `pull_request` и `push` в `develop`.
- Job'ы (нейтральные имена, человеческий стиль): `code-style` (Pint `--test`), `static-analysis` (PHPStan L10), `tests` (Pest), `frontend` (`pnpm build`).
- `tests`: service-контейнер `mysql:8.4` (env сервиса: `MYSQL_DATABASE=testing`, `MYSQL_USER`/`MYSQL_PASSWORD` = `test_*`, `MYSQL_ROOT_PASSWORD`), шаги `composer install`, `cp .env.testing`/`key:generate`, `artisan migrate`, `artisan test`. **Job задаёт `env: DB_HOST=127.0.0.1`** (сервис на localhost раннера — переопределяет `DB_HOST=mysql` из `.env.testing`, см. выше); `DB_USERNAME`/`DB_PASSWORD` совпадают с кредами сервиса. Redis service не нужен (тесты на `array`/`sync`).
- Frontend: setup pnpm + Node, `pnpm install --frozen-lockfile`, `pnpm build`.
- ⛔ Никаких упоминаний `ai/`, FEAT-номеров, агентов; имена шагов/job'ов — как в обычном OSS-репозитории.

## Тесты
**Добавить:** отдельных Pest-тестов фича не требует (инфраструктурная). Валидация — прогоном существующего набора на новом соединении.
**Обновить:** нет изменений assertion-ов; проверить, что `sail artisan test` зелёный на MySQL-`testing` (а не sqlite).
**Удалить:** нет.

> Чувствительные данные/permissions не затрагиваются напрямую; правило негативных тестов неприменимо (нет нового защищённого маршрута).

## Типизация/качество (минимальный набор гейтов)
- Локально до коммита: `sail bin pint --test` (pass), `sail bin phpstan analyse` (L10, No errors), `sail artisan test` (0 fail), `pnpm build` (ok). Тяжёлые прогоны — через `./scripts/gate.sh test|build -- <cmd>`.
- Новых подавлений типов/линтера не вносим. Baseline PHPStan (8 записей) в этой фиче **не трогаем** — его гасит FEAT-007 (см. границы).

## Безопасность
- **Доступы:** новых маршрутов/эндпоинтов нет. Новых поверхностей атаки на уровне приложения нет.
- **Данные:** `.env.testing` содержит только `test_*`-значения — боевые креды (Neon, MinIO/S3, Cloudflare, API-токены) в тесты/CI не попадают (жёсткое правило 5). Секреты CI — только через GitHub Secrets, не в YAML.
- **Валидация:** неприменимо (нет пользовательского ввода).
- **Гигиена §8:** CI-workflow и все правки — без следов системы; коммит через `commit.sh` (стоп-словарь физически блокирует следы в workflow-файле).

## Пользовательская документация
README проекта обновляется в рамках этой фичи (pnpm + перечень сервисов) → user-visible для разработчика. Отразить строкой в `impl.md`. Клиентский `CLAUDE.md` инфраструктуру запуска уже описывает — проверить и при расхождении синхронизировать.

## Зависимые файлы для изменения
| Файл | Тип изменения |
|---|---|
| `compose.yaml` | добавить сервисы `redis`, `mailpit`, том `sail-redis`, `depends_on` |
| `.env.example` | mysql/redis/mailpit + драйверы (cache=redis, queue=redis, session=database) |
| `.env.testing` | новый — mysql `testing`, `test_*`, эфемерные драйверы |
| `phpunit.xml` | явный `DB_CONNECTION=mysql` |
| `composer.json` | скрипты `lint`/`analyse`; npm→pnpm в `setup`/`dev` (блок `scripts` only) |
| `README.md` | npm→pnpm; упоминание Redis/Mailpit |
| `.github/workflows/ci.yml` | новый — Pint+PHPStan+Pest+pnpm build на develop |

## Зависимости/границы (сверка с 006/007/008)
- **Порядок:** FEAT-005 реализуется **первой** — задаёт зелёную инфраструктуру и гейты, на которые опираются 006/007/008.
- **`composer.json`:** FEAT-005 владеет блоком **`scripts`** (и npm→pnpm). FEAT-006 позже добавит **`require-dev`** `spatie/laravel-typescript-transformer` (иная секция того же файла) — при последовательной реализации 006 ребейзится на 005; конфликта строк нет, но обе фичи трогают `composer.json` — интегрировать по очереди.
- **`README.md`:** единственный владелец — FEAT-005. FEAT-008 при необходимости документирует свои `lint`/`typecheck` поверх уже смерженной базы 005 (не параллельно).
- **`package.json`:** FEAT-005 **не трогает** (только README/composer). Скрипты npm и devDependencies — зона FEAT-008.
- **`phpstan-baseline.neon`:** FEAT-005 не трогает; удаление baseline — FEAT-007.
- **CI:** файл заводит FEAT-005; последующие фичи добавляют шаги (например `pnpm lint`/`pnpm typecheck` из 008) поверх смерженной базы.

## Что НЕ входит
- UserData DTO / генерация TS-типов (FEAT-006).
- Throttle/FormRequest/удаление baseline (FEAT-007).
- ESLint/tsconfig/чистка скаффолда/Tailwind-линия (FEAT-008).
- Миграция на Tailwind v4, доменные сущности Recipe/Ingredient, Filament, media.

## Оценка сложности
Средняя. Ключевые риски: (1) CI-прогон Pest требует корректно поднятого service-MySQL и `.env.testing` — легко «позеленеть локально, покраснеть в CI»; (2) смена драйверов кэша/сессий может потребовать наличия таблицы `sessions` (проверить дефолтные миграции L12); (3) §8-чистота CI-файла — критично, проверяется «ревью чистоты».
