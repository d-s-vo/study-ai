---
repo: cbook
authored_hash: 2038821eefc9c42e37574c95fc5fc4aabfe84bcf
patch_id: c932b4f755213c3b1b923983694c4b4fc5cb6288
branch: feat/enterprise-skeleton
feat: FEAT-003
date: 2026-07-30
final_hash:
---

# cbook@2038821 — fix: подхватить конфиг pint и привести кодовую базу к psr12 + strict_types

> Коммит-сообщение (как в клиентском репо): `fix: подхватить конфиг pint и привести кодовую базу к psr12 + strict_types`

## Кратко (для инженера)

- **rename `.pint.json → pint.json`** — Pint автообнаруживает только `pint.json` (без точки); дотовый
  файл молча игнорировался, `psr12` + `declare_strict_types` не применялись.
- `sail bin pint` по всей базе → авто-вставка `declare(strict_types=1)` + psr12-нормализация в 27 файлах
  (`app/*`, `bootstrap/*`, `config/*`, `database/*`, `public/index.php`, `routes/*`, `tests/*`).
- Логика не менялась — только форматирование и строгая типизация; 29 файлов, +62/−8.
- Larastan L10 — зелёно без baseline; Pest arch-барьер доказан red→green (PoC); полный pest — 4 passed.

## Детально (для новичка)

### Почему один rename тянет 27 переформатированных файлов
Pint — автоформат кода. Его конфиг (`pint.json`) включал строгий стиль PSR-12 и правило
`declare_strict_types` (принудительный `declare(strict_types=1)` в каждом файле). Но файл назвали
`.pint.json` (с точкой), а Pint такой файл «не видит» и молча форматирует дефолтным пресетом — правила
не работали. Как только файл переименовали в `pint.json`, Pint подхватил конфиг и при первом прогоне
дописал строгую типизацию и выровнял стиль по всему проекту разом. Отсюда 27 файлов: это не новая
логика, а «долг форматирования», накопившийся пока конфиг был мёртв.

### Почему это `fix`, а не `chore`
Инвариант проекта — `declare(strict_types=1)` в каждом `.php` и psr12 — де-факто не выполнялся:
инструмент качества был выключен неверным именем файла. Коммит чинит именно это (config-inert bug),
поэтому тип — `fix`.

## Почему так, а не иначе

- **`pint.json` вместо `.pint.json`** — промпт задачи и FEAT-002 диктовали дотовое имя, но с ним
  конфиг Pint не подхватывается (проверено эмпирически: `pint` без `--config` → пресет Laravel;
  с `--config .pint.json` → PSR 12). Дотовое имя = мёртвый конфиг, DoD по strict_types недостижим.
- **Baseline не заводили** — Larastan L10 на `app/` даёт `No errors` и без него; `phpstan-baseline.neon`
  создавать не стали (он допустим только для штатного framework-кода, здесь не потребовался).

## Связи

- Фича: `../../features/FEAT-003-enterprise-skeleton/impl.md`.
- Предшественник: `9f4b857-laravel-skeleton.md` (FEAT-002) — исправляемый дефект родом оттуда.
- ADR: `../../../adr/002-stack-laravel-filament-inertia.md`, `../../../adr/003-layered-architecture.md`.
