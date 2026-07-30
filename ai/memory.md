# cbook — Memory (текущий статус)

> **Для AI-ассистента:** это рабочая память проекта. Обновляется **после каждой завершённой фичи** (см. `guides/feature-workflow.md`, Шаг 10).
> Читается вместе с `architecture.md` **перед любой работой**.

<!-- MEMORY-TOC-START -->
<!-- Оглавление между маркерами MEMORY-TOC-START/END. Одна строка на значимую запись/инициативу/gotcha
     со ссылкой-якорем, в порядке добавления. Скрипт-генератор пока НЕ подключён — держи блок вручную. -->
- [North Star и целевой стек (ведущий контекст)](#north-star-и-целевой-стек-ведущий-контекст)
- [Актуальный срез](#актуальный-срез)
- [Реализовано](#реализовано)
- [Открытые задачи / бэклог](#открытые-задачи--бэклог)
- [Архитектурные решения (кратко)](#архитектурные-решения-кратко)
- [Gotchas](#gotchas)
- [Счётчики](#счётчики)
<!-- MEMORY-TOC-END -->

> **Конвенции файла (важно):**
> - **Append-only.** Записи не переписываются задним числом — новые события добавляются, старые остаются как история. Правки только фактических ошибок.
> - **TOC-first дисциплина чтения.** Сначала читай оглавление выше, затем прыгай в нужную запись.
> - **Кто пишет.** В делегированном режиме `memory.md` пишет **оркестратор при закрытии инициативы** (субагент отдельной фичи пишет в `impl.md` + живой документ ADR, не сюда). В **соло-режиме** запись делает **сам исполнитель при закрытии фичи**.
> - **Две формы записи.** (1) *Запись инициативы* — итоги закрытого ADR/блока. (2) *Gotcha* — короткая durable-заметка о грабле.
> - **После добавления записи — обнови оглавление вручную** (скрипт-генератор пока не подключён).

---

## North Star и целевой стек (ведущий контекст)

> Это **ведущий контекст всего проекта** — читается перед `Актуальным срезом`. Источник истины — уточнённое ТЗ заказчика (2026-07-28).

**Общая цель (north star):** **переписывание cbook с нуля ради обучения** — владелец осваивает сборку enterprise-**монолитов на Laravel** (стиль референс-проектов `listvafintess`/`av1`) на **стеке Laravel 12** в **строгой слоистой архитектуре** (Request → Controller → Task → Repository → DTO → Resolver → Inertia). cbook — **подопытный кролик**, не продукт. Сохраняем только **общую идею** (кулинарная книга) и **специфичные блоки — прежде всего BVI-панель**. Legacy **Nuxt 4 / Prisma / PostgreSQL(Neon)** = **донор идеи и BVI, а не образец для порта**; он **замещается**, а не развивается параллельно. Дыры Nuxt-версии (нет auth, нет серверной валидации, утечки, небезопасная загрузка) — **чинить, не воспроизводить**. Подробная рамка — `../PROJECT-BRIEF.md`.

**Целевой стек (ТЗ, отменяет прежние дефолты):**
- **Backend:** PHP **8.4** + Laravel **12** + MySQL **8**.
- **Frontend:** Inertia.js + Vue 3 (`<script setup>`, TypeScript **strict**) + Tailwind CSS.
- **Слой данных:** Spatie **Laravel Data** (DTO) + автогенерация TS-типов (`artisan typescript:transform`).
- **Админка:** Filament **5**. **Медиа:** `whyme-agency/laravel-media`.
- **Качество:** PHPStan **Level 10** + Laravel Pint (PSR-12, `declare_strict_types`). Тесты — **Pest PHP**.
- **Локально:** Laravel **Sail** (Docker); СУБД — MySQL 8 (Sail-сервис `mysql`, порт 3306); инструмент — `./vendor/bin/sail`.

**5 STRICT RULES (нарушение слоёв = ошибка PHPStan Level 10):**
1. Каждый `.php` начинается с `<?php declare(strict_types=1);`.
2. **Изоляция Eloquent:** `Eloquent\Model` и фасад `DB` — ТОЛЬКО внутри `app/Data/Repositories/*`. Контроллеры / Tasks / Resolvers / Vue напрямую Eloquent НЕ вызывают.
3. **Поток данных:** Request (FormRequest) → Controller → Task (бизнес-логика) → Repository (запрос к БД) → DTO (Spatie Data) → Page Resolver → Inertia Vue Page.
4. В Inertia/Vue передаются **ТОЛЬКО DTO (Spatie Data)** — никаких сырых моделей/массивов Eloquent.
5. **Слои-именование:** одна бизнес-операция = один Task (`app/Tasks/CreateRecipeTask.php`); сборка пропсов страницы = Resolver (`app/Resolvers/Page/RecipeDetailResolver.php`); запросы к БД = Repository (`app/Data/Repositories/RecipeRepository.php`).

**⚠️ Прежние дефолты ОТМЕНЕНЫ ТЗ:** было Laravel 11 / PHP 8.3 / PostgreSQL / Filament 3 → стало Laravel 12 / PHP 8.4 / MySQL 8 / Filament 5. **Открытый вопрос по СУБД снят** — MySQL 8 (Sail-сервис `mysql`, порт 3306). Слоёв «Domain/Application/Infrastructure» больше нет — их заменяет конкретный поток Task/Repository/DTO/Resolver (см. ADR-003).

**Доменная модель (ТЗ):**
- `Recipe`: id, title, description, cooking_time (int), servings (int), difficulty (Enum `low|medium|high`), steps (**JSON-массив строк**), created_at, updated_at.
- `Ingredient`: id, recipe_id (FK→Recipe, cascade delete), name, quantity (float), unit (string).
- `steps` — JSON-колонка (нет своего id/ЖЦ); `ingredients` — отдельная таблица `hasMany`.

---

## Актуальный срез

**Дата последнего обновления:** 2026-07-30
**Текущая среда:** локальная разработка (Laravel Sail / Docker через OrbStack; MySQL 8, сервис `mysql:3306`); интеграционная ветка — `develop`
**Основной фокус:** запущено переписывание cbook на Laravel. **FEAT-002 (greenfield-скелет 1a) — DONE** + **FEAT-003 (активация Pint / строгая типизация по базе) — DONE**: enterprise-каркас слоёв (`BaseTask`/`BaseRepository`, Data/Tasks/Resolvers) и QA-тулчейн (Pint psr12+strict, Larastan L10, Pest arch-барьер) заложены и **реально работают** — вскрыт и починен дефект FEAT-002 (конфиг Pint был `.pint.json`, молча инертен → `git mv` в `pint.json`). Легаси Nuxt 4 вынесен в `local/legacy_nuxt/` (донор идеи+BVI, не образец для порта).
**Следующее:** доставка FEAT-002 (`9f4b857`) и FEAT-003 (`2038821`) в git клиента — за владельцем (`deliver.sh cbook feat/laravel-skeleton` и `deliver.sh cbook feat/enterprise-skeleton` → PR в `develop`). Далее — задача 1b/следующие шаги переписывания (домен Recipe/Ingredient, миграции MySQL 8, Filament 5, Inertia/Vue, media). При старте крупной инициативы — включить process-retro (M7).

---

## Реализовано

> Состояние инфраструктуры/окружения и системы разработки, а также закрытые фичи/инициативы.

<!-- Формат записи инициативы: краткий итог + ключевые контракты/gotchas + ссылка на ADR/impl. -->
- **Инициализация базы знаний `ai/`** (2026-07-28): развёрнута двухконтурная система (study-cbook-ai вне кода клиента). Профиль: M1/M2/M6 ON, M7 отложен, M3/M4/M5/M8/M9 off. Зафиксированы стартовые ADR-002/003/006.
- **FEAT-002 — greenfield-скелет Laravel 12 (задача 1a)** (2026-07-29): в `feat/laravel-skeleton` (коммит `9f4b857`) развёрнут чистый Laravel **12.64** (pinned) / PHP **8.4.23** / MySQL 8 через Sail (OrbStack). Enterprise-каркас: `app/Tasks/BaseTask.php` (`handle(): mixed`), `app/Data/Repositories/BaseRepository.php`, пустые слои `app/Data/`, `app/Resolvers/Page/` (`.gitkeep`). QA-инварианты: Pint (psr12 + `declare_strict_types`), Larastan **L10** (No errors), Pest **arch-барьер** изоляции Eloquent/DB по слоям (доказан red→green). Пакеты: `spatie/laravel-data` (prod); larastan/pest (dev). Legacy Nuxt → `local/legacy_nuxt/`. Детали — `devlog/features/FEAT-002-laravel-skeleton/impl.md`; разбор коммита — `devlog/commits/cbook/9f4b857-laravel-skeleton.md`. Исполнение под ADR-002/003/006, новых ADR не вводит. Доставка в git клиента — за владельцем. ⚠ Правка: заявленный тут Pint psr12+strict фактически был инертен — исправлено FEAT-003.
- **FEAT-003 — активация Pint / строгая типизация по базе** (2026-07-30): в `feat/enterprise-skeleton` (коммит `2038821`) вскрыт и починен дефект FEAT-002 — конфиг Pint назывался `.pint.json` (с точкой), Pint автообнаруживает только `pint.json` → правила `psr12`+`declare_strict_types` **молча не применялись**, часть framework-кода была без `strict_types`. Починка: `git mv .pint.json → pint.json` + `sail bin pint` по всей базе (29 файлов, +62/−8, только форматирование). Доказано: Larastan **L10** No errors без baseline; Pest arch-барьер red→green (PoC с DummyTask); полный pest **4 passed**. Детали — `devlog/features/FEAT-003-enterprise-skeleton/impl.md`; разбор — `devlog/commits/cbook/2038821-enterprise-skeleton.md`. Новых ADR не вводит. Доставка в git клиента — за владельцем.

---

## Открытые задачи / бэклог

- [ ] Переписывание cbook с нуля на Laravel 12 + Filament 5 + Inertia/Vue ради обучения (крупная инициатива, ADR-006; Nuxt = донор идеи+BVI). При старте — включить process-retro (M7).
  - [x] ~~Задача 1a — greenfield-скелет (FEAT-002)~~ — DONE (коммит `9f4b857`, доставка за владельцем).
  - [x] ~~Задача — enterprise-барьеры / активация Pint (FEAT-003)~~ — DONE (коммит `2038821`, доставка за владельцем).
  - [ ] Задача 1b и далее — домен Recipe/Ingredient, миграции MySQL 8, Filament 5, Inertia/Vue, media.
- [ ] Уточнить у владельца: CI на `develop` (настроен ли pipeline); дисковый драйвер для `whyme-agency/laravel-media` (локальный/S3) — `(уточнить)`.
- [x] ~~Финальный выбор СУБД~~ — снят ТЗ: **MySQL 8** (Sail-сервис `mysql`, порт 3306).

---

## Архитектурные решения (кратко)

> Одна-две строки на решение + ссылка на карточку `adr/NNN-*.md`. Полное «почему» — в ADR, здесь — навигация.

- ADR-002 — целевой стек Laravel 12 + PHP 8.4 + MySQL 8 + Filament 5 + Inertia/Vue 3 (TS strict) + Spatie Data + Tailwind, Sail → `adr/002-stack-laravel-filament-inertia.md`
- ADR-003 — строгая слоистая архитектура (поток Request→Controller→Task→Repository→DTO→Resolver→Inertia; изоляция Eloquent в `app/Data/Repositories/*`, enforced PHPStan L10) → `adr/003-layered-architecture.md`
- ADR-006 — переписывание cbook с нуля на Laravel ради обучения (greenfield; Nuxt = донор идеи+BVI, замещается) → `adr/006-migration-nuxt-to-laravel.md`
- Системные ADR методологии (001/004/009/010) — см. `adr/README.md`.

---

## Gotchas

> Короткие durable-заметки о граблях (класс проблемы + как обойти). Расширяется по мере набивания шишек.

- **БД: схема пишется ЗАНОВО под MySQL 8 (не перенос Postgres→MySQL).** Целевая СУБД — **MySQL 8** в Sail (сервис `mysql`, `DB_CONNECTION=mysql`, `DB_HOST=mysql`, `:3306`). Схема создаётся с нуля под Laravel-миграции (`database/migrations`) — это переписывание, а не перенос Prisma-схемы; исторические Prisma-миграции неприменимы. Legacy Neon Postgres — только референс. Прежний дефолт (Sail Postgres/`pgsql:5432`) отменён.
- **Медиа: whyme-agency/laravel-media (не прямой s3).** Изображения рецептов в целевом стеке идут через пакет `whyme-agency/laravel-media`, а не через ручной драйвер `s3`. Дисковый драйвер (локальный/S3) — `(уточнить)`. Legacy-изображения лежали в MinIO (S3-совместимо); боевые креды из `.env` в тесты не тащить.
- **Cloudflare Tunnel.** Внешний доступ к legacy dev-стенду шёл через Cloudflare Tunnel. При Sail-стенде уточнить, нужен ли туннель; секреты туннеля — только в `.env`, наружу не выносить.
- **Дыры Nuxt-версии — чинить, не воспроизводить.** В легаси нет auth, нет серверной валидации, ошибки текут наружу, небезопасная загрузка файлов. При переписывании auth+серверная валидация вводятся сразу; порт 1:1 этих дыр запрещён (Nuxt = донор идеи+BVI, не образец).
- **process-retro (M7) отложен** — включить при первой крупной инициативе (переписывание на Laravel).
- **`laravel.build`/`laravel new` даёт ПОСЛЕДНЮЮ мажорную (на 2026 — вероятно 13), не 12.** Для целевого Laravel 12 разворачивать через pinned `composer create-project laravel/laravel "12.*"` (можно в контейнере `laravelsail/php84-composer`, хостовый PHP не нужен). Проверять `artisan --version` / `laravel/framework` в `composer.lock`.
- **Sail дефолтит на свежий PHP-runtime (был 8.5).** Целевой стек — PHP 8.4: править `compose.yaml` (build context `runtimes/8.4`, image `sail-8.4/app`). Доступные runtimes — `vendor/laravel/sail/runtimes/`.
- **Legacy-референс → `local/legacy_nuxt/`, НЕ в клиентский worktree.** Клиентский worktree = только актуальный код (двухконтурная модель). `local/` игнорируется в study-cbook-ai и вне любого worktree → ноль риска утечки legacy в клиентский коммит. Не добавлять `/legacy_*/` в клиентский `.gitignore` (папки там нет). Старый код всё равно отражается в git как удаления.
- **Секрет-детектор pre-commit ловит хеши `composer.lock` (и `package-lock.json`) как секреты** — ложное срабатывание на `content-hash`/`reference`/`shasum` (32/40 hex). Гасится узким allow-паттерном в `githooks/allowpatterns-root.txt` (`secret_allowed`). Правит **только владелец** — обвязка блокирует запись агентом (Edit/Write и, по духу, Bash). Реальные `PASSWORD=`/`TOKEN=`/AWS-ключи по-прежнему ловятся.
- **Docker-демон — OrbStack** (не Docker Desktop). `docker context` = `orbstack`; поднять — `open -a OrbStack`. Sail работает поверх без изменений.
- **Pint читает только `pint.json` (без точки) — `.pint.json` молча игнорируется.** Дотовый файл не автообнаруживается: Pint тихо гоняет дефолтный пресет `laravel`, а заданные `preset`/`rules` (в т.ч. `declare_strict_types`) не применяются. Симптом: «pint отработал без ошибок», но strict_types не проставлен. Проверка: `pint` без `--config` в шапке пишет пресет `Laravel`; с `--config <файл>` — `PSR 12` → автодетект не сработал. Родом из FEAT-002, починено FEAT-003 (`2038821`).

---

## Счётчики

> Опциональные сквозные счётчики (следующий свободный FEAT-номер, последний ADR и т.п.) — чтобы не сверяться каждый раз вручную.

- Следующий свободный FEAT: FEAT-004 (FEAT-002 = greenfield-скелет done 2026-07-29; FEAT-003 = активация Pint/strict done 2026-07-30)
- Последний ADR: 010 (системный); последний продуктовый — 006; следующий свободный продуктовый — 007

---

## Как обновлять

1. Закрыл фичу/инициативу → добавь запись в «Реализовано» (append-only) и обнови «Актуальный срез».
2. Наступил на грабли → строка в «Gotchas» с классом проблемы.
3. Обнови TOC-блок (`MEMORY-TOC-START…END`) вручную.
4. Проверь «гейт актуальности» `architecture.md` (изменила ли фича то, что тот файл описывает как ФАКТ?).
