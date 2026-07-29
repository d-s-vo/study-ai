---
feat: FEAT-002
tags: [docs-only, security-leak]
class: 'Greenfield-скелет Laravel 12 + enterprise-слои + QA-тулчейн (Pint/Larastan L10/Pest arch-барьер)'
prevention: 'test: Pest arch-барьер (tests/Feature/ArchitectureTest.php) — изоляция Eloquent/DB-фасада по слоям, доказан red→green'
---

# FEAT-002: Greenfield-скелет Laravel 12 + тулчейн + enterprise-архитектура — Implementation

**Статус:** DONE
**Ветка:** `feat/laravel-skeleton` · **Репо:** cbook · **Коммит (as-authored):** `9f4b857`
**Дата:** 2026-07-29
**Spec-of-record:** внешний провалидированный промпт `local/prompts/task-1a-laravel-skeleton.md`
(spec.md ретроспективно не сочинялся — правило devlog «spec пишется ДО реализации»).

## Что сделано (файлы → изменения)

- **Изоляция legacy.** Весь Nuxt-проект (`app/`, `.github/`, `prisma/`, конфиги, `server/`, `shared/`,
  `tests/` и т.д.) вынесен из корня worktree. По указанию владельца — не в корень worktree, а в
  `local/legacy_nuxt/` корня study-cbook-ai (вне любого клиентского worktree). Наш корневой
  `README.md` сохранён без изменений (идентичен базе `develop`).
- **Чистый Laravel 12.** `composer create-project laravel/laravel "12.*"` в контейнере
  `laravelsail/php84-composer` → Laravel Framework **12.64.0**. `sail:install --with=mysql`.
  Содержимое перенесено в корень worktree (дефолтный README скэффолда удалён в пользу нашего).
- **Sail / .env.** `compose.yaml` runtime приведён 8.5 → **8.4** (целевой стек README — PHP 8.4).
  `.env` (MySQL, `DB_HOST=mysql`) + порты брони FEAT-002: `APP_PORT=8110`, `VITE_PORT=5183`,
  `FORWARD_DB_PORT=3110`. `APP_KEY` сгенерирован. `.gitignore` — Laravel-дефолт.
- **Пакеты.** PROD: `spatie/laravel-data ^4.23`. DEV: `larastan/larastan ^3.10`, `pestphp/pest ^3.8`,
  `pestphp/pest-plugin-laravel ^3.2` (Pint — из коробки).
- **Enterprise-слои.** `app/Data/` (+`.gitkeep`), `app/Data/Repositories/BaseRepository.php`,
  `app/Tasks/BaseTask.php` (`abstract public function handle(): mixed`), `app/Resolvers/Page/`
  (+`.gitkeep`). Все `.php` — `declare(strict_types=1)`.
- **QA-конфиги.** `.pint.json` (psr12 + `declare_strict_types`), `phpstan.neon` (Larastan, level 10,
  paths: app). `tests/Feature/ArchitectureTest.php` — арх-барьер изоляции слоёв.

## Отклонения от spec (промпта) — осознанные, ради цели промпта

1. **Laravel разворачивал через `composer create-project "12.*"`, не `laravel.build`.** На 2026-07-29
   `laravel.build`/`laravel new` отдаёт последнюю мажорную (вероятно 13) → разошлось бы с DoD
   «чистый Laravel 12». Pin → гарантированно 12.64 (проверено).
2. **PHP-runtime Sail: 8.5 → 8.4.** Sail дефолтит на свежий PHP; целевой стек (README/ADR-002) — 8.4.
3. **legacy_nuxt → `local/`, не в корень worktree** (указание владельца). Строка `/legacy_nuxt/`
   из клиентского `.gitignore` убрана (папки в worktree нет — запись была бы мёртвой). Конвенция
   зафиксирована в durable-памяти агента.

## Ключевые решения по ходу

- **Секрет-детектор pre-commit ловил хеши `composer.lock`** (`content-hash`/`reference`, 32/40 hex)
  как «секреты» — ложное срабатывание. `composer.lock` обязателен к коммиту. Решение: узкий allow-паттерн
  в `githooks/allowpatterns-root.txt` (штатный механизм `secret_allowed`). Правку в `githooks/`
  вносил **владелец** (обвязка блокирует запись агентом — «правит только человек»), агент не обходил
  барьер через Bash. Реальные `PASSWORD=`/`TOKEN=`/AWS-ключи по-прежнему ловятся.
- Тяжёлый первичный `sail build` сериализован через `gate.sh docker-build`.

## Как тестировали (команды, результаты)

- `sail up -d` → контейнеры подняты; `curl :8110` → **HTTP 200**; `sail php -v` → **PHP 8.4.23**.
- `sail artisan migrate` → миграции прошли (коннект MySQL 8 подтверждён).
- `sail bin phpstan analyse` (Larastan **level 10**) → **No errors**.
- Арх-барьер (PoC): временный `DummyTask` с `\App\Models\User::query()` →
  `sail bin pest tests/Feature/ArchitectureTest.php` **красный** (зафиксировано нарушение слоя);
  после удаления DummyTask — **зелёный**.
- `sail bin pest` (весь набор) → **4 passed** (Unit + Arch×2 + Feature/Example).

## Итог

DoD задачи 1a закрыт полностью. Клиентский коммит `9f4b857` на `feat/laravel-skeleton`; 0 следов ИИ
(проверено: имена, содержимое, сообщение). Доставка в git клиента — шаг владельца (`deliver.sh`).

## Связи

- Spec-of-record: `local/prompts/task-1a-laravel-skeleton.md`
- Per-commit rationale: `../../commits/cbook/9f4b857-laravel-skeleton.md`
- ADR: `../../adr/002-stack-laravel-filament-inertia.md`, `../../adr/003-layered-architecture.md`,
  `../../adr/006-migration-nuxt-to-laravel.md` (исполнение, новых решений не вводит)
