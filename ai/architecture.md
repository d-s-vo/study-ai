# cbook — Архитектура проекта

> **Для AI-ассистента:** это главный файл контекста. **Начни с §0 (роутер задач)** — он определит тип твоей работы и направит в нужный гайд; разделы 1–11 — справочник по подсистемам.
> Дополнительно: `memory.md` (текущий статус), `adr/` (обоснования решений), `guides/` (пошаговые руководства), `devlog/features/` (история фич).

> ⚠️ **Внешнее размещение контекста (мета-правило).** Эта база знаний (`ai/`, репозиторий **study-cbook-ai**) живёт **вне** репозиториев кода. Код клиентских реп (`cbook`) в неё **не входит**. Все ссылки на код в документах — пути **от корня workspace** (`cbook/...`), без `../` наружу из `ai/`.

> ⛔ **Режим секретности.** Клиентские репозитории не должны нести НИ ОДНОГО следа этой системы. Полное правило — §8 «Гигиена клиентского репозитория»; краткая памятка есть в каждом гайде и брифе.

---

## 0. 🧭 Старт для AI-агента (роутер задач) — читай ПЕРВЫМ

Единственное, что нужно прочитать, чтобы начать. Определи тип работы по таблице ниже → открой указанный гайд **ПЕРВЫМ** → следуй его алгоритму.

**Базовый цикл любой задачи:** этот файл (обзор) → тип работы по таблице ниже → читаешь гайд → покрываешь тестами → живая приёмка → крупное ведёшь через субагентов. Всё, что уходит в клиентский код, проходит §8 (гигиена репозитория).

> **Перед стартом ЛЮБОЙ работы — прочти [`memory.md`](memory.md)** (текущий статус: фокус, что в исполнении, открытые задачи и gotchas). Это дешевле, чем повторять уже сделанное.

### Куда копать — по типу работы

| Делаешь | Читай ПЕРВЫМ (порядок) | Ключевой гейт / нельзя забыть |
|---|---|---|
| **Одну нетривиальную фичу** (2+ файла/пакета, новый контракт/схема, новый компонент, >30 мин) | [`guides/feature-workflow.md`](guides/feature-workflow.md) | Specs-First (≥2 фич → спеки на ВСЕ ДО кода) · worktree через `./scripts/task.sh new <slug>` + Step-0 sync · реализация снизу-вверх · §8 гигиена |
| **Фича с архитектурным решением** (decision-ADR: ОДНА фича + одна карточка `adr/NNN`) | [`guides/feature-workflow.md`](guides/feature-workflow.md) + мини-шаг ADR (§4.5) | decision-ADR = одна карточка `adr/NNN-slug.md` (в `ai/`, НЕ в клиентском коде) · ≠ ADR-инициатива (десятки фич → `adr-execution.md`) · номер: `coord.sh book --adr` или следующий свободный · статус Принят→Реализован в §10 |
| **Крупный блок / целый ADR** (десятки фич), ты — оркестратор | [`guides/adr-execution.md`](guides/adr-execution.md) (слой НАД feature-workflow) | Закоммить подготовленный ADR ДО делегирования · specs-first гейт фазы · живой документ (статус+журнал+keystone) = часть DoD · каждую фичу → субагенту · **это НЕ decision-ADR одной фичи** |
| **Серверная фича** (Laravel / слои: миграция · модель · Repository · DTO · Task · FormRequest · Controller · Resolver · Inertia) | [`guides/stack-specifics.md`](guides/stack-specifics.md) §Backend-специфика + `feature-workflow.md` | Framework-first (проверь, есть ли готовое в Laravel/пакете); строгие инварианты (Eloquent/`DB` — только в `app/Data/Repositories/*`, enforced PHPStan L10; поток Controller→Task→Repository→DTO→Resolver; наружу только DTO; авторизация через Policies) — см. stack-specifics |
| **Клиентская фича** (Inertia/Vue: страница · компонент · composable/store · типы) | [`guides/stack-specifics.md`](guides/stack-specifics.md) §Frontend-специфика + `feature-workflow.md` | Types-first (0 `any`/`as`; TS strict; DTO-типы — автоген `artisan typescript:transform`); в props — только DTO Inertia, не прямой fetch; стили — Tailwind; Filament 5 Resource без бизнес-логики — см. stack-specifics |
| **Поиск причины бага / дебаг** (тест упал · данные пропали · рендер пуст) | [`guides/debugging.md`](guides/debugging.md) | Repro → trace → binary search по стыкам → root-cause-fix → regression-тест · сверься с `process-metrics/known-flakes.md` ДО диагностики |
| **Живая приёмка / проверить X живьём** (curl · браузер · e2e) | [`guides/live-acceptance.md`](guides/live-acceptance.md) | Зелёные тесты ≠ работает: прогони реальный сценарий · свой код — на изолированном стенде (даже соло) · часть DoD |
| **Ретро процесса при закрытии инициативы** | [`guides/process-retro.md`](guides/process-retro.md) | Разбор процесса (не продукта): что стоило дорого, что переделали |
| **Trivial-fix** (1-2 файла, <50 LOC, не миграция/контракт/keystone) | `feature-workflow.md` §Trivial-fix shortcut | **Без FEAT-NNN директории!** Одна строка в `devlog/YYYY-MM-DD.md` · §8 гигиена всё равно действует |
| **Поднять систему / e2e / проверить** | `ops/local-setup.md` + [`guides/live-acceptance.md`](guides/live-acceptance.md) | `Laravel app :80 (Sail APP_PORT), Vite :5173, MySQL 8 :3306, Redis :6379, Mailpit :8025; Filament — /admin` — см. ops/local-setup |
| **Работа над САМОЙ системой** (coord-скрипты, гайды, инфраструктура агентов — артефакты вне клиентских реп) | [`devlog/features/README.md`](devlog/features/README.md) §Маппинг | Брони `coord.sh book` НЕ создаются · FEAT-номера резервируются диапазоном в таблице маппинга · при крупной инициативе → [`guides/adr-execution.md`](guides/adr-execution.md) |
| **Параллельная работа при живых соседях** (брони, изоляция окружений, гейты) | [`guides/coordination.md`](guides/coordination.md) | Присутствие + брони FEAT/ADR (`coord.sh`) · окружение изолируй вручную (эфемерная БД Sail / `.env.testing`, свой порт) · тяжёлые гейты сериализуй (`gate.sh`) |
| **Research / спайк / PoC** (изучение библиотеки, эмпирическая проверка гипотезы — НЕ фича) | [`research/README.md`](research/README.md) | Не ADR и не фича · привело к решению → ADR; превратилось в реализацию → `devlog/features/FEAT-NNN-*/` |
| **Подхват чужой недоделанной работы после ротации** | ADR-инициатива → [`guides/adr-execution.md`](guides/adr-execution.md) Часть F (handoff) · одиночная фича → бронь/статус + `spec.md`/`impl.md` фичи | Продолжай по `feature-workflow.md` от текущего состояния, не с нуля · §8 гигиена действует |
| **Создаёшь НОВЫЙ док** (куда положить?) | правило размещения — [`ops/README.md`](ops/README.md) | Среда/эксплуатация → `ai/ops/` · методология → `ai/guides/` · решение → `ai/adr/` · инфра клиента → `ai/infra/` · статус → `ai/memory.md` |

> **Субагенты — делегируй ради экономии контекста ⚠️**
> Главный/оркестраторский контекст ограничен и переполняется (к ~10-й фиче крупной инициативы). Делегируй субагентам работы, порождающие много «шума», и держи у себя только выводы. Делегируй: каждую фичу крупной ADR-инициативы; широкий поиск/разведку по многим файлам (read-only Explore-агент); независимые куски; ревью/перепроверку/живую приёмку. Субагент возвращает **сжатую сводку** — её и держи в контексте. Мелкие правки в 1–2 файла делай сам.
>
> **⚠️ Ресурсы при параллели.** Параллельные фичи (каждая в своём `tasks/<slug>` worktree) — это про **изоляцию файлов**, но тяжёлые гейты (тесты/сборка/typecheck) нескольких субагентов бьют по **общей** RAM/CPU одной машины — вплоть до OOM. Правило: фичи параллелят, **тяжёлые гейты — сериализуй**. Параллельность агентов ⊥ параллельность тяжёлых прогонов.
> **Имена ресурсов `gate.sh` (конвенция — совпадать обязательно, иначе два агента на одной операции не сериализуются):** `build | test | migrate` (напр. `backend-tests`, `frontend-build`, `typecheck`, `coverage`, `migrate-shared`, …). `gate.sh` exit `75` = queue-timeout/**REQUEUE** (лок не взят за `GATE_WAIT`) — «занято, повтори», НЕ красный гейт.

### Держи память и обзор актуальными

- **После правки `memory.md`** (новая запись инициативы или gotcha) — обнови TOC-блок (`MEMORY-TOC-START…END`) вручную.
- **После значимых изменений** — прогони «гейт актуальности» этого файла (см. «Всегда» ниже, п.5).

> **Правило выбора модели для субагентов ⚠️ (правило проекта)**
> При запуске ЛЮБОГО субагента **ЯВНО указывай модель** — не оставляй дефолт. Два яруса:
> - **`Sonnet 5` — рутина:** механические правки по готовому брифу, разведка/поиск по коду, сбор фактов, прогон тестов/гейтов, доки по шаблону, чек-листы, форматирование, массовые однотипные операции.
> - **`Opus 4.8` — всё сложное:** проектирование/архитектура, авторинг ADR и спеков, нетривиальная реализация, адверсариальное ревью и верификация инвариантов, security-анализ, дебаг с неизвестной причиной, живая приёмка, «ревью чистоты» (§8).
> - **Сомневаешься, рутина это или нет — бери `Opus 4.8`.** Правило распространяется и на вложенных агентов.

### Всегда (сквозные правила — чаще всего забывают)

1. **Свежий worktree → Step-0 sync:** fetch+merge базиса `develop` → восстановить зависимости → (при необходимости) миграции → **вердикт одной строкой**. Нет пререквизита = сталый базис, НЕ «фича не начата». Команды — `# ADAPT: stack-specifics ./scripts/sync.sh && ./scripts/status.sh`.
2. **Framework-first:** прежде чем писать инфраструктуру руками — проверь, что её нет во фреймворке стека.
3. **Покрытие тестами + живая приёмка = часть DoD.** Для нового кода — негативные тесты на права и на чувствительные данные обязательны.
4. **Крупная/шумная работа — через субагентов.**
5. **Держи этот файл актуальным:** после значимых изменений — обнови §10 (ADR-таблица), §3–§5 (структура/модули), §0 (если добавился новый тип работы). Спроси: «изменила ли фича то, что этот файл описывает как ФАКТ?»
6. **Trivial-fix не через FEAT-NNN** — канал = `devlog/YYYY-MM-DD.md`.

7. **§8 «Гигиена клиентского репозитория» действует ВСЕГДА** — включая quickfix. Коммит в клиентскую репу → только `scripts/commit.sh`; push → только пользователь.

> Глубже: разделы **1–11** — справочник по подсистемам · `adr/` — «почему» · `guides/` — «как» · `memory.md` — «текущий статус» · `devlog/features/` — «что сделано».

---
## 1. Концепция

cbook — кулинарная книга (cookbook): веб-приложение для ведения и организации рецептов. Пользователь заводит рецепты (ингредиенты, шаги приготовления, изображения) и находит их по каталогу. Аудитория — домашние кулинары, ведущие личную коллекцию рецептов. Легаси-версия существует на **Nuxt 4 (Prisma + PostgreSQL/Neon)** — это **донор идеи и BVI-панели, а не образец для порта**; **north star проекта** — **переписывание cbook с нуля ради обучения** сборке enterprise-**монолитов на Laravel** (стиль референс-проектов `listvafintess`/`av1`) на стек **Laravel 12 + Filament 5 + Inertia/Vue** в **строгой слоистой архитектуре** (поток Request→Controller→Task→Repository→DTO→Resolver→Inertia). cbook — учебный полигон, не продукт: сохраняем общую идею (кулинарная книга) + BVI-панель, остальное строим заново, дыры Nuxt-версии чиним. См. `memory.md` (ведущий контекст + 5 STRICT RULES), ADR-002/003/006 и `../local/PROJECT-BRIEF.md` (локальный, вне git).

### Ключевые сущности

Доменная модель по ТЗ заказчика (`steps` — JSON-массив строк внутри Recipe; `ingredients` — отдельная таблица `hasMany`):

| Сущность | Поля (ТЗ) | Где живёт |
|----------|-------|--------------------------|
| Recipe (Рецепт) | id, title, description, cooking_time (int), servings (int), difficulty (Enum `low\|medium\|high`), **steps (JSON-массив строк)**, created_at, updated_at | Eloquent-модель `app/Models/Recipe` (доступ — только из Repository) |
| Ingredient (Ингредиент) | id, recipe_id (FK→Recipe, **cascade delete**), name, quantity (float), unit (string) | Eloquent-модель `app/Models/Ingredient`, связь `hasMany` от Recipe |
| User (Пользователь) | Владелец рецептов; аутентификация (Laravel auth) | `app/Models/User` + Policies |

> `steps` не имеет собственного id/ЖЦ — это JSON-колонка Recipe. `ingredients` — отдельная таблица (`hasMany`, каскадное удаление по recipe_id). Категории/Step как отдельные сущности в ТЗ **не заданы** — при появлении фиксировать здесь по факту.

### Принципы системы (5 STRICT RULES ТЗ + сквозные)

1. **`declare(strict_types=1)` в каждом `.php`.** Обязательная первая строка (`<?php declare(strict_types=1);`).
2. **Изоляция Eloquent.** `Eloquent\Model` и фасад `DB` — ТОЛЬКО в `app/Data/Repositories/*`; контроллеры/Tasks/Resolvers/Vue напрямую Eloquent не трогают. Нарушение = ошибка **PHPStan Level 10**.
3. **Единый поток данных.** Request (FormRequest) → Controller → Task → Repository → DTO (Spatie Data) → Page Resolver → Inertia Vue Page. **Наружу — только DTO** (никаких сырых моделей/массивов Eloquent).
4. **Именование слоёв по каталогам.** Бизнес-операция = Task (`app/Tasks`); сборка пропсов = Resolver (`app/Resolvers/Page`); запросы к БД = Repository (`app/Data/Repositories`).
5. **Framework-first + root-cause + безопасность по владельцу.** Готовое искать в Laravel/пакетах; баг-фикс закрывать регрессионным тестом; рецепты изолированы по владельцу (Policies + негативные тесты на защищённые пути).
6. **Единый источник команд/версий стека** — [`guides/stack-specifics.md`](guides/stack-specifics.md); документация не дублирует значения из скриптов.

---

## 2. Технологический стек

> **Скелет-опросник.** Структура секции стабильна; наполнение — под проект. Команды/версии — единый источник в [`guides/stack-specifics.md`](guides/stack-specifics.md).

### Runtime и инструменты
- **Backend runtime:** PHP **8.4** (Laravel **12**); зависимости — Composer; локальное окружение — Laravel Sail (Docker).
- **Frontend runtime:** Node + TypeScript **strict** (Vite); пакетный менеджер — pnpm.
- **Репозитории:** одна клиентская репа `cbook` (моно); единая база знаний `ai/` (репозиторий study-cbook-ai) покрывает её.

### Backend
- **Фреймворк:** Laravel **12** (PHP **8.4**), строгая слоистая архитектура — поток Controller → Task → Repository → DTO → Resolver (см. §4, ADR-003).
- **БД / ORM:** **MySQL 8** (Sail-сервис `mysql`, порт 3306); Eloquent — **только внутри `app/Data/Repositories/*`** (изоляция enforced PHPStan L10).
- **Слой данных:** Spatie **Laravel Data** (DTO) + автогенерация TS-типов (`artisan typescript:transform`).
- **Медиа:** `whyme-agency/laravel-media` (изображения рецептов).
- **Auth:** Laravel auth (сессии); авторизация через Policies.
- **Очереди / кэш:** Redis (Sail) — как есть.
- **Админка:** Filament **5** (`/admin`).
- **Тесты / типы / линт:** **Pest PHP** · PHPStan **Level 10** (Larastan) · Laravel Pint (PSR-12, `declare_strict_types`).

### Frontend
- **Фреймворк:** Inertia.js + Vue 3 (`<script setup>`, TypeScript **strict**) + **Tailwind CSS** (Vite).
- **UI / состояние / слой данных:** SFC-компоненты Vue; состояние — composables/stores; наружу приходят **только DTO** (Spatie Data) через props Inertia, без прямого fetch на чужие хосты. TS-типы DTO — автоген `artisan typescript:transform`.
- **Тесты / типы / линт:** (тесты — при необходимости Vitest) · `vue-tsc` (strict) · ESLint.

### Инфраструктура и деплой
- **Деплой / CI:** ветка `develop` (интеграционная) → merge в `main` = деплой; доставку и push делает пользователь.
- **Таймзона:** хранение времени в UTC, вывод — по локали пользователя (уточняется при переписывании).
- **Локальный стенд:** Laravel Sail (Docker) — app :80, Vite :5173, **MySQL 8 :3306**, Redis :6379, Mailpit :8025 (детали — `ops/local-setup.md`).
- **Legacy-инфраструктура (Nuxt-контур, донор идеи+BVI):** Prisma + PostgreSQL(Neon), MinIO(S3), Cloudflare Tunnel — служит референсом и **замещается** переписанным Laravel-приложением (не работает как параллельный продукт). В целевом стеке схема пишется заново под MySQL 8, медиа — через `whyme-agency/laravel-media`.

---

## 3. Структура workspace

`study-cbook-ai/` — рабочее пространство (**НЕ единый репозиторий**). Внутри — git-worktree клиентских реп + внутренний репозиторий базы знаний (папка `ai/`).

```
study-cbook-ai/                  # workspace (не репозиторий)
├── ai/                       # 🧠 study-cbook-ai: ЭТА база знаний (внутренний git-репо, отдельный origin)
├── .repos/                   # bare-клоны клиентских реп (руками не трогать)
├── cbook/        # worktree интеграционной ветки develop — ОСНОВНАЯ рабочая копия
├── prod/        # worktree main — прод (read-only, сравнение/хотфиксы)
├── tasks/<slug>/             # worktree на задачу (создаётся ./scripts/task.sh new <slug>)
├── local/                    # docker-compose, секреты (team.env), логи (гитигнор)
└── scripts/                  # обвязка (зона оркестратора — часть агенту не менять)
```

> **`ai/` внутри:** `guides/` (методология) · `adr/` (решения) · `devlog/` (журнал фич) · `ops/` (операторские/средовые доки — правило в `ops/README.md`) · `research/` · `coord/` (runtime координации) · `architecture.md` · `memory.md`.

> Имена папок верхнего уровня — контракт из правил клиента (`CLAUDE.md`) и скриптов. **Не переименовывать.** Двухконтурная модель: база знаний живёт в отдельном репозитории вне кода клиента (ADR-001).

---

## 4. Ключевые модули / сервисы

> Целевая раскладка слоёв Laravel по ТЗ — **конкретный поток**, не абстрактные Domain/Application/Infrastructure. Направление одностороннее: Controller → Task → Repository → DTO → Resolver → Inertia.

### Backend
| Слой / модуль | Роль | Путь | Eloquent/`DB`? |
|--------|------|------|---|
| FormRequest | Вся серверная валидация входа | `cbook/app/Http/Requests/...` | нет |
| Controller | Тонкий: FormRequest → Task/Resolver → Inertia-ответ | `cbook/app/Http/Controllers/...` | нет |
| Task | Одна бизнес-операция (`CreateRecipeTask`) | `cbook/app/Tasks/...` | нет |
| Repository | Запросы к БД — **единственное место** Eloquent/`DB` | `cbook/app/Data/Repositories/...` | **ДА (только здесь)** |
| DTO (Spatie Data) | Форма данных наружу; источник TS-типов (`typescript:transform`) | `cbook/app/Data/...` | нет |
| Page Resolver | Сборка пропсов Inertia-страницы из DTO (`RecipeDetailResolver`) | `cbook/app/Resolvers/Page/...` | нет |
| Eloquent-модели | `Recipe`, `Ingredient`, `User` — используются только из Repository | `cbook/app/Models/...` | — |
| Enums | Домен-enum'ы (`Difficulty`) | `cbook/app/Enums/...` | нет |
| Admin (Filament 5) | Панель `/admin`: Resource'ы без бизнес-логики (делегируют в Task/Repository) | `cbook/app/Filament/...` | делегируют |

> **Инвариант изоляции Eloquent:** любой `Eloquent\Model`/фасад `DB` вне `app/Data/Repositories/*` = ошибка PHPStan Level 10. Наружу (в Task/Controller/Resolver/Inertia) ходят **только DTO**.

### Frontend
Слои Inertia/Vue: страницы (`resources/js/Pages/`, Vue 3 `<script setup>` + TS strict, роут = Inertia-страница) → компоненты (`resources/js/Components/`) → composables/stores (состояние) → **DTO-типы (автоген `artisan typescript:transform`)**. В props приходят **только DTO** со стороны Resolver'а (сервер как слой-прокси); стили — **Tailwind CSS**-утилиты, не хардкод-литералы.

---

## 5. Схема БД

> **Скелет-опросник (рубрика).** Опиши контуры БД и тестовую цепочку — даже если БД одна.

- **Базы/контуры:** одна БД **MySQL 8**. Локальный адрес — сервис `mysql` в Sail (`DB_CONNECTION=mysql`, `DB_HOST=mysql`, `:3306`). Legacy Nuxt-версия использовала Neon (managed Postgres) через Prisma — это референс; при переписывании **схема создаётся заново** под Laravel-миграции в Sail-MySQL (не перенос Prisma-схемы; исторические Prisma-миграции неприменимы).

  | База | Алиас/env | Назначение | Локальный адрес |
  |------|-----------|------------|-----------------|
  | cbook (основная) | `DB_HOST=mysql`, `DB_PORT=3306` | Рецепты, ингредиенты, пользователи | Sail `mysql:3306` |
  | тестовая | `.env.testing` | Прогон Pest (RefreshDatabase) | эфемерная (пересоздаётся) |

- **Доменная схема (ТЗ):**

  | Таблица | Колонки | Заметки |
  |---|---|---|
  | `recipes` | id, title, description, cooking_time (int), servings (int), difficulty (enum `low\|medium\|high`), **steps (JSON)**, created_at, updated_at | `steps` — JSON-массив строк (нет своего id/ЖЦ); хранится в самой таблице рецепта |
  | `ingredients` | id, recipe_id (FK→recipes, **ON DELETE CASCADE**), name, quantity (float/decimal), unit (string) | Связь `Recipe hasMany Ingredient`; удаление рецепта каскадит ингредиенты |

- **Миграции:** источник схемы — Laravel-миграции (`database/migrations/`, `artisan migrate`). Правило для нового кода: любое изменение схемы — через миграцию (не руками в БД); порядок создания сущности — миграция первой (см. stack-specifics §Backend). `steps` кастуется в модели как array (JSON-колонка), `difficulty` — как Enum. Грабли переноса Postgres→MySQL и Prisma→Laravel фиксируются в `memory.md` §Gotchas по мере миграции.
- **Контуры dev-БД + тестовая цепочка:** dev — локальный Sail-Postgres; тесты — эфемерная БД по `.env.testing` с `RefreshDatabase`. Детали — [`guides/stack-specifics.md`](guides/stack-specifics.md) §Тесты.

---

## 6. Клиентская часть

Единственный поддерживаемый UI — SPA-подобный интерфейс на Inertia/Vue 3 (сервер отдаёт Inertia-страницы, данные приходят props'ами; отдельного публичного REST-API для клиента нет). Админ-функции — через Filament-панель `/admin`. Публичного help-центра у продукта на момент инициализации нет; правило пользовательской документации: любое user-visible изменение отражать в клиентском `CLAUDE.md` / README проекта и фиксировать строкой в `impl.md` фичи (`updated … / checked, no changes needed because … / needs product-owner review …`).

---

## 7. Деплой и инфраструктура

> **Скелет-опросник.** Модель веток и доставки клиента.

- **Ветки:** `develop` (интеграционная) → merge в `main` = деплой (прод). Наша доставка: ветка `feat/<slug>` → MR в `develop` (создаёт пользователь). CI-статус на интеграционной ветке — (уточнить: настроен ли pipeline на стороне клиента); деплой триггерится merge'ем в `main`.
- **Доставка агентской работы (инвариант):** агент оставляет работу **локальным коммитом** в ветке `tasks/<slug>` (через `scripts/commit.sh`), проверенным гейтами. **`git push` и merge — только пользователь.** «✅ готово» = смерженный MR + зелёные локальные гейты (см. `guides/feature-workflow.md` Шаг 12).
- **Локальный стенд:** `ops/local-setup.md` (`Laravel app :80 (Sail APP_PORT), Vite :5173, MySQL 8 :3306, Redis :6379, Mailpit :8025; Filament — /admin`).

---

## 8. Безопасность

### Аутентификация и авторизация
Механизм аутентификации — Laravel auth (сессии). Авторизация — через Policies и Gate. Правила: новый защищённый маршрут/действие → явная проверка прав (Policy/authorize) **до** бизнес-логики; рецепты и связанные данные изолированы по владельцу (пользователь видит/меняет только своё); Filament-панель `/admin` закрыта политиками доступа. На каждый защищённый путь — обязательные **негативные** тесты (чужой пользователь / без прав → отказ). Capability-проверки сквозные: backend-право ↔ доступность действия в UI.

### Секреты
- Секреты — только в `.env`/`local/*.env` (chmod 600), **не коммитить** (`.gitignore` базы знаний блокирует `*.env`). В логах — нет токенов/паролей/чувствительных данных.
- Боевые креды (БД, S3/MinIO, API-токены, Cloudflare Tunnel) из `.env` — наружу не выносить и в тестах не использовать; тесты — на `.env.testing` с `test_*`-значениями.

### 🔒 Гигиена клиентского репозитория (режим секретности) ⛔

Клиентские репозитории (`cbook`) не должны нести **НИ ОДНОГО следа** этой системы разработки. Жёсткое правило, повторено в каждом гайде и брифе.

- **Ноль упоминаний** в коде, коммитах, ветках, MR: этой системы (`ai/`, `study-cbook-ai`), FEAT-номеров, спеков, агентов/ИИ, оркестраторов, названий внутренних гайдов.
- **Постоянные комментарии в коде** — только «как писал бы человек»: по стилю окружающего кода, объясняют ограничение/логику; без ссылок на внутренние документы/FEAT/спеки.
- **Рабочие (временные) пометки** в коде — ТОЛЬКО с маркером `~wip~`. Перед завершением фичи ВСЕ `~wip~` удаляются; pre-commit хук блокирует их физически.
- **Коммиты в клиентские репы — ТОЛЬКО через `scripts/commit.sh`** (обёртка с гейтами и сканером следов). `git push` агентам запрещён всегда — доставку делает пользователь.
- **Имена веток** — стиль команды: `feat/<понятный-slug>` без номеров. Маппинг FEAT ↔ ветка — в [`devlog/features/README.md`](devlog/features/README.md).
- **Сообщения коммитов** — формат команды: `<type>: <описание> (conventional commits; type ∈ feat|fix|chore|refactor|docs|test|style|perf|build|ci)`. Канонический список PREFIX — в `scripts/commit.sh` (`FORMAT_RE`); при расхождении верно то, что в `FORMAT_RE`.
- **Финальный DoD-шаг «ревью чистоты»:** свежий субагент **без доступа к `ai/`** читает `git diff` как внешний ревьюер и ищет следы системы / несоответствие стилю репо.

---

## 9. Документация проекта

> **Скелет-опросник.** Источники: операторские заметки `ai/ops/`; правила клиентского репо `CLAUDE.md`; dev-доки клиента; публичная дока/help-центр.

### Правило публичной доки (user-visible изменения отражать в клиентском CLAUDE.md / README проекта)
Публичного help-центра у cbook на момент инициализации нет. Правило: любое user-visible изменение → (1) проверить клиентские `CLAUDE.md`/README на актуальность, (2) обновить при изменении поведения, (3) в `impl.md` фичи явно писать одно из: `updated … / checked, no changes needed because … / needs product-owner review …`.

### AI-context (эта база)
- `architecture.md` (этот файл), `memory.md`, `guides/`, `adr/`, `devlog/features/`, `process-metrics/`, `research/`.

---

## 10. ADR (Architecture Decision Records)

Реестр решений со статусами. **Механизм таблицы стабилен**; строки наполняются под проект. Системные ADR методологии (номера сохранены) — в [`adr/README.md`](adr/README.md).

| # | Статус | Решение | Файл |
|---|--------|---------|------|
| 001 | Системный | Агентская система: сепарация + git-броня + клетка возможностей (M6) | [`adr/001-agent-dev-system.md`](adr/001-agent-dev-system.md) |
| 004 | Системный | Worktree-процесс через `task.sh` (ветка = задача) | [`adr/004-worktree-task-process.md`](adr/004-worktree-task-process.md) |
| 009 | Системный | Per-commit rationale (разбор «почему» на коммит) | [`adr/009-per-commit-rationale.md`](adr/009-per-commit-rationale.md) |
| 010 | Системный | Обязательное независимое ревью каждого коммита | [`adr/010-mandatory-commit-review.md`](adr/010-mandatory-commit-review.md) |
| 002 | Принят | Целевой стек: Laravel 12 + PHP 8.4 + MySQL 8 + Filament 5 + Inertia/Vue 3 (TS strict) + Spatie Data + Tailwind, Sail | [`adr/002-stack-laravel-filament-inertia.md`](adr/002-stack-laravel-filament-inertia.md) |
| 003 | Принят | Строгая слоистая архитектура (Controller→Task→Repository→DTO→Resolver→Inertia; Eloquent только в `app/Data/Repositories/*`, enforced PHPStan L10) | [`adr/003-layered-architecture.md`](adr/003-layered-architecture.md) |
| 006 | Принят | Переписывание cbook с нуля на Laravel ради обучения (greenfield; Nuxt = донор идеи+BVI) | [`adr/006-migration-nuxt-to-laravel.md`](adr/006-migration-nuxt-to-laravel.md) |
| 011 | Реализован | Граница Filament-админки и изоляции Eloquent (подход C: чтение модели в `App\Filament`, мутации через Tasks; allow-list rule #1 += `App\Filament`, `DB`-guard сохранён; супер-доступ админа через `RecipePolicy::before`) | [`adr/011-filament-admin-boundary.md`](adr/011-filament-admin-boundary.md) |

> Свободные номера 012 и далее — под будущие продуктовые ADR (007…010 заняты; 011 — Filament-граница). Номера 005/008 исторически занимали системные ADR отключённых модулей (M5/M3) и не переиспользуются. Системные ADR (001/004/009/010) не перенумеровывать.

Детали — в [`adr/`](adr/).

---

## 11. Быстрый чеклист для AI-ассистента

Перед началом работы:

1. Прочитать этот файл (`architecture.md`), особенно §0 (роутер) и §8 (гигиена).
2. Прочитать `memory.md` — что сделано, открытые задачи.
3. Новая фича → `guides/feature-workflow.md` (+ изоляция `./scripts/task.sh new <slug>`).
4. Backend → `guides/stack-specifics.md` §Backend + `CLAUDE.md`.
5. Frontend → `guides/stack-specifics.md` §Frontend.

7. Любой код в клиентскую репу → §8 (гигиена) + коммит через `scripts/commit.sh`.
