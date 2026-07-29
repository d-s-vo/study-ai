---
repo: cbook
authored_hash: 9f4b857b84cad88df8add27ada9792b868c99c07
patch_id: ab97c5b11fced253fcdcf18976b58450b5affb01
branch: feat/laravel-skeleton
feat: FEAT-002
date: 2026-07-29
final_hash:
---

# cbook@9f4b857 — feat: инициализировать скелет Laravel 12 со слоистой архитектурой и QA-тулчейном

> Коммит-сообщение (как в клиентском репо): `feat: инициализировать скелет Laravel 12 со слоистой архитектурой и QA-тулчейном`

## Кратко (для инженера)

- Удаление legacy Nuxt (49× `D`) — старый стек изолирован вне worktree, greenfield-старт с чистого листа.
- `compose.yaml`, `.env.example`, `.gitignore` — Laravel Sail (MySQL 8, runtime PHP 8.4), дефолтная обвязка.
- `app/Tasks/BaseTask.php` — абстрактный контракт бизнес-операций, `handle(): mixed` (явный тип для PHPStan L10).
- `app/Data/Repositories/BaseRepository.php` — абстрактный контракт слоя доступа к БД (единственная зона Eloquent/DB).
- `app/Data/.gitkeep`, `app/Resolvers/Page/.gitkeep` — держат пустые слои в индексе.
- `.pint.json`, `phpstan.neon` — Pint psr12 + `declare_strict_types`, Larastan level 10 на `app/`.
- `tests/Feature/ArchitectureTest.php` — арх-барьер: Eloquent/DB-фасад только в репозиториях.
- `composer.json`/`composer.lock` — `spatie/laravel-data` (prod); larastan/pest (dev).

## Детально (для новичка)

### Удаление Nuxt-файлов
Старый проект был на Nuxt (Vue-фреймворк на Node). Мы переписываем cbook с нуля на Laravel (PHP),
поэтому старый код больше не проект, а лишь референс. Он физически вынесен из рабочей папки, и git
видит это как удаление файлов. Сам референс не потерян — лежит вне репозитория (`local/legacy_nuxt/`).

### `app/Tasks/BaseTask.php` и `app/Data/Repositories/BaseRepository.php`
Это «слоистая архитектура»: код разбит на слои с чёткими обязанностями. **Task** — одна бизнес-операция
(например «создать рецепт»). **Repository** — единственное место, где разрешено обращаться к БД
(Eloquent/фасад `DB`). Базовые абстрактные классы — общий контракт, от которого наследуются конкретные.
`handle(): mixed` — метод с явно указанным типом возврата; строгая типизация нужна статическому
анализатору PHPStan на максимальном уровне 10 (иначе он ругается на «неизвестный тип»).

### `tests/Feature/ArchitectureTest.php`
Обычные тесты проверяют поведение; **арх-тесты** (Pest) проверяют *структуру* — что слои не нарушены.
Здесь: модели Eloquent и фасад `DB` можно вызывать только в репозиториях (и сидерах/фабриках Laravel).
Если кто-то дёрнет модель напрямую из Task или контроллера — тест покраснеет. Это структурный «предохранитель»
против размывания архитектуры; мы доказали его работу (временный нарушитель → красный, удалили → зелёный).

### `.pint.json`, `phpstan.neon`
Инструменты качества. **Pint** — автоформат кода (стиль PSR-12) и принудительный
`declare(strict_types=1)` в каждом файле. **Larastan** — PHPStan с поправкой на «магию» Laravel; level 10 —
самый строгий. Оба гоняются через Sail и должны быть зелёными до коммита.

## Почему так, а не иначе

- **`composer create-project "12.*"` вместо `laravel.build`** — отклонён: дефолтный bootstrap сегодня
  ставит последнюю мажорную (вероятно Laravel 13), а цель — именно 12. Pin даёт детерминизм (12.64).
- **PHP 8.5 (дефолт Sail)** — отклонён в пользу 8.4: целевой стек проекта — PHP 8.4 (ADR-002).
- **`--filter` для запуска арх-теста** — отклонён в пользу запуска по пути файла (надёжнее матчит, чем
  по описанию теста).

## Связи

- Фича: `../../features/FEAT-002-laravel-skeleton/impl.md` · spec-of-record: `local/prompts/task-1a-laravel-skeleton.md`.
- ADR: `../../../adr/002-stack-laravel-filament-inertia.md`, `../../../adr/003-layered-architecture.md`, `../../../adr/006-migration-nuxt-to-laravel.md`.
