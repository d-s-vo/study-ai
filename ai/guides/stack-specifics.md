# Гайд: Стек-специфика проекта cbook

> Этот файл — **отправная точка** для стек-специфичных правил проекта: команды гейтов, окружения, миграции, инварианты backend/frontend.
> Он — **главный параметрический слот**: сюда ведут все стек-специфичные ссылки из универсальных гайдов (feature-workflow, debugging, live-acceptance). Заполняй каждую обязательную секцию под текущий стек; пустых обязательных секций оставаться не должно.
> По мере роста разбивай на отдельные гайды (`api-service.md`, `client-entity.md`, `dev-local.md`), оставляя здесь навигацию.

> ⛔ **Гигиена клиентского репозитория** действует на весь код (см. `../architecture.md` §8): без следов системы, коммит через `scripts/commit.sh`, временные пометки только `~wip~`, push — только пользователь.

> **Стек (ТЗ):** PHP **8.4** + Laravel **12** + MySQL **8**; Inertia.js + Vue 3 (`<script setup>`, TypeScript **strict**) + **Tailwind CSS**; слой данных — Spatie **Laravel Data** (DTO) + `artisan typescript:transform`; админка — Filament **5**; медиа — `whyme-agency/laravel-media`; качество — PHPStan **Level 10** + Laravel Pint (PSR-12, `declare_strict_types`). Строгая слоистая архитектура (поток Request→Controller→Task→Repository→DTO→Resolver→Inertia). Локально — Laravel Sail (Docker), СУБД MySQL 8 (сервис `mysql`, порт 3306), инструмент `./vendor/bin/sail`. Legacy-контур (Nuxt 4 / Prisma / Neon Postgres / MinIO) — донор идеи и BVI-панели, замещается переписанным Laravel-приложением, см. `../memory.md`.
>
> ⚠️ Прежние дефолты (Laravel 11 / PHP 8.3 / PostgreSQL / Filament 3) **отменены ТЗ**.

---

## Команды (гейты) — ОБЯЗАТЕЛЬНАЯ секция

Таблица команд по слоям. Это **источник истины** для команд, которые цитируют универсальные гайды. Всё, что бьёт по БД/контейнерам, идёт через Sail; фронт — через pnpm.

| Действие | Backend/сервер (Laravel 12 / PHP 8.4; слои Controller→Task→Repository→DTO→Resolver) | Frontend/клиент (Inertia + Vue 3 `<script setup>` + TS strict + Tailwind, Vite; Filament 5 — админка) |
|----------|------------------------------------|--------------------------------------|
| Установка зависимостей | `composer install` | `pnpm install` |
| Dev-запуск | `./vendor/bin/sail up -d` (+ `sail artisan migrate`) | `pnpm dev` (Vite) |
| Сборка | `composer install --no-dev -o` | `pnpm build` |
| Тесты | `./vendor/bin/sail artisan test` (**Pest PHP**) | `(отсутствует; при необходимости Vitest)` |
| Typecheck / статанализ | `./vendor/bin/sail bin phpstan analyse` (**Level 10**, Larastan) | `pnpm vue-tsc --noEmit` (TS strict) |
| Lint | `./vendor/bin/sail bin pint --test` (PSR-12) | `pnpm lint` (ESLint, если настроен) |
| Автоформат | `./vendor/bin/sail bin pint` | `pnpm format` |
| Генерация TS-типов из DTO | `./vendor/bin/sail artisan typescript:transform` (Spatie Data → TS) | — (типы приходят готовыми в `resources/js`) |

> **Минимальный набор гейтов** (M3 quality-ratchet в профиле выключен): тесты (Pest) + статанализ (**PHPStan Level 10** — на нём же ловится нарушение изоляции Eloquent и слоёв) + lint (Pint). После изменения DTO — прогнать `artisan typescript:transform`, чтобы TS-типы не разъехались. Прогоняются вручную; тяжёлые прогоны сериализуй через `./scripts/gate.sh <ресурс> -- <команда>` (имена ресурсов `build | test | migrate`), чтобы параллельные агенты не били по общей RAM/CPU.

> Однопроектный стек — один столбец backend + один frontend. `./vendor/bin/sail` можно завести под алиас `sail`.

### venv / изоляция тулчейна — ОБЯЗАТЕЛЬНАЯ секция

- **Рантайм-окружение:** PHP-тулчейн и сервисы (php 8.4, **mysql 8**, redis, mailpit) живут в **Sail-контейнерах** (Docker); PHP-инструменты вызываются как `./vendor/bin/sail <...>` или `./vendor/bin/<tool>` внутри контейнера. Composer-зависимости — в `vendor/`, node-зависимости — в `node_modules/` **внутри каждого worktree** (`tasks/<slug>/`): свежий worktree требует `composer install && pnpm install` (Step-0 sync). Абсолютный путь тулчейна — `vendor/bin` (+ `node_modules/.bin`).

### Адреса БД/хранилищ из окружения — ОБЯЗАТЕЛЬНАЯ секция

Правило (K-db): **env задан → берётся из env; env не задан → дефолт локального стенда.** Precedence: `shell export > .env > .env.testing`.

| Переменная | Хост-дефолт (env не задан) | Сервис Sail (Docker) |
|---|---|---|
| `DB_CONNECTION` | `mysql` | `mysql` |
| `DB_HOST` | `127.0.0.1` | `mysql` |
| `DB_PORT` | `3306` | `3306` |
| `REDIS_HOST` | `127.0.0.1` | `redis` |
| `REDIS_PORT` | `6379` | `6379` |
| `MAIL_HOST` | `127.0.0.1` | `mailpit` (`:1025`, UI `:8025`) |

> Внутри Sail код обращается к сервисам по DNS-именам контейнеров (`mysql`, `redis`), с хоста — по проброшенным портам на `127.0.0.1`. Redis — как есть (кэш/очереди). Боевые адреса/креды (legacy Neon, дисковый бэкенд медиа, Cloudflare Tunnel) — только через `.env`, наружу не выносить.

---

## Тесты (контуры БД / тестовая цепочка) — ОБЯЗАТЕЛЬНАЯ секция

- **Ephemeral (основной режим):** тесты (**Pest PHP**) идут на отдельной тестовой БД MySQL 8 по `.env.testing`; трейт `RefreshDatabase` пересоздаёт схему миграциями перед прогоном. Изоляции task-окружений отдельным скриптом нет (M4 off) — для параллельной работы держи тестовую БД под задачу вручную (отдельная база/схема) или полагайся на `RefreshDatabase` в транзакции.
- **CI:** если pipeline настроен на стороне клиента — ephemeral + service-БД (уточнить, см. `../memory.md`).

**Маркеры/файлы тестов:** Pest — `tests/Feature`, `tests/Unit`; конфиг — `phpunit.xml` / `.env.testing`; precedence env — `shell export > .env > .env.testing`. Для нового кода обязательны **негативные** тесты на права и изоляцию данных по владельцу (см. `../architecture.md` §8).

---

## Инварианты проекта — ОБЯЗАТЕЛЬНАЯ секция (трёхчастная рубрика)

> Против этих инвариантов проверяются тройная проверка spec (feature-workflow Шаг 5) и адверсариальная приёмка (live-acceptance).

**Backend / сервер (строгая слоистая архитектура — 5 STRICT RULES ТЗ):**
- **`declare(strict_types=1)` в КАЖДОМ `.php`** — файл начинается с `<?php declare(strict_types=1);` (Pint это чинит/проверяет).
- **Изоляция Eloquent (жёстко):** `Eloquent\Model` и фасад `DB` — ТОЛЬКО внутри `app/Data/Repositories/*`. Контроллеры, Tasks, Resolvers, Vue напрямую Eloquent/`DB` НЕ вызывают. **Нарушение = ошибка PHPStan Level 10** (проверяется гейтом статанализа, не только ревью).
- **Единый поток данных:** Request (**FormRequest**) → **Controller** → **Task** (бизнес-логика) → **Repository** (запрос к БД) → **DTO** (Spatie Data) → **Page Resolver** → **Inertia Vue Page**. Слои не «перепрыгивать».
- **Только DTO наружу:** в Inertia/Vue передаются ТОЛЬКО DTO (Spatie Data) — никаких сырых Eloquent-моделей/массивов.
- **Именование слоёв — по каталогам:** одна бизнес-операция = один Task (`app/Tasks/CreateRecipeTask.php`); сборка пропсов страницы = Resolver (`app/Resolvers/Page/RecipeDetailResolver.php`); запросы к БД = Repository (`app/Data/Repositories/RecipeRepository.php`).
- **Контроллеры тонкие** — принимают провалидированный FormRequest, делегируют в Task/Resolver, возвращают Inertia-ответ; бизнес-логики в контроллере нет.
- **Валидация — во FormRequest** (вся серверная валидация), не в контроллере россыпью.
- **Авторизация — через Policies/Gate**, явная проверка прав до бизнес-логики; данные изолированы по владельцу.
- **Изменение схемы — только миграцией** (`database/migrations/`), не руками в БД.
- **Секреты — только из env**, в код/тесты боевые креды не попадают.

**Frontend / клиент:**
- **Допустимый UI** — Vue 3 SFC (`<script setup>`, TypeScript **strict**) + Inertia + **Tailwind CSS**; админ-экраны — Filament 5 (не смешивать с публичным UI без причины).
- **Типизация** — 0 `any`/`as`-кастов в новом коде; типы props Inertia-страниц — из **автогенерации** `artisan typescript:transform` (Spatie Data → TS), руками TS-модели DTO не дублировать.
- **Источник данных** — props Inertia со страницы (DTO с сервера как слой-прокси), не прямой fetch на чужие хосты.
- **Tailwind-утилиты/дизайн-токены** вместо хардкод-литералов цвета/отступов.

**Процесс:**
- Изоляция фичи — `./scripts/task.sh new <slug>` (ветка `feat/<slug>`).
- Коммит — `scripts/commit.sh`; push/merge/MR — пользователь.
- После user-visible изменения — правило публичной доки: отразить в клиентском `CLAUDE.md`/README и строкой в `impl.md` фичи.

---

## Backend-специфика — секция под стек

Структура приложения — по конкретным слоям потока (не абстрактные Domain/Application/Infrastructure):

| Каталог | Роль | Может трогать Eloquent/`DB`? |
|---|---|---|
| `app/Http/Requests/` | FormRequest — вся серверная валидация | нет |
| `app/Http/Controllers/` | Тонкий контроллер — принял FormRequest, делегировал в Task/Resolver, вернул Inertia | нет |
| `app/Tasks/` | Одна бизнес-операция = один Task (`CreateRecipeTask.php`) | нет (через Repository) |
| `app/Data/Repositories/` | Запросы к БД — **единственное место** Eloquent-моделей и фасада `DB` | **ДА (только здесь)** |
| `app/Data/` | DTO на Spatie Laravel Data (`RecipeData.php`); источник TS-типов | нет |
| `app/Resolvers/Page/` | Page Resolver — сборка пропсов Inertia-страницы из DTO (`RecipeDetailResolver.php`) | нет (через Repository) |
| `app/Models/` | Eloquent-модели (`Recipe`, `Ingredient`) — используются только из репозиториев | — |
| `app/Enums/` | Enum'ы домена (`Difficulty` = `low\|medium\|high`) | нет |
| `app/Filament/` | Filament 5 Resource'ы (`/admin`) без бизнес-логики | делегируют в Task/Repository |

Регистрация роутов — `routes/web.php` (Inertia); DI/биндинги репозиториев — в сервис-провайдерах. Медиа (изображения рецептов) — через пакет `whyme-agency/laravel-media`.

### Порядок создания новой сущности (снизу-вверх, под слои ТЗ) — инвариант

1. **Миграция** (`database/migrations/`) — схема таблицы.
2. **Eloquent-модель** (`app/Models/`) — связи (`hasMany`), casts (`steps` → array, `difficulty` → Enum).
3. **Repository** (`app/Data/Repositories/`) — запросы к БД; **единственное место** Eloquent/`DB`.
4. **DTO** (`app/Data/`, Spatie Laravel Data) — форма данных наружу; после — `artisan typescript:transform`.
5. **Task** (`app/Tasks/`) — бизнес-операция; вызывает Repository, возвращает DTO.
6. **FormRequest** (`app/Http/Requests/`) — серверная валидация входа.
7. **Controller** (`app/Http/Controllers/`, тонкий) — FormRequest → Task, вернуть Inertia.
8. **Resolver** (`app/Resolvers/Page/`) — сборка пропсов страницы из DTO.
9. **Inertia Vue page** (`resources/js/Pages/`, `<script setup>` + TS strict) — получает только DTO-пропсы.
10. **Pest-тесты** — позитив + негатив (права, изоляция по владельцу).

> Порядок «миграция → модель → Repository → DTO → Task → FormRequest → Controller → Resolver → Inertia → Pest» — **инвариант** (feature-workflow Шаг 7); Eloquent живёт только в Repository, наружу идёт только DTO.

---

## Frontend-специфика — секция под стек

Клиент — Inertia-страницы в `resources/js/Pages/` (Vue 3 `<script setup>`, TypeScript strict), компоненты в `resources/js/Components/`, состояние — composables/stores, стили — **Tailwind CSS**. TS-типы данных — **не пишутся руками**: генерируются из DTO командой `artisan typescript:transform` (Spatie Data → TS).

### Слои сущности
DTO-типы (автоген из `typescript:transform`) → composable/store (состояние, при необходимости) → Inertia-страница (получает **только DTO** props'ами со стороны Resolver'а) → компоненты. Прямого API-клиента к бэкенду нет — данные приходят через Inertia; мутации — через Inertia-формы/POST на именованные роуты.

---

## Работа с датами / интеграциями — секция под стек

- **Таймзона:** хранить время в UTC (`APP_TIMEZONE=UTC` / `timestamp`-колонки), выводить по локали пользователя; в тестах фиксировать время явно.
- **Медиа (изображения рецептов):** через пакет `whyme-agency/laravel-media` (не ручной драйвер `s3`); дисковый бэкенд (локальный/S3) — `(уточнить)`; креды только из `.env`.
- **Legacy-интеграции (Nuxt-контур, донор идеи+BVI, замещается):** Neon (Postgres) через Prisma, MinIO (S3), Cloudflare Tunnel — референс; в целевом стеке схема пишется заново под Sail (MySQL 8), медиа — через `whyme-agency/laravel-media` / уточняются.

---

## Сквозные реестры (для крупных инициатив, adr-execution.md H.8) — ОБЯЗАТЕЛЬНАЯ секция

Объект, участвующий в сквозной гарантии, прошивай во ВСЕ точки в одной фиче:

- **Новая доменная сущность с доступом по владельцу** → миграция + Eloquent-модель (`app/Models`) + Repository (`app/Data/Repositories`) + DTO (Spatie Data) + Task + FormRequest + контроллер/Resolver/Inertia + **Policy** + seed (если справочник) + негативные тесты прав.
- **Новый защищённый маршрут/действие** → backend Policy/authorize + FormRequest-валидация + отражение доступности в UI (Inertia props/навигация) + негативный тест (чужой пользователь → отказ), сквозная проверка end-to-end, не по имени окружения.

---

## Связи

- [`./feature-workflow.md`](./feature-workflow.md) — обязательный процесс работы над фичей
- [`../architecture.md`](../architecture.md) — полный обзор стека + §8 гигиена
- [`../adr/`](../adr/) — архитектурные решения проекта (стек — ADR-002, слои — ADR-003, миграция — ADR-006)
- Первоисточники: `CLAUDE.md`, dev-доки клиента, `../ops/local-setup.md`
