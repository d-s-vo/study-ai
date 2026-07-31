---
repo: cbook
authored_hash: 7ff6cf8f97cb99047f3b518891c555da3d014863
patch_id: fd447df671b5533f9e4ab1b3905baa2f54abfc0a
feat: FEAT-006
branch: feat/user-dto
reviewer_model: Opus 4.8
review_date: 2026-07-31
verdict: PASS
blockers_total: 0
blockers_open: 0
resolved_by: []
---

# cbook@7ff6cf8 — REVIEW — fix: не регистрировать генератор ts-типов в проде

**Verdict:** PASS
**Blocking findings:**
- нет
**Non-blocking notes:**
- нет
**Evidence:**
- **Узкий скоуп §6** (фикс blocker'а + WARN ревью `fd0e5fe-review.md`); диф мал (3 файла), проверен по
  существу как закрытие находок + отсутствие регрессий.
- `git show 7ff6cf8`: (1) `bootstrap/providers.php` — `TypeScriptTransformerServiceProvider` убран,
  файл вернулся к состоянию до fd0e5fe (только `AppServiceProvider`); (2) `AppServiceProvider::register()`
  — условная регистрация под `class_exists(TypeScriptTransformerApplicationServiceProvider::class)`;
  (3) `UserDataTest` — `missing('auth.user.created_at'/'updated_at')` в guest- и authed-Inertia-тестах.
- **Корректность гарда (адверсариально, семантика PHP):** `use`-импорт НЕ триггерит автолоад
  (compile-time алиас); `::class`-константа на имени класса резолвится в строку БЕЗ автолоада (даже для
  отсутствующего класса — просто FQCN-строка, без ошибки); `class_exists(..., $autoload=true)` пытается
  автолоадить и чисто возвращает `false` при отсутствии пакета — фатала нет. Дочерний
  `App\Providers\TypeScriptTransformerServiceProvider` (extends dev-only базы) теперь упоминается ТОЛЬКО
  как `::class`-строка внутри гарда → его файл в проде никогда не загружается → фатал резолвинга
  родителя недостижим. Генерация composer-классмапы (`--no-dev` + `optimize`) файлы мапит, но не
  объявляет классы — этот путь тоже безопасен.
- **Прод-сценарий доказан автором живьём** (impl-отчёт): чистая копия, `composer install --no-dev`
  (включая `package:discover` в post-autoload-dump) EXIT 0; `artisan optimize` чист (CACHE_STORE=file;
  database-вариант падал лишь из-за отсутствия MySQL-драйвера в контейнере проверки — среда, не код);
  `vendor/` без пакета. Blocking #1 исходного ревью закрыт.
- **Dev-поведение не сломано:** при установленном пакете `class_exists` → true → провайдер регистрируется
  в `register()` (та же фаза, что и `bootstrap/providers.php`) → `typescript:transform` доступен.
- **WARN закрыт мутационно:** реверт middleware к `'user' => $user` (сырая модель) теперь ловится —
  `$hidden` у `User` не скрывает timestamps, `auth.user.created_at` появился бы в пропсах →
  `missing('auth.user.created_at')` падает. Тест перестал быть слеп к регрессии DTO→модель
  (STRICT RULE 4). Guest-ассерты timestamps при `user === null` избыточны, но безвредны.
- **Гейты (отчёт автора):** Pest 38 passed / 122 assertions, PHPStan L10 No errors, Pint pass.
- **Чистота:** стоп-словарь по дифу (grep -iE) — 0 совпадений; комментарий в AppServiceProvider —
  человеческий стиль, по делу; сообщение `fix: не регистрировать генератор ts-типов в проде` —
  conventional (`fix:`), без следов системы.
- **Регрессии вокруг:** прочего в дифе нет; `HandleInertiaRequests`/`UserData`/типы не тронуты.
**Suggested next:** none

## Рубрика (сокращённая, узкий скоуп §6)

☑ Находка Blocking #1 `fd0e5fe-review.md` закрыта (гард корректен, прод-бут доказан живьём)
☑ WARN (altitude-gap теста) закрыт (missing created_at/updated_at — ловит мутацию DTO→модель)
☑ Регрессий нет (диф минимален; dev-поток transform сохранён)
☑ Атомарность (один смысл: условная регистрация dev-провайдера) · ☑ Чистота (стоп-словарь, conventional)

## Журнал закрытия находок

- Находок нет. Этот коммит закрывает Blocking #1 и WARN ревью `fd0e5fe-review.md` (отметки — там).

## Связи

- Исходное ревью с blocker'ом: `fd0e5fe-review.md` (рядом; вердикт цепочки обновлён на PASS).
- Разбор «почему» исходного коммита (ADR-009): `fd0e5fe-user-dto.md`.
- Фича: `../../features/FEAT-006-user-dto/impl.md` · `spec.md`.
- Гайд ревью: [`../../guides/commit-review.md`](../../guides/commit-review.md) §6 (фикс-цикл, узкий скоуп).
