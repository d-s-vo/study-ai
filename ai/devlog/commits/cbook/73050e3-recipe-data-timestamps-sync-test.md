---
repo: cbook
authored_hash: 73050e32c51eeb9fc29529784db388f69cb695b8
patch_id: fc611a67b819c7d5844049cb5ae059d9410d6546
branch: feat/recipe-data-layer
feat: FEAT-009
date: 2026-07-31
final_hash:
---

# cbook@73050e3 — refactor: единообразие типов дат в RecipeData и осмысленная проверка синхронизации ингредиентов

> Коммит-сообщение (как в клиентском репо): `refactor: единообразие типов дат в RecipeData и осмысленная проверка синхронизации ингредиентов`

## Кратко (для инженера)

- `app/Data/RecipeData.php` — `created_at`/`updated_at`: `?string` → `?CarbonImmutable`, как в `UserData`. TS-тип не меняется (`replaceType(CarbonImmutable → 'string')` в провайдере → `string | null`); `generated.d.ts` перегенерирован, diff пуст.
- `tests/Feature/Recipe/RecipeRepositoryTest.php` — заменена вакуумная ассерция `assertDatabaseMissing(... 'name'=>'Salt','quantity'=>999)` (Salt реально вставлялся с quantity=1.0 → проверка мертва) на осмысленную: фиксируем id исходных 3 ингредиентов, после `update` проверяем `assertDatabaseMissing` по каждому исходному id + `assertDatabaseHas` по новым именам (Sugar, Salt). Теперь ассерция ловит мутацию стратегии sync (append вместо delete+insert).

Follow-up фикс по advisory-находкам ревью коммита `c48543f` (ADR-010 Verdict PASS без блокеров).

## Детально (для новичка)

### `app/Data/RecipeData.php`
DTO — описание «формы данных наружу». Раньше временные метки объявлялись как `?string`, а в соседнем `UserData` — как `?CarbonImmutable`. Разнобой типов в одном слое: одинаковая по смыслу сущность (момент времени) представлялась двумя разными PHP-типами. `CarbonImmutable` — неизменяемый объект даты/времени (операции возвращают новый объект, не мутируют исходный — безопаснее). Приводим `RecipeData` к тому же типу для единообразия. На фронт это не влияет: генератор TS-типов настроен правилом `replaceType(CarbonImmutable → 'string')`, поэтому в `generated.d.ts` поле остаётся `string | null` — diff файла пуст.

### `tests/Feature/Recipe/RecipeRepositoryTest.php`
«Вакуумная» (мёртвая) ассерция — проверка, которая истинна при любом поведении кода и потому ничего не гарантирует. Прежняя строка искала ингредиент Salt с `quantity=999`, хотя Salt вставлялся с `quantity=1.0` — такой записи нет никогда, проверка проходит независимо от корректности кода. Смысл теста — убедиться, что `update` синхронизирует ингредиенты стратегией delete+insert (старые физически удаляются, новые создаются заново). Поэтому до апдейта запоминаем id трёх исходных ингредиентов, а после — проверяем, что каждого из них в таблице больше нет (`assertDatabaseMissing` по `id`), и что появились новые (Sugar, Salt по имени). Если кто-то ошибочно поменяет стратегию на «добавить к существующим», исходные id останутся — и тест упадёт. Так проверка начинает ловить регрессию.

## Почему так, а не иначе

- **Оставить `?string` в RecipeData** — отклонено: держит разнобой типов дат внутри слоя `app/Data`; единый `?CarbonImmutable` + `replaceType` даёт то же TS-представление и один стиль.
- **Проверять sync через точный `assertDatabaseCount`** — рассматривалось; проверка по конкретным исходным id строже: ловит именно подмену стратегии (append), а не только итоговое число строк.

## Связи

- Фича: `../features/FEAT-009-recipe-data-layer/impl.md` · `../features/FEAT-009-recipe-data-layer/spec.md`.
- Базовый коммит фичи: `cbook/c48543f-recipe-data-layer.md` (разбор) · `cbook/c48543f-review.md` (ревью ADR-010, источник advisory).
