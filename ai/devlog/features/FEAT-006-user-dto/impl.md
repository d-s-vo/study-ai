---
feat: FEAT-006
repos: [cbook]
tags: [backend, frontend, dto, spatie-data, typescript, inertia, strict-rule-4]
class: 'закрытие advisory-долга FEAT-004 — сырой User в Inertia → UserData (Spatie Data) + автоген TS-типов'
prevention: 'Pest: негативный тест на утечку password/remember_token в DTO + Inertia-assert формы auth.user (guest=null, authed=whitelist)'
---

# FEAT-006: UserData DTO наружу + автоген TS-типов — Implementation

## Статус: DONE (передано пользователю на доставку)
## Дата: 2026-07-31
## Коммит: fd0e5fe (ветка feat/user-dto, от origin/develop @ e0c8ee3)

## Step-0 (свежесть базиса)
HEAD == origin/develop == e0c8ee3, дерево чистое → базис свежий. Worktree был без зависимостей:
`composer install` через образ `laravelsail/php84-composer` (хостового PHP нет), `pnpm install --frozen-lockfile`.

## Что сделано

**Backend — контракт до фронта.**

| Файл | Изменение |
|---|---|
| `app/Data/UserData.php` | **новый**, `final extends Spatie\LaravelData\Data`, `#[TypeScript]`. Поля только для фронта: `id:int`, `name:string`, `email:string`, `email_verified_at:?CarbonImmutable`. Пароля/remember_token нет. |
| `app/Http/Middleware/HandleInertiaRequests.php` | `'user' => $request->user()` → `$user = $request->user(); … 'user' => $user !== null ? UserData::from($user) : null`. Сырой модели наружу больше нет. |
| `app/Providers/TypeScriptTransformerServiceProvider.php` | **новый** — конфигурация генератора (v3 API, см. отклонение). Коллектор на `app/Data`, вывод `resources/js/types/generated.d.ts`, замены типов `CarbonImmutable`/`DateTimeInterface` → `string`, `withoutManifest()`. |
| `bootstrap/providers.php` | регистрация `TypeScriptTransformerServiceProvider`. |
| `composer.json` | require-dev: `spatie/laravel-typescript-transformer: ^3.3`. |

**Автоген TS-типов.** `sail artisan typescript:transform` → `resources/js/types/generated.d.ts` (коммитится):
```
declare namespace App { namespace Data {
  export type UserData = { id: number, name: string, email: string, email_verified_at: string | null };
} }
```
Детерминированный вывод (4 скаляра, без Lazy/Optional), `email_verified_at` схлопнут в `string | null` заменой типа.

**Frontend — types-first, null-safety.**

| Файл | Изменение |
|---|---|
| `resources/js/types/index.d.ts` | удалён рукописный `interface User`; `PageProps.auth.user: App.Data.UserData \| null` (ссылка на глобальный ambient из `generated.d.ts`, который попадает в программу через `include: resources/js/**/*.ts`). |
| `resources/js/Layouts/AuthenticatedLayout.vue` | 3 обращения `$page.props.auth.user.{name,email}` → optional chaining `?.` (без `!`/`as`). |
| `resources/js/Pages/Profile/Partials/UpdateProfileInformationForm.vue` | `user.name/.email` → `user?.name ?? ''`/`user?.email ?? ''`; `user.email_verified_at` → `user?.email_verified_at`. |

**Тесты.** `tests/Feature/UserDataTest.php` (**новый**, 5 кейсов): сборка из модели (id/name/email/email_verified_at);
unverified → null; **негативная утечка** (`->toArray()` не содержит `password`/`remember_token`); Inertia-assert
guest на `/` → `auth.user === null`; authed на `/dashboard` → `auth.user` содержит id/name/email и **не** содержит
password/remember_token.

## Отклонения от spec

1. **Версия и способ конфигурации трансформера (вынужденное).** Spec предполагал v2-поток
   (`config/typescript-transformer.php` + коллектор `DataTypeScriptCollector` из laravel-data). Реальность:
   `spatie/laravel-typescript-transformer` **v2.x нерешаемо конфликтует** с деревом Laravel 12 —
   `phpdocumentor/reflection-docblock 6.x` тянет `phpdocumentor/type-resolver ^2.0`, а трансформер v2 требует
   `^1.6.2` (взаимоисключение; даунгрейд задел бы phpstan/larastan). Поэтому взят **v3.3**, где конфиг — это
   `App\Providers\TypeScriptTransformerServiceProvider` (fluent-builder), а laravel-data-коллектор недоступен
   (его `DataTypeScriptTransformer` наследует v2-базу `DtoTransformer`, отсутствующую в v3). Использован
   нативный `AttributedClassTransformer` + атрибут `#[TypeScript]` на DTO — для простого 4-скалярного DTO
   вывод идентичен. Все функциональные Acceptance Criteria выполнены (require-dev, конфиг, коллектор на App\Data,
   `typescript:transform` — то же имя команды, generated.d.ts коммитится).
2. **`email_verified_at: ?CarbonImmutable` (а не `?string`).** Это явно предусмотренная спекой альтернатива
   («или `?CarbonImmutable` с TS-маппингом в `string|null`»). Причина выбора: `UserData::from($model)` через
   `ModelNormalizer` отдаёт значение атрибута как `Carbon` (каст `datetime`), что несовместимо с `?string`
   (TypeError). С типом `CarbonImmutable` глобальный `DateTimeInterfaceCast` Spatie корректно приводит значение,
   на выходе (`toArray`/Inertia) сериализуется в ISO-строку, а TS-замена типа даёт `string | null`. Это позволило
   сохранить **дословную** формулировку критерия — `UserData::from($user)` в middleware, без обращения к
   `App\Models\User` (иначе бы упал arch-барьер: `App\Models` разрешён только в репозиториях).

## Ключевые решения по ходу реализации

- **DTO и middleware — model-free (arch-барьер).** Pest ArchitectureTest запрещает `App\Models` вне
  `App\Data\Repositories`/Factories/Seeders и сканирует `app/`. Поэтому ни middleware, ни DTO не ссылаются на
  `App\Models\User`: сборка идёт через `UserData::from($user)` (принимает `mixed`/`Authenticatable`), Spatie
  `ModelNormalizer` вытягивает только объявленные в DTO поля — `password`/`remember_token` физически не читаются.
- **generated.d.ts — глобальный ambient, без `import`.** Файл содержит `declare namespace App { … }` (скрипт, не
  модуль). `import './generated'` в index.d.ts дал бы TS2306 — убран; тип доступен глобально, т.к. `.d.ts`
  попадает под `include: resources/js/**/*.ts`.
- **`withoutManifest()`** — чтобы v3 не плодил `typescript-transformer-manifest.json` (build-кэш) в коммите.
- **Null-safety без костылей** — только optional chaining и `?? ''`, 0 `any`/`as`/`!` в новом фронт-коде.
- **PHPStan-baseline не тронут** (остаётся 8 Breeze-строк FEAT-004; снимает FEAT-007).

## Гейты (все зелёные)
- **Pint** `--test`: passed (`declare(strict_types=1)` везде).
- **PHPStan L10**: `[OK] No errors` (baseline не расширялся; сужение типа User не потребовалось — `from()` берёт mixed).
- **Pest** (через `gate.sh backend-tests`): **38 passed** (33 FEAT-004 + 5 новых), 0 fail/skip, 118 assertions.
  Нюанс: Inertia-render тесты требуют `public/build/manifest.json` → сначала `pnpm build`, потом `test`.
- **pnpm build** (через `gate.sh frontend-build`, `vue-tsc && vite build`): ✓; отдельный `vue-tsc --noEmit`: ✓.

## Живая приёмка (реальный HTTP, изолированный стенд :8120, compose-проект `cbook-userdto`, порты 8120/5193/3120)
- **Guest** `GET /` → `auth.user === null`, Welcome рендерится (200).
- **Register** `POST /register` → 302 → `/dashboard`; payload `auth.user` = ровно `{id, name, email, email_verified_at}`
  (keys: email, email_verified_at, id, name) — **нет** created_at/updated_at/password/remember_token.
- **Login** `POST /login` → 302 → `/dashboard`; тот же чистый DTO.
- Стенд снят (`sail down -v`).

## Пользовательская документация
Внутреннее изменение контракта Inertia-пропсов; user-visible поведение не меняется. README уже описывает
`typescript:transform` — актуально, правок публичной доки не требуется (checked, no changes needed).

## Фикс по ревью (коммит 7ff6cf8)

Ревью `fd0e5fe` вернуло FAIL (`ai/devlog/commits/cbook/fd0e5fe-review.md`). Fix-forward той же веткой:

- **Blocker — безусловная регистрация dev-провайдера.** `TypeScriptTransformerServiceProvider` наследует базу из
  require-dev-пакета; строка в `bootstrap/providers.php` инстанцировала его на каждом буте → `composer install
  --no-dev` (и любой прод-запрос) падал бы фаталом «class not found». Фикс: провайдер убран из
  `bootstrap/providers.php`; регистрация — в `AppServiceProvider::register()` под гардом
  `class_exists(TypeScriptTransformerApplicationServiceProvider::class)` (нет пакета → класс провайдера вообще
  не загружается; `::class`-константа автолоад не триггерит).
- **WARN — сторожевая сила негативных тестов.** `missing('auth.user.password'/'remember_token')` не ловили
  регрессию «DTO → сырая модель» (их и так прячет `$hidden`). В оба Inertia-теста добавлены
  `->missing('auth.user.created_at')` и `->missing('auth.user.updated_at')` — поля, которые сырая модель
  реально протекла бы.
- **Доказательство прод-сценария** (чистая копия в scratchpad, без порчи vendor/ worktree):
  `composer install --no-dev` — OK (post-autoload-dump `package:discover` прошёл); явный `php artisan
  package:discover` — EXIT 0; `php artisan optimize` — все секции DONE (config/events/routes/views/laravel-data;
  `CACHE_STORE=file` — в контейнере проверки нет MySQL-драйвера, это среда, не код); `php artisan about` — бут ок;
  `vendor/spatie/laravel-typescript-transformer` отсутствует. Worktree остался с dev-зависимостями (рабочее состояние).
- **Гейты после фикса:** Pint passed; PHPStan L10 No errors; Pest (gate `backend-tests`) **38 passed**
  (122 assertions); `typescript:transform` в dev-режиме работает, `generated.d.ts` без diff (детерминирован).
- Разбор коммита по ADR-009: `ai/devlog/commits/cbook/fd0e5fe-user-dto.md` (цепочка fd0e5fe + 7ff6cf8).

## Итог
Advisory-долг FEAT-004 закрыт: наружу в Inertia уходит `UserData` (Spatie Data), а не сырая модель (STRICT RULE 4);
TS-тип `User` больше не рукописный, а автогенерируемый (`App.Data.UserData`), `auth.user` честно nullable, все
потребители null-safe. Границы соблюдены: baseline (FEAT-007) и axis/tsconfig (FEAT-008) не тронуты. Доставка — за владельцем.
