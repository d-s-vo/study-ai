---
repo: cbook
authored_hash: fd0e5fea37819c0e3f507738629bc9d2ce0ef416
patch_id: f870bb6f43f98fcd6b5cf51d70c1881c0a4cfff2
branch: feat/user-dto
feat: FEAT-006
date: 2026-07-31
final_hash:
fix_chain:
  - hash: 7ff6cf8f97cb99047f3b518891c555da3d014863
    patch_id: fd447df671b5533f9e4ab1b3905baa2f54abfc0a
    message: 'fix: не регистрировать генератор ts-типов в проде'
---

# cbook@fd0e5fe — feat: отдавать текущего пользователя в Inertia через DTO и генерировать TS-типы из слоя данных

> Коммит-сообщение (как в клиентском репо): `feat: отдавать текущего пользователя в Inertia через DTO и генерировать TS-типы из слоя данных`
> Итоговая цепочка: `fd0e5fe` (фича) + `7ff6cf8` (`fix: не регистрировать генератор ts-типов в проде` — закрытие blocker'а ревью).

## Кратко (для инженера)

- **`app/Data/UserData.php`** (НОВЫЙ) — `final` DTO на Spatie Data, `#[TypeScript]`; ровно 4 поля наружу:
  `id:int`, `name:string`, `email:string`, `email_verified_at:?CarbonImmutable` (в JSON — ISO-строка/`null`).
  Пароля/`remember_token` в DTO нет — они физически не читаются из модели.
- **`app/Http/Middleware/HandleInertiaRequests.php`** — `'user' => $request->user()` (сырая Eloquent-модель)
  → `'user' => $user !== null ? UserData::from($user) : null`. Ссылки на `App\Models\User` в middleware нет.
- **`app/Providers/TypeScriptTransformerServiceProvider.php`** (НОВЫЙ) — конфигурация генератора TS-типов
  (v3 fluent-builder): `AttributedClassTransformer` + `EnumTransformer`, скан `app/Data`, замены
  `CarbonImmutable`/`DateTimeInterface` → `string`, вывод `resources/js/types/generated.d.ts`, `withoutManifest()`.
- **Регистрация провайдера** — в `fd0e5fe` была безусловной строкой в `bootstrap/providers.php` (это blocker,
  см. ниже); после `7ff6cf8` — условная в `AppServiceProvider::register()` под гардом
  `class_exists(TypeScriptTransformerApplicationServiceProvider::class)`.
- **`composer.json`/`composer.lock`** — require-dev: `spatie/laravel-typescript-transformer ^3.3` (+ dev-транзитивы:
  `spatie/typescript-transformer`, `roave/better-reflection`, `spatie/file-system-watcher` и др.).
- **`resources/js/types/generated.d.ts`** (НОВЫЙ, коммитится) — автоген: глобальный ambient
  `App.Data.UserData = { id:number, name:string, email:string, email_verified_at:string|null }`.
- **`resources/js/types/index.d.ts`** — рукописный `interface User` удалён; `PageProps.auth.user:
  App.Data.UserData | null` (тип стал честно nullable).
- **`AuthenticatedLayout.vue`, `UpdateProfileInformationForm.vue`** — null-safety потребителей `auth.user`:
  `?.` и `?? ''`, без `!`/`as`/`any`.
- **`tests/Feature/UserDataTest.php`** (НОВЫЙ) — 5 кейсов: форма DTO из модели; unverified → `null`;
  негативная утечка (`toArray()` без `password`/`remember_token`); Inertia guest → `auth.user === null`;
  Inertia authed → whitelist-поля присутствуют, `password`/`remember_token`/`created_at`/`updated_at`
  отсутствуют (последние два добавлены фикс-коммитом).

## Детально (для новичка)

### Зачем DTO вместо `$request->user()`
STRICT RULE 4 проекта: в Inertia/Vue уходят **только DTO** (Spatie Data). Сырая Eloquent-модель наружу — это
нетипизированный контракт: фронт получает всё, что отдаст сериализация модели (включая `created_at`/`updated_at`
и любые будущие колонки), а защита от утечки чувствительных полей держится на одном `$hidden`. DTO переворачивает
модель безопасности: наружу идёт **whitelist** из 4 полей, всё остальное не попадает в payload по построению.
Это закрытие advisory-долга ревью FEAT-004 (`e0c8ee3-review.md`).

### Как `UserData::from($user)` работает без ссылки на модель
Arch-барьер (Pest) запрещает `App\Models` вне `app/Data/Repositories`. Поэтому middleware передаёт в `from()`
результат `$request->user()` (`?Authenticatable`) как есть: Spatie `ModelNormalizer` сам вытягивает из модели
только поля, объявленные в конструкторе DTO. `email_verified_at` объявлен `?CarbonImmutable` (вариант, явно
предусмотренный спекой): модельный каст отдаёт Carbon, глобальный `DateTimeInterfaceCast` приводит его, наружу
JSON-сериализуется ISO-строка, а в TS замена типа даёт `string | null`. Вариант `?string` дал бы TypeError.

### Почему трансформер v3, а не v2 из спеки
Спека предполагала v2-поток (`config/typescript-transformer.php` + коллектор laravel-data). Но v2 нерешаемо
конфликтует с деревом Laravel 12: `phpdocumentor/reflection-docblock 6.x` требует `phpdocumentor/type-resolver ^2.0`,
а трансформер v2 — `^1.6.2`; даунгрейд зацепил бы phpstan/larastan. Взят v3.3, где конфиг — сервис-провайдер
(fluent-builder), а вместо недоступного laravel-data-коллектора (наследует отсутствующую в v3 базу) — нативный
`AttributedClassTransformer` + атрибут `#[TypeScript]` на DTO. Для плоского 4-скалярного DTO вывод идентичен.
Функциональные AC спеки выполнены (require-dev, конфиг, скан `app/Data`, та же команда `typescript:transform`,
`generated.d.ts` коммитится).

### Blocker ревью и фикс `7ff6cf8`
В `fd0e5fe` провайдер был прописан в `bootstrap/providers.php` **безусловно**, а его базовый класс живёт в
require-dev-пакете. Laravel инстанцирует все провайдеры из этого файла на каждом буте; PHP резолвит родителя
в момент объявления дочернего класса → `composer install --no-dev` (который сам запускает `package:discover`)
падал бы фаталом «Class … not found» ещё на установке, и любой прод-запрос не поднялся бы. Фикс: провайдер убран
из `bootstrap/providers.php`; регистрация перенесена в `AppServiceProvider::register()` под гард
`class_exists(TypeScriptTransformerApplicationServiceProvider::class)` — есть dev-пакет → генератор доступен,
нет пакета (прод) → класс провайдера вообще не загружается (`::class`-константа автолоад не триггерит). Прод
кодоген и не нужен: `generated.d.ts` коммитится. Тем же фикс-коммитом закрыт minor ревью: в Inertia-тесты
добавлены `->missing('auth.user.created_at')`/`->missing('auth.user.updated_at')` — именно эти поля протекли бы
при регрессии «DTO → сырая модель» (`password`/`remember_token` прятал бы и `$hidden`, их отсутствие регрессию
не ловит).

### Доказательство прод-сценария (после фикса)
В чистой копии дерева (без `vendor/`): `composer install --no-dev` — OK (включая post-autoload-dump
`package:discover`); явные `php artisan package:discover` — EXIT 0; `php artisan optimize` — DONE
(config/events/routes/views/laravel-data; кэш-стор file — в контейнере проверки нет MySQL);
`php artisan about` — фреймворк бутится. Пакет `spatie/laravel-typescript-transformer` в `vendor/` отсутствует.

## Почему так, а не иначе (отклонения от spec)

1. **Трансформер v3.3 + конфиг-провайдер вместо v2 + config-файла** — вынужденно (конфликт зависимостей, выше);
   интент спеки (автоген из DTO, dev-only, тот же CLI-контракт) сохранён полностью.
2. **`email_verified_at: ?CarbonImmutable`** — разрешённая спекой альтернатива `?string`; выбрана, чтобы
   сохранить дословный AC `UserData::from($user)` в middleware без обращения к `App\Models\User`.
3. **Условная регистрация провайдера** (фикс-коммит) — приведение реализации к уже записанному AC спеки
   («прод не нужен, т.к. `generated.d.ts` коммитится»); спека-дельта не требуется.

## Гейты (итог цепочки fd0e5fe + 7ff6cf8)

- Pint `--test` — passed; PHPStan **L10** — `[OK] No errors` (baseline FEAT-004 не расширялся);
- Pest — **38 passed** (122 assertions), 0 fail/skip;
- `pnpm build` (`vue-tsc && vite build`) — ✓; `typescript:transform` идемпотентен (повторный прогон — без diff).
- Живая приёмка (изолированный Sail-стенд :8120): guest `/` → `auth.user:null`; register/login → 302 → dashboard,
  payload `auth.user` = ровно `{id, name, email, email_verified_at}`.

## Связи

- Ревью коммита: `fd0e5fe-review.md` (рядом; blocker закрыт `7ff6cf8`).
- Фича: `../../features/FEAT-006-user-dto/` (`spec.md`, `impl.md`).
- Долг-первоисточник: `e0c8ee3-review.md` (advisory FEAT-004).
