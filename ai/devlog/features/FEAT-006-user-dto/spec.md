# FEAT-006: UserData DTO наружу + автоген TS-типов (закрытие advisory-долга FEAT-004)

## Статус: SPEC

## Затрагиваемые репозитории
cbook (backend + frontend) — один репозиторий. Мультирепный рецепт §3.5 не применяется.

## Цель
Закрыть advisory-долг ревью FEAT-004: `HandleInertiaRequests` отдаёт в Inertia **сырую модель `User`**, нарушая STRICT RULE 4 («наружу — только DTO»). Ввести `App\Data\UserData` (Spatie Data), отдавать `UserData|null`, и заменить рукописный TS-интерфейс `User` на **автогенерируемый** тип (`artisan typescript:transform`), сделав `auth.user` честно nullable.

## Контекст
База — `origin/develop @ e0c8ee3`, поверх FEAT-005 (инфраструктура/гейты уже зелёные). Долг зафиксирован в `ai/memory.md` («Открытые задачи», ревью `e0c8ee3-review.md`) и в бэклоге.

Текущее состояние:
- `app/Http/Middleware/HandleInertiaRequests.php:37` — `'user' => $request->user()` отдаёт Eloquent-модель `User` целиком (включая потенциально лишние поля) → нарушение STRICT RULE 4.
- `resources/js/types/index.d.ts:1-6` — рукописный `interface User`; `PageProps.auth.user: User` (строки 11-13) **ложно non-nullable** (гость → `user` = `null`).
- `Welcome.vue:49` уже делает `v-if="$page.props.auth.user"` (значит на практике бывает null), но тип это скрывает.
- `spatie/laravel-typescript-transformer` **НЕ установлен**: он фигурирует в `composer.lock` только как `require-dev` пакета `spatie/laravel-data` (т.е. как его dev-зависимость, транзитивно НЕ подтягивается) — в `vendor/spatie/laravel-typescript-transformer` его нет, в `composer.json` его нет, конфиг не опубликован (`config/typescript-transformer.php` отсутствует). ⇒ это **свежая установка** пакета (`composer require --dev`), а не «промоут уже стоящей транзитивной зависимости». Команда `typescript:transform` из ТЗ/README ещё не задействована.

STRICT RULE 4 и «типы API — из контракта (кодогенерация), не рукописные» — `ai/memory.md` North Star + `stack-specifics.md` §Frontend-инварианты.

## Acceptance Criteria
- [ ] Существует `app/Data/UserData.php` (Spatie `Data`) c полями только для фронта: `id: int`, `name: string`, `email: string`, `email_verified_at: ?string` (или `?CarbonImmutable` с TS-маппингом в `string|null`). Пароля/`remember_token` — нет.
- [ ] `HandleInertiaRequests::share()` отдаёт `'user' => $user ? UserData::from($user) : null` — сырой модели `User` наружу больше нет.
- [ ] `spatie/laravel-typescript-transformer` установлен и добавлен явной записью в `composer.json` **`require-dev`** (dev/codegen-инструмент — прод не нужен, т.к. `generated.d.ts` коммитится); конфиг опубликован; коллектор настроен на `App\Data`; вывод — `resources/js/types/generated.d.ts`.
- [ ] `artisan typescript:transform` генерирует `generated.d.ts` с типом для `UserData`; файл присутствует в репозитории (или сгенерирован детерминированно и закоммичен — решение ниже).
- [ ] Рукописный `interface User` из `index.d.ts` удалён; `PageProps.auth.user` типизирован как `<сгенерированный UserData> | null`.
- [ ] `vue-tsc --noEmit` (в составе `pnpm build`) проходит; все потребители `$page.props.auth.user` — null-safe (см. ниже 3 места).
- [ ] Живая приёмка: гость на `/` → `auth.user === null` (Welcome не падает); залогиненный → шапка `AuthenticatedLayout` показывает имя/email; профиль редактируется.
- [ ] PHPStan L10 без новых подавлений; Pint pass; Pest — существующие тесты зелёные (+ тест на форму DTO).

## Технический дизайн

### Backend (контракт — до фронта)
- **`app/Data/UserData.php`** — `final` класс на `Spatie\LaravelData\Data`:
  ```
  public function __construct(
      public int $id,
      public string $name,
      public string $email,
      public ?string $email_verified_at,
  ) {}
  ```
  Сборка из модели — `UserData::from(User $user)` (magic `from` Spatie Data по совпадению имён; `email_verified_at` привести к ISO-строке/`null`). Модель `User` внутри DTO не хранится — только скалярные поля.
- **`HandleInertiaRequests.php`**: получить `$user = $request->user()`; вернуть `UserData::from($user)` при наличии, иначе `null`. `$request->user()` типизирован как `?Authenticatable` — сузить (`instanceof User` / `assert`) как в `ProfileController`, чтобы L10 не ругался. Eloquent-модель наружу не уходит; `UserData::from()` вызывается в middleware (допустимо — это не запрос к БД; изоляция Eloquent касается `Model`/`DB`, а не DTO-сборки).

### Автоген TS-типов
- Установить `spatie/laravel-typescript-transformer` (`composer require --dev` — свежая установка, пакета нет в `vendor/`) в `composer.json` **`require-dev`** (кодоген-инструмент; в прод-сборку не идёт — `generated.d.ts` коммитится).
- Опубликовать конфиг (`vendor:publish` тег transformer) → `config/typescript-transformer.php`; настроить `collectors`/`transformers` на Spatie Data и `auto_discover_types => ['app/Data']`; `output_file => resources/js/types/generated.d.ts`.
- Пометить `UserData` для трансформера (атрибут `#[TypeScript]` или auto-discover по каталогу — выбрать один способ и зафиксировать).
- **Решение о хранении `generated.d.ts`:** файл **коммитится** в репозиторий (детерминированная генерация), чтобы `vue-tsc`/CI не требовали PHP-шага перед сборкой фронта. Регенерация — командой `artisan typescript:transform` после изменения любого DTO (инвариант из README/stack-specifics).

### Frontend (types-first)
- `resources/js/types/index.d.ts`: удалить рукописный `interface User`; импортировать сгенерированный тип (namespace из `generated.d.ts`, напр. `App.Data.UserData`); `PageProps.auth.user: App.Data.UserData | null`.
- Null-safety у **всех** потребителей `$page.props.auth.user`:
  - `Welcome.vue:49` — уже `v-if`, тип теперь честный (ок).
  - `AuthenticatedLayout.vue:55,159,162` — `$page.props.auth.user.name/.email`: этот layout рендерится только под `auth`-мидлварой (user всегда есть), но тип нулевой → добавить `?.`/guard или локальное сужение (напр. `const user = computed(() => page.props.auth.user!)` с обоснованием, либо `v-if`). Выбрать безопасный вариант без `!`-ассерта где возможно.
  - `UpdateProfileInformationForm.vue:13` — `usePage().props.auth.user` (non-null сейчас): страница только для авторизованного; сузить явно (guard/`computed`), не `as`/`any`.
- `resources/js/types/global.d.ts` — augment `@inertiajs/core` PageProps остаётся; **axios-часть не трогаем** (её чистит FEAT-008 — см. границы).

## Тесты
**Добавить:** `tests/Feature/UserDataTest.php` (или расшить существующий) — `UserData::from(User::factory()->create())` даёт корректные `id/name/email/email_verified_at`; поля `password`/`remember_token` в массиве DTO **отсутствуют** (негативная проверка утечки).
**Добавить:** `tests/Feature/*` — Inertia-assert: гость на `/` → проп `auth.user === null`; залогиненный → `auth.user` содержит `id/name/email` и **не** содержит `password`.
**Обновить:** существующие Inertia-тесты, если ассертят форму `auth.user` (проверить `Dashboard`/`Profile`-тесты).
**Удалить:** нет.

> STRICT RULE 4 — чувствительные поля: обязательна негативная проверка, что `password`/`remember_token` не сериализуются наружу.

## Типизация/качество
- Гейты: `sail bin phpstan analyse` (L10, без новых подавлений — сужение типа `User` через `instanceof`/`assert`, не baseline), `sail bin pint --test`, `sail artisan test`, `pnpm build` (включает `vue-tsc`).
- **Типы — из контракта:** TS-тип `User` больше не рукописный, а из `typescript:transform`. Инвариант «после изменения DTO — прогнать transform» зафиксирован.
- 0 `any`/`as` в новом фронт-коде.

## Безопасность
- **Доступы:** новых маршрутов нет. `HandleInertiaRequests` уже глобальный — меняется только форма пропа.
- **Данные:** ключевое улучшение — DTO отдаёт **только** whitelisted-поля; `password`/`remember_token` физически не покидают backend (было: сырая модель с `$hidden`, но контракт наружу нетипизирован). Негативный тест обязателен.
- **Валидация:** пользовательского ввода фича не добавляет.
- **Гигиена §8:** DTO/типы — человеческий стиль, без следов системы.

## Пользовательская документация
Внутреннее изменение контракта Inertia-пропсов; user-visible поведение не меняется (гость/логин работают как прежде). README уже описывает `typescript:transform` — проверить актуальность формулировки; правок публичной доки не требуется (отметить в `impl.md`: checked, no changes needed).

## Зависимые файлы для изменения
| Файл | Тип изменения |
|---|---|
| `app/Data/UserData.php` | новый DTO (Spatie Data) |
| `app/Http/Middleware/HandleInertiaRequests.php` | `user` → `UserData\|null` |
| `composer.json` | require-dev: `spatie/laravel-typescript-transformer` (свежая установка, кодоген-инструмент) |
| `config/typescript-transformer.php` | новый — конфиг генератора |
| `resources/js/types/generated.d.ts` | новый — автоген типов |
| `resources/js/types/index.d.ts` | убрать рукописный `User`; `auth.user: UserData\|null` |
| `resources/js/Layouts/AuthenticatedLayout.vue` | null-safety `auth.user` |
| `resources/js/Pages/Profile/Partials/UpdateProfileInformationForm.vue` | null-safety `auth.user` |
| `tests/Feature/UserDataTest.php` (+Inertia-assert) | новые тесты |

## Зависимости/границы (сверка с 005/007/008)
- **Порядок:** реализуется **после FEAT-005** (нужны зелёные гейты/pnpm/CI). До FEAT-007 и FEAT-008.
- **`composer.json`:** FEAT-006 трогает **`require-dev`** (добавляет transformer); FEAT-005 владел блоком `scripts`. Разные секции — при последовательной интеграции конфликта строк нет; ребейз 006 на 005.
- **`HandleInertiaRequests.php`:** трогает **только FEAT-006**. FEAT-007 (auth-контроллеры/requests/baseline) этот файл не касается — конфликта нет.
- **`resources/js/types/*`:** FEAT-006 правит `index.d.ts` (+ новый `generated.d.ts`); FEAT-008 позже правит `global.d.ts` (удаление axios) и ужесточает `tsconfig`. Разные файлы types-каталога → при последовательности 006→008 конфликта строк нет, но обе фичи трогают каталог — интегрировать по очереди. Null-safety `auth.user` — целиком в 006, чтобы 008 (tsconfig strict/ESLint) наследовал уже чистый фронт.
- **`phpstan-baseline.neon`:** FEAT-006 не трогает (сужение типа `User` в middleware решается локально `instanceof`/`assert`, не через baseline). Baseline удаляет FEAT-007.
- **Оставляет систему зелёной:** после 006 все гейты (phpstan/pint/pest/build) зелёные; baseline ещё присутствует (его снимает 007).

## Что НЕ входит
- Throttle, перевод инлайн-валидации в FormRequest, удаление phpstan-baseline (FEAT-007).
- Чистка axios/скаффолда, ESLint/tsconfig-ужесточение, Tailwind-линия (FEAT-008).
- DTO для доменных сущностей (Recipe/Ingredient) — доменная фаза.

## Оценка сложности
Средняя. Риски: (1) корректная настройка typescript-transformer (коллектор/namespace/output) — первый запуск генератора в проекте; (2) детерминированность `generated.d.ts` (порядок полей) для чистого diff; (3) null-safety в `AuthenticatedLayout` без `!`/`any`-костылей при честно nullable типе.
