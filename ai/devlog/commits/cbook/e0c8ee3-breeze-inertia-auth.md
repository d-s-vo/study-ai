---
repo: cbook
authored_hash: e0c8ee3ea9dc7e522fbaa3f5928cdb82623a750a
patch_id: c5173dcc4bfc3d506715982d339812f64cdf79c2
branch: feat/breeze-inertia-auth
feat: FEAT-004
date: 2026-07-30
final_hash:
---

# cbook@e0c8ee3 — feat: скелет фронтенда на Inertia/Vue и авторизация через слой репозиториев

> Коммит-сообщение (как в клиентском репо): `feat: скелет фронтенда на Inertia/Vue и авторизация через слой репозиториев`

## Кратко (для инженера)

- **Breeze-скаффолд (Inertia+Vue3+TS+Tailwind).** `breeze:install vue --typescript --pest` развернул
  фронт-стек, контроллеры Auth, FormRequest'ы, `routes/auth.php`, миграции, Pest-тесты Auth. Node — pnpm
  (`pnpm-lock.yaml`). Это мех. поставка стартер-кита.
- `app/Data/Repositories/UserRepository.php` (`final`) — единственное место Eloquent по `User`:
  `create/setPassword/updateProfile/delete`. Мутации принимают `Authenticatable` + `assert(instanceof User)`.
- `app/Tasks/RegisterUserTask.php` (`final`) — бизнес-операция регистрации: конструктор с `readonly`
  зависимостью, `run(name,email,plainPassword): Authenticatable`.
- `app/Tasks/BaseTask.php` — приведён к пустому abstract-маркеру (снят `handle(): mixed`).
- Контроллеры `Auth/RegisteredUserController`, `Auth/NewPasswordController`, `Auth/PasswordController`,
  `ProfileController` + `Http/Requests/ProfileUpdateRequest` — все прямые вызовы Eloquent по `User`
  заменены делегированием в `UserRepository`/`RegisterUserTask`; убраны `use App\Models\User`.
- `resources/js/Pages/Dashboard.vue` — дефолт Breeze заменён каркасом-заглушкой дашборда.
- `phpstan-baseline.neon` — 8 записей только на нетронутый Breeze-scaffold (`$request->user(): User|null`).

## Детально (для новичка)

### `app/Data/Repositories/UserRepository.php`
**Репозиторий** — слой, который единственный ходит в базу данных через Eloquent (ORM Laravel). Наше
жёсткое правило (STRICT RULE 2): модели (`User`) и запись в БД разрешены **только здесь**, чтобы
логика не «размазывалась» по контроллерам. Breeze же по умолчанию пишет `User::create(...)` прямо в
контроллере — это правило нарушает. Мы перенесли все операции над пользователем (создать, сменить
пароль, обновить профиль, удалить) сюда. Приём с `Authenticatable` + `assert(...)`: контроллеру Laravel
отдаёт «текущего пользователя» как абстрактный тип `Authenticatable` (контракт), а не как класс `User`.
Если бы метод репозитория требовал именно `User`, этот тип «протёк» бы в контроллер (и нарушил барьер).
Поэтому метод принимает контракт, а внутри `assert($user instanceof User)` сужает тип — это и проверка,
и подсказка статическому анализатору (PHPStan L10), что дальше доступны методы Eloquent.

### `app/Tasks/RegisterUserTask.php` и `app/Tasks/BaseTask.php`
**Task** — один бизнес-сценарий как класс (здесь: «зарегистрировать пользователя»). Контроллер не
делает логику сам, а зовёт Task. `RegisterUserTask` в конструкторе получает `UserRepository` (Laravel
подставляет его автоматически — dependency injection), а данные операции принимает методом
`run($name,$email,$password)`. Пометки: `final` (наследоваться от готовой операции нельзя),
`readonly` (внедрённую зависимость нельзя подменить после создания). Метод назван `run` (а не `handle`),
класс-предок `BaseTask` — **пустой**: у разных Task-ов разные наборы аргументов, поэтому единую
сигнатуру в предке зафиксировать нельзя (PHP выдал бы фатальную ошибку несовместимости). Этот канон
выверен по референс-проекту (см. «Почему так»).

### Контроллеры Auth + `ProfileUpdateRequest`
Все они теперь «тонкие»: приняли провалидированный запрос → позвали репозиторий/Task → вернули ответ.
Пример: регистрация раньше делала `User::create()` в контроллере, теперь — `RegisterUserTask::run()`.
Сброс пароля (`NewPasswordController`) типизирует пользователя в замыкании как `Authenticatable` и зовёт
`UserRepository::setPassword()`. `ProfileUpdateRequest` (правило уникальности email) больше не ссылается
на класс `User` — уникальность задаётся по таблице (`Rule::unique('users','email')`), а идентификатор
берётся через контракт (`getAuthIdentifier()`). Так arch-тест (который запрещает `App\Models` вне
репозиториев) снова зелёный.

### `resources/js/Pages/Dashboard.vue` и Breeze-скаффолд
Остальное — стандартная поставка Laravel Breeze: страницы входа/регистрации/профиля на Vue, лэйауты,
TypeScript-конфиг, Vite/Tailwind, набор Pest-тестов авторизации. Это генерируется командой и правится
минимально (Dashboard — заглушка-каркас). Menеджер пакетов Node — pnpm (быстрый, строгий node_modules).

## Почему так, а не иначе

- **Стандартный Breeze без рефактора** — отклонён: нарушает STRICT RULE 2 (Eloquent в контроллере),
  роняет arch-тест. Рефактор через репозиторий — суть задачи (учебный кейс защиты слоя данных).
- **Task с `handle(): mixed` (данные через конструктор)** — отклонён в пользу `run($данные)` с пустым
  `BaseTask`: сверка с north-star референсом `listvafitness` (студия whyme-agency) показала именно этот
  канон — пустой `AbstractTask`, `run($данные)`, `final readonly`. Приняли его как канон Task проекта.
- **Отдельный DTO входа регистрации** — отклонён: три скаляра достаточно; DTO вводим доменным сущностям
  (Recipe) позже. В референсе тоже есть Task-и на скалярах.
- **Широкий PHPStan-baseline** — отклонён: baseline минимален (8 строк, только framework-scaffolding),
  наши файлы типизированы без подавлений.

## Связи

- Фича: `../../features/FEAT-004-breeze-inertia-auth/impl.md` · `spec.md`.
- Канон слоёв/изоляция Eloquent: `../../adr/003-layered-architecture.md`; стек: `adr/002`; переписывание: `adr/006`.
- Референс канона Task: `listvafitness` (`app/Tasks/*`, `vendor/whyme-agency/laravel-foundation` — пустые `AbstractTask`).
