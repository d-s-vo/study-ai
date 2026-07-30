---
feat: FEAT-003
tags: [config-inert, silent-noop, tooling]
class: 'Конфиг Pint молча инертен из-за дотового имени файла (.pint.json не автообнаруживается)'
prevention: 'gotcha + reference-память pint-config-filename; проверка: pint без --config пишет пресет Laravel вместо PSR 12 → конфиг не подхвачен'
---

# FEAT-003: Активация конфига Pint + строгая типизация по всей базе — Implementation

**Статус:** DONE
**Ветка:** `feat/enterprise-skeleton` · **Репо:** cbook · **Коммит (as-authored):** `2038821`
**Дата:** 2026-07-30
**Spec-of-record:** внешний провалидированный промпт задачи «Enterprise-скелет бэкенда и архитектурные барьеры».

## Контекст

Задача формулировалась как полная настройка enterprise-скелета (слои, Pint, Larastan L10, Pest
arch-барьер). Но каркас уже был заложен FEAT-002 (`9f4b857`): директории `Data`/`Tasks`/`Resolvers`,
`BaseTask`/`BaseRepository`, `phpstan.neon`, `ArchitectureTest`, Pest. Поэтому фактическая работа
свелась к **исполнению и доказательству инвариантов**, в ходе которого вскрылся дефект FEAT-002.

## Корневой дефект (root cause)

FEAT-002 завёл QA-конфиг Pint как **`.pint.json`** (с точкой — так же диктовал и промпт задачи).
Laravel Pint автообнаруживает конфиг строго как **`pint.json`** (без точки); дотовый файл
**молча игнорируется** — Pint тихо гоняет дефолтный пресет `laravel`, а заданные `preset: psr12` и
`rules.declare_strict_types` **не применяются вообще**. Следствие: часть штатного framework-кода
(`User`, `Controller`, `AppServiceProvider`, config/*, migrations, tests) была **без**
`declare(strict_types=1)`, хотя impl FEAT-002 отчитался «Pint psr12+strict применён».

Диагностика (эмпирическая): `pint` без `--config` в шапке пишет пресет **Laravel**; с
`--config .pint.json` — **PSR 12**. Значит автодетект дотового имени не срабатывал.

## Что сделано (файлы → изменения)

- **`git mv .pint.json → pint.json`** — ключевая починка: конфиг стал подхватываться, `psr12` +
  `declare_strict_types` реально применились.
- **`sail bin pint`** по всей базе → авто-правки: вставка `declare(strict_types=1)` + psr12-нормализация
  (пустая строка после `<?php`, скобки класса на отдельной строке). Затронуто 27 файлов
  (`app/*`, `bootstrap/*`, `config/*`, `database/*`, `public/index.php`, `routes/*`, `tests/*`) —
  только форматирование, логика не менялась.
- Итого коммит `2038821`: 29 файлов, +62/−8, включая rename `.pint.json → pint.json`.

## Доказательство инвариантов (как тестировали)

- **Pint:** после rename — чисто, `declare(strict_types=1)` во всех 5 `app/*.php` (BaseTask,
  BaseRepository, User, Controller, AppServiceProvider) + config/tests/migrations.
- **Larastan L10:** `sail bin phpstan analyse` → **No errors**, 5 файлов в `app`. **Baseline не
  понадобился** (ни до, ни после добавления strict_types) — `phpstan-baseline.neon` не создавался.
- **Pest arch-барьер (PoC red→green):** базовая линия зелёная (2 passed) → создан временный
  `app/Tasks/DummyTask.php` с `App\Models\User::query()` → `sail bin pest --filter=ArchitectureTest`
  **красный** (упало правило 1: `Expecting 'App\Models\User' not to be used on 'App\Tasks\DummyTask'`,
  правило DB-фасада осталось зелёным) → DummyTask удалён → снова **зелёно** (2 passed).
- **Полный `sail bin pest`:** **4 passed** (Unit/Example, Arch×2, Feature/Example).

## Гигиена (§8)

0 следов ИИ: grep по коду/тестам/конфигам чист; коммит прошёл сканер стоп-слов и формат-гейт
`commit.sh`. Артефактов PoC/baseline/scratch в коммите нет (DummyTask удалён, `.env`/`vendor` под
gitignore). Доставка в git клиента — за владельцем (`deliver.sh`).

## Корректива к записи FEAT-002

impl FEAT-002 утверждал «Pint psr12+strict применён» — фактически из-за `.pint.json` форматирование
было инертным. FEAT-003 закрывает это расхождение; сам скелет FEAT-002 (слои/контракты/arch-тест)
корректен и остаётся в силе.

## Связи

- Разбор коммита: `../../commits/cbook/2038821-enterprise-skeleton.md`
- Предшественник: `../FEAT-002-laravel-skeleton/impl.md` (`9f4b857`)
- Durable gotcha: агентская reference-память `pint-config-filename`
- ADR: `../../adr/002-stack-laravel-filament-inertia.md`, `../../adr/003-layered-architecture.md`
  (исполнение, новых решений не вводит)
