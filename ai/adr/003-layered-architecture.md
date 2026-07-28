# ADR-003: Строгая слоистая архитектура (Request→Controller→Task→Repository→DTO→Resolver→Inertia)

**Статус:** Принят (зафиксирован при инициализации `ai/`; переработан под ТЗ заказчика 2026-07-28)
**Дата:** 2026-07-28

> Продуктовый decision-ADR. Фиксирует конкретную слоистую организацию кода Laravel-приложения cbook по ТЗ.
> **Уточнение (2026-07-28):** абстрактные слои «Domain/Application/Infrastructure» **отменены** ТЗ и заменены конкретным именованным потоком с каталогами `app/Tasks`, `app/Resolvers/Page`, `app/Data/Repositories`. Это уточнение того же ADR-003, а не новый номер.

## Контекст

cbook переезжает на Laravel 12 (ADR-002). Дефолтный Laravel располагает к «толстым» контроллерам/моделям, где бизнес-логика и запросы к БД размазаны по HTTP-слою и Eloquent. ТЗ заказчика требует **строгой enterprise-раскладки** с одним направлением потока данных и **машинно-проверяемой изоляцией Eloquent** (PHPStan Level 10), чтобы доменная логика рецептов (правила, права по владельцу) оставалась тестируемой, а Eloquent не «протекал» в презентацию.

## Рассмотренные варианты

### Вариант А — Стандартный Laravel-layout (контроллеры + Eloquent-модели)
- **За:** меньше церемоний; привычно; быстрый старт.
- **Против:** бизнес-логика и запросы утекают в контроллеры/модели; трудно тестировать без БД/фреймворка; правила прав и инварианты рассеиваются; изоляцию нечем проверить автоматически.

### Вариант Б — Строгий именованный поток Task/Repository/DTO/Resolver (выбран, по ТЗ)
- **За:** одно направление потока; Eloquent заперт в репозиториях и это **проверяет PHPStan L10** (не только ревью); наружу идут типобезопасные DTO (Spatie Data) с автогенерацией TS-типов; контроллеры/Filament тонкие; каталоги задают роль однозначно.
- **Против:** больше слоёв и церемоний (Task/Resolver/Repository/DTO на операцию); строгий статанализ требует дисциплины.

## Решение (5 STRICT RULES ТЗ)

1. **`declare(strict_types=1)`** — в каждом `.php` первой строкой (`<?php declare(strict_types=1);`).
2. **Изоляция Eloquent (жёстко):** `Eloquent\Model` и фасад `DB` — ТОЛЬКО внутри `app/Data/Repositories/*`. Контроллеры / Tasks / Resolvers / Vue напрямую Eloquent/`DB` НЕ вызывают. **Нарушение = ошибка PHPStan Level 10.**
3. **Единый поток данных:** Request (**FormRequest**) → **Controller** → **Task** (бизнес-логика) → **Repository** (запрос к БД) → **DTO** (Spatie Data) → **Page Resolver** → **Inertia Vue Page**.
4. **Только DTO наружу:** в Inertia/Vue передаются ТОЛЬКО DTO (Spatie Data) — никаких сырых Eloquent-моделей/массивов.
5. **Именование слоёв по каталогам:** одна бизнес-операция = один Task (`app/Tasks/CreateRecipeTask.php`); сборка пропсов страницы = Resolver (`app/Resolvers/Page/RecipeDetailResolver.php`); запросы к БД = Repository (`app/Data/Repositories/RecipeRepository.php`).

### Каталоги и роли

| Каталог | Роль | Eloquent/`DB`? |
|---|---|---|
| `app/Http/Requests/` | FormRequest — вся серверная валидация | нет |
| `app/Http/Controllers/` | Тонкий контроллер: FormRequest → Task/Resolver → Inertia | нет |
| `app/Tasks/` | Одна бизнес-операция = один Task | нет |
| `app/Data/Repositories/` | Запросы к БД — **единственное место** Eloquent/`DB` | **ДА (только здесь)** |
| `app/Data/` | DTO (Spatie Laravel Data); источник TS-типов | нет |
| `app/Resolvers/Page/` | Page Resolver — сборка пропсов Inertia-страницы из DTO | нет |
| `app/Models/` | Eloquent-модели — используются только из репозиториев | — |
| `app/Filament/` | Filament 5 Resource'ы (`/admin`) без бизнес-логики | делегируют |

6. **Контроллеры/Filament тонкие:** приняли запрос → делегировали в Task/Repository → вернули Inertia-ответ; валидация — во **FormRequest**; авторизация — через **Policies/Gate** до бизнес-логики.
7. **Порядок создания сущности (инвариант):** миграция → Eloquent-модель (`app/Models`) → Repository (`app/Data/Repositories`) → DTO (Spatie Data) → Task → FormRequest → Controller → Resolver → Inertia Vue page → тесты (Pest, позитив + негатив прав).

## Последствия

- Инварианты слоёв прошиты в [`../guides/stack-specifics.md`](../guides/stack-specifics.md) §Инварианты и §Backend-специфика; против них проверяются тройная проверка spec (feature-workflow Шаг 5) и адверсариальная приёмка (live-acceptance).
- Роутер задач `../architecture.md` §0 для серверной фичи ведёт на эти инварианты.
- **Изоляция Eloquent энфорсится автоматически** — PHPStan Level 10 (гейт статанализа), а не только ревью; направление потока держится ревью + commit-review.
- Издержка: дополнительный код-церемония (Task/Resolver/Repository/DTO на операцию) на каждую сущность; после правки DTO — прогон `artisan typescript:transform`.

## Ссылки

- [`002-stack-laravel-filament-inertia.md`](002-stack-laravel-filament-inertia.md) — стек.
- [`006-migration-nuxt-to-laravel.md`](006-migration-nuxt-to-laravel.md) — миграция, в ходе которой слои наполняются.
- [`../guides/stack-specifics.md`](../guides/stack-specifics.md) — инварианты и порядок создания сущности.
- [`../architecture.md`](../architecture.md) §4 — раскладка слоёв.
