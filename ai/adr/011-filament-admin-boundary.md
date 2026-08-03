# ADR-011: Граница Filament-админки и изоляции Eloquent (админ-слой поверх строгой архитектуры)

**Статус:** Реализован
**Дата:** 2026-08-03

> Продуктовый decision-ADR фичи FEAT-013 (filament-admin). Уточняет машинно-энфорсимый инвариант
> изоляции Eloquent из ADR-003 для нового админ-слоя `app/Filament`. Заведён по критериям
> `adr/README.md`: меняется уже принятое машинно-энфорсимое архитектурное решение + фиксируется
> неочевидный компромисс между подходами.

## Контекст

cbook ставит Filament 5 как админ-панель `/admin` (целевой стек — ADR-002). Filament по своей природе
работает с **Eloquent напрямую**: Resource привязан к модели (`protected static ?string $model`),
таблицы/формы/relation-managers строят запросы к модели (`getEloquentQuery()`, table query, form fill).

Но ADR-003 (5 STRICT RULES) требует: `Eloquent\Model` и фасад `DB` — **только** внутри
`app/Data/Repositories/*`, и это энфорсится машинно — арх-барьер `tests/Feature/ArchitectureTest.php`
(allow-list слоёв) + PHPStan Level 10. «В лоб» сгенерированный Filament-Resource, назвавший
`App\Models\Recipe`, краснит арх-барьер (правило #1) и не проходит гейт.

Конфликт неизбежен: либо Filament не вписывается в архитектуру, либо инвариант изоляции нужно
осознанно уточнить для админ-слоя. Дополнительно `RecipePolicy` (FEAT-010) реализует анти-IDOR
(мутации — только владелец), а админ по замыслу должен видеть и править **все** рецепты — нужен
явный супер-доступ, не обходящий Policy молча.

## Рассмотренные варианты

### Вариант A — Filament как санкционированное исключение (Eloquent напрямую, включая мутации)
- **За:** проще всего; Resource читает и пишет модель напрямую, минимум кастома.
- **Против:** дублирует бизнес-логику. `RecipeRepository::createForUser/update` делает транзакционную
  синхронизацию ингредиентов; прямой `->save()` из Filament обойдёт её (риск рассинхрона агрегата) и
  размажет мутации по Resource (анти-паттерн «бизнес-логика в Filament Resource»). Максимально
  ослабляет инвариант.

### Вариант B — Всё через Repository/Task (модель в Resource не появляется)
- **За:** инвариант изоляции не ослабляется вовсе.
- **Против:** тяжёлая борьба с фреймворком. Filament ждёт Eloquent-query для сортировки/фильтров/
  пагинации/relation-manager; замена на кастомные `getTableQuery`/actions — много хрупкого кода,
  часть возможностей панели теряется, педагогически спорно.

### Вариант C — Гибрид (выбран)
- **За:** **чтение** (table query, form fill, relation-manager) — через модель в Resource, в рамках
  точечно расширенного allow-list; **мутации** (create/update/delete) — делегируются существующим
  Tasks через хуки Filament; **авторизация** — через существующие Policies. Единый источник правды
  мутаций (Tasks/Repository, транзакции сохранены), инвариант ослаблен точечно (только чтение модели
  в админ-слое). Соответствует роли `app/Filament` из ADR-003 («Resource без бизнес-логики,
  делегирует в Task/Repository»).
- **Против:** умеренный кастом на мутационных хуках (`handleRecordCreation`/`handleRecordUpdate`/
  `handleRecordDeletion`), которые нужно провести через Task, не «протекая» в прямой `->save()`.

## Решение (вариант C)

1. **Расширение allow-list арх-барьера, правило #1.** В `ArchitectureTest` правило
   `expect('App\Models')->toOnlyBeUsedIn([...])` дополняется `'App\Filament'` — админ-слою разрешено
   ссылаться на модели для **чтения**. Доказано **red→green** (без строки барьер краснеет на первом
   Resource, со строкой — зеленеет). Правило #2 (`DB` → только `App\Data\Repositories`) **не трогаем** —
   оно остаётся машинным guard'ом против сырых записей из Filament.
2. **Граница «Filament можно / нельзя»:**
   - **Можно:** объявлять `$model`, ссылаться на модель для чтения (table/form/relation query,
     `getEloquentQuery`), маппить данные модели в форму/таблицу/Infolist.
   - **Нельзя:** прямые мутации с бизнес-смыслом (`->save()/->create()/->delete()` доменной записи) и
     **любое обращение к фасаду `DB`**. Мутации доменного агрегата Recipe идут через существующие
     Tasks (`CreateRecipeTask`/`UpdateRecipeTask`/`DeleteRecipeTask` → `RecipeRepository`, транзакции
     сохранены), вызванные из хуков Filament.
3. **Супер-доступ админа через `RecipePolicy::before()`.** Добавляется
   `before(User $user): ?bool { return $user->is_admin ? true : null; }`. Для админа — супер-доступ ко
   всем рецептам (осознанный, по замыслу); для не-админа возвращается `null` → owner-scoping (FEAT-010)
   не ослаблен, негативные IDOR-тесты остаются зелёными.
4. **Доступ к панели — least privilege.** `User implements FilamentUser`;
   `canAccessPanel()` = `is_admin && hasVerifiedEmail()`. Флаг `is_admin` (bool, default `false`) —
   **вне `$fillable`** (нет mass-assignment-эскалации прав через формы), назначается bootstrap-командой.
5. **UserResource — read-only**, без экспонирования `password`/`remember_token`/токенов.

## Последствия

- Инвариант изоляции Eloquent (ADR-003, правило #2 про `DB`) сохранён как машинный guard; правило #1
  (модели) точечно расширено на `App\Filament` — только чтение. Мутации домена по-прежнему в Tasks.
- Источник энфорсмента: `ArchitectureTest` (allow-list) + PHPStan L10 (`app/Filament` в `paths`, без
  baseline — сгенерированный код доводится до 0 ошибок вручную).
- Новая поверхность доступа `/admin` закрыта `canAccessPanel` (least privilege) + негативными тестами.
- Супер-доступ админа задокументирован как осознанный, а не дыра изоляции; owner-scoping не-админа
  не изменён.
- Издержка: мутационные хуки Filament требуют ручной проводки в Tasks и STRICT-ревиза
  сгенерированного кода под L10/strict.

## Ссылки

- [`003-layered-architecture.md`](003-layered-architecture.md) — уточняемый инвариант изоляции Eloquent.
- [`002-stack-laravel-filament-inertia.md`](002-stack-laravel-filament-inertia.md) — Filament 5 в стеке.
- [`../devlog/features/FEAT-013-filament-admin/spec.md`](../devlog/features/FEAT-013-filament-admin/spec.md) — спека.
- [`../devlog/features/FEAT-013-filament-admin/impl.md`](../devlog/features/FEAT-013-filament-admin/impl.md) — реализация, PoC red→green.
