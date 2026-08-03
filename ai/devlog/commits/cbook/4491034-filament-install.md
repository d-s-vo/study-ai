---
repo: cbook
authored_hash: 4491034b91c6aa8ce4e62b822cc8b5f1525cb61a
patch_id: d7f4e7b27eacf2dcf045ba96a7046f67b6b7e06c
branch: feat/filament-admin
feat: FEAT-013
date: 2026-08-03
---

# cbook@4491034 — установка админ-панели Filament

> Коммит-сообщение (как в клиентском репо): `chore: установка админ-панели Filament`

## Кратко (для инженера)

- `composer.json`/`composer.lock` — `filament/filament: ^5.0` (фактически ставится 5.7.5); `post-autoload-dump` дополнен `@php artisan filament:upgrade` (регенерирует опубликованные ассеты панели после каждого `composer install/update`, а не только при первой установке).
- `bootstrap/providers.php` — регистрация `App\Providers\Filament\AdminPanelProvider::class` рядом с существующим `AppServiceProvider`.
- `app/Providers/Filament/AdminPanelProvider.php` — новый, сгенерированный `php artisan make:filament-panel` и STRICT-доведённый: `declare(strict_types=1)` добавлен вручную (генератор его не проставляет). Панель: `id('admin')`, `path('admin')`, `login()`, `discoverResources`/`discoverPages`/`discoverWidgets` по неймспейсу `App\Filament\*`, стандартный набор middleware Filament (сессии/CSRF/куки), `authMiddleware([Authenticate::class])`.
- `.gitignore` — `+/public/css/filament`, `+/public/fonts/filament`, `+/public/js/filament` — это сгенерированные vendor-ассеты панели (публикуются `filament:upgrade`), не исходники проекта.
- `eslint.config.js` — `public/js/filament` добавлен в `ignores` — ESLint не должен линтить чужой скомпилированный JS.

## Детально (для новичка)

### Зачем это всё: установка Filament без затрагивания публичного фронтенда

Filament — это административная панель для Laravel: набор готовых Livewire-компонентов (таблицы, формы, виджеты), которые монтируются на отдельный префикс маршрутов (здесь — `/admin`) и живут собственным жизненным циклом сборки ассетов, полностью отдельным от Vite/Inertia/Tailwind, на которых построен публичный фронтенд (`resources/js`). Задача этого коммита — поставить пакет так, чтобы он ничего не задел в существующей сборке: ни `vite.config.ts`, ни `tailwind.config.js`, ни маршруты `web.php` не меняются.

### `composer.json` и `filament:upgrade`

Filament при обновлении версии публикует/перегенерирует свои статические ассеты (CSS/JS/шрифты) в `public/`. Хук `post-autoload-dump` — это composer-скрипт, который запускается автоматически после каждой установки/обновления зависимостей; добавление туда `artisan filament:upgrade` гарантирует, что ассеты панели всегда актуальны версии пакета, а не только сразу после `composer require`.

### `AdminPanelProvider`

`PanelProvider` — точка конфигурации одной панели Filament (в проекте панель одна — `admin`). `discoverResources`/`discoverPages`/`discoverWidgets` — автообнаружение классов по неймспейсу и директории (аналог автодискаверинга Policy в Laravel): новый `Resource`, положенный в `app/Filament/Resources`, подхватится без ручной регистрации. `login()` подключает встроенную страницу входа панели — отдельную от `/login` публичного сайта. Файл сгенерирован артизан-командой, поэтому по умолчанию не содержит `declare(strict_types=1)` — это добавлено вручную при STRICT-ревью, чтобы файл соответствовал общему правилу проекта (строгая типизация везде в `app/`).

### `.gitignore` и `eslint.config.js`

Опубликованные ассеты панели (`public/css/filament`, `public/js/filament`, `public/fonts/filament`) — сгенерированный код вендора, не пишется руками и не должен коммититься (аналогично `public/build` для Vite). ESLint, соответственно, не должен пытаться анализировать этот чужой JS как часть проектного кода — иначе линт будет падать на файлах, которые команда не пишет и не может поправить.

## Почему так, а не иначе

- **Отдельная директория `app/Filament` + автодискаверинг, а не ручная регистрация ресурсов** — стандартный путь Filament, выбран как единственный поддерживаемый способ (альтернатива — ручной список классов в провайдере — плодит дублирование при каждом новом Resource).
- **`declare(strict_types=1)` в сгенерированном файле** — не проектная норма Filament, а требование STRICT-ревью cbook: любой файл в `app/` обязан быть строго типизирован, независимо от происхождения (сгенерирован/написан руками).

## Связи

- ADR: `ai/adr/011-filament-admin-boundary.md` — граница Filament/Eloquent и супер-доступ админа, реализуемые следующими коммитами этой же фичи.
- Спека: `ai/devlog/features/FEAT-013-filament-admin/spec.md`.
- Следующий коммит: `cbook/b0a56ff-admin-access.md` (доступ к панели, `is_admin`, супер-доступ к рецептам).
