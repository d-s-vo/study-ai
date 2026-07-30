---
feat: FEAT-004
repos: [cbook]
tags: [frontend, backend, auth, architecture, scaffolding]
class: 'фронт-скелет Inertia/Vue + enterprise-рефактор Breeze-авторизации под слои'
prevention: 'Pest ArchitectureTest (изоляция App\Models вне репозиториев) — red→green доказан'
---

# FEAT-004: Фронтенд-скелет (Breeze Inertia/Vue/TS) + enterprise-рефактор авторизации — Implementation

## Статус: DONE (передано пользователю на доставку)
## Дата: 2026-07-30

## Что сделано

**Установка стека (Breeze).** `laravel/breeze` (dev) → `breeze:install vue --typescript --pest` развернул связку
Inertia.js + Vue 3 (`<script setup>`, TS strict) + Vite + Tailwind: `resources/js/{app.ts,bootstrap.ts,
Pages,Components,Layouts,types}`, `tsconfig.json`, `resources/views/app.blade.php`, контроллеры Auth,
FormRequest'ы, `routes/auth.php`, миграции (users/password_reset_tokens/sessions/cache/jobs). Node-менеджер —
**pnpm** (через Sail-passthrough; `pnpm-lock.yaml` коммитится). `pnpm run build` — зелёно.

**Enterprise-рефактор (STRICT RULE 2 — Eloquent по User только в репозиториях).**

| Файл | Изменение |
|---|---|
| `app/Data/Repositories/UserRepository.php` | **новый**, `final`. Единственное место Eloquent по User: `create()`, `setPassword()`, `updateProfile()`, `delete()`. Методы мутаций принимают `Authenticatable` + `assert($user instanceof User)` — тип User не «протекает» в контроллеры |
| `app/Tasks/RegisterUserTask.php` | **новый**, `final`. `__construct(private readonly UserRepository)`, `run(name,email,plainPassword): Authenticatable` |
| `app/Tasks/BaseTask.php` | приведён к пустому abstract-маркеру (см. «Ключевые решения») |
| `Auth/RegisteredUserController@store` | `User::create`+`event`+`login` → `RegisterUserTask::run()`; убран `use App\Models\User`; `unique:users,email` |
| `Auth/NewPasswordController@store` | замыкание `Password::reset` типизировано `Authenticatable`; тело → `UserRepository::setPassword(..., rotate:true)`; убран импорт User |
| `Auth/PasswordController@update` | `$user->update([...])` → `UserRepository::setPassword(..., rotate:false)` |
| `ProfileController@update/@destroy` | ручной fill/save и `$user->delete()` → `UserRepository::updateProfile()/delete()`; логаут/инвалидация сессии сохранены |
| `Http/Requests/ProfileUpdateRequest` | 2-й arch-нарушитель: `Rule::unique(User::class)->ignore($this->user()->id)` → `Rule::unique('users','email')->ignore($this->user()?->getAuthIdentifier())`; убран `use App\Models\User` |
| `resources/js/Pages/Dashboard.vue` | дефолт Breeze заменён каркасом «Cookbook: Greenfield Enterprise» в `AuthenticatedLayout` |
| `tests/Feature/UserRepositoryTest.php` | **новый**: create/setPassword/updateProfile(reset email_verified_at)/delete |
| `phpstan-baseline.neon` | **новый**, 8 записей — только нетронутый Breeze-scaffold (`$request->user(): User|null` + 1 `Stringable`); наших файлов в baseline нет |
| `pnpm-workspace.yaml` | `onlyBuiltDependencies: [esbuild]` (нестандартный sandbox-`allowBuilds` убран перед доставкой) |

## Отклонения от spec

1. **`BaseTask` — пустой маркер + метод `run()` вместо `handle()`** (spec допускал `handle(): mixed`).
   Причина — сверка с north-star референсом `listvafitness` (та же студия whyme-agency, чей пакет
   `laravel-media` в нашем стеке): там `LaravelFoundation\Abstracts\AbstractTask` **пуст**, а Task-и
   объявляют `run($данные)` с данными-аргументами и `private readonly` зависимостями в конструкторе,
   классы `final`. Приняли этот канон осознанно (владелец подтвердил). См. «Ключевые решения».
2. **DTO входа Task не вводили** — 3 скаляра в `run()`. Референс использует и DTO, и скаляры
   (листинг-Task на скалярах) — для регистрации скаляры достаточны; доменные DTO (Recipe) — позже.
3. **`@inertiajs/core` вынесен явной dev-зависимостью** — под strict-node_modules pnpm bare-импорт в
   `types/global.d.ts` не резолвился транзитивно (ломал `PageProps`-augmentation, 5 ошибок vue-tsc).
   Явная строка чинит и под pnpm, и под npm — обычная человеческая зависимость.

## Ключевые решения по ходу реализации

- **Канон Task (A + `run()` + `final readonly`).** База (`BaseTask`/`BaseRepository`) — пустой
  abstract-ярлык слоя (нельзя навязать единую сигнатуру: у разных Task-ов разные вводные). Конкретный
  Task — `final`, зависимости `private readonly` в конструкторе (DI Laravel), данные операции — в
  `run($данные)`. Полностью повторяет `listvafitness/app/Tasks/*`.
- **Граница контракта `Authenticatable`.** Контроллеры/Task оперируют контрактом `Authenticatable`
  (`$request->user()`), модель `App\Models\User` живёт только внутри `UserRepository` (там `assert(...)`
  сужает тип для PHPStan L10). Так arch-барьер зелёный без каста `as`, а L10 не видит «undefined method
  on Authenticatable».
- **PHPStan-baseline — минимальный и обоснованный.** 8 строк = только framework-scaffolding, который мы
  сознательно не рефакторили под бизнес-логику (email-verification контроллеры, throttle-key в
  LoginRequest). Наши файлы типизированы идеально, в baseline не входят.

## Как тестировали

- **Arch red→green:** сырой Breeze — RED (`ProfileUpdateRequest` использует `App\Models\User`); после
  рефактора — `PASS Tests\Feature\ArchitectureTest` (2 assertions). Grep: `App\Models` встречается только
  под `app/Models/` и `app/Data/Repositories/`.
- **Гейты:** Pint `--test` passed (`declare(strict_types=1)` везде); PHPStan L10 `[OK] No errors`;
  Pest `Tests: 33 passed` (6 UserRepository + 2 arch + весь Breeze-набор), 0 fail/skip; `pnpm run build` ✓.
  Перепрогнаны после переименования `handle→run`.
- **Живая приёмка (реальный HTTP, http://localhost):** `GET /register` 200 → `POST /register` 302 →
  `/dashboard` 200; юзер в БД = 1; `POST /logout` 302; гость на `/dashboard` → 302 `/login`. Строка
  «Cookbook: Greenfield Enterprise» рендерится клиентом (SPA без SSR) — подтверждена в собранном бандле.

## Пользовательская документация

User-visible: появились регистрация/логин/дашборд. Клиентского `CLAUDE.md` как AI-артефакта в целевой
репе нет — не создавали. `cbook/README.md` уже под целевой стек; отдельной правки под auth не потребовалось
(скелет, не пользовательская фича). Проверено — правок не нужно.

## Итог

Фронт-скелет (Inertia+Vue3+TS+Tailwind) поднят, авторизация работает в браузере, все контроллеры Breeze
приведены к слоям (Eloquent по User — только в `UserRepository`), arch-барьер/L10/Pint/Pest зелёные.
Побочный результат ценнее скелета: зафиксирован **канон Task** проекта (пустая база + `run($данные)` +
`final readonly`), выверенный по north-star референсу `listvafitness`. Риски: baseline на 8 Breeze-мест —
закрывать по мере обрастания auth бизнес-логикой; SPA без SSR — живая проверка контента идёт через бандл.
