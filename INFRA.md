# INFRA — локальное развёртывание проекта

Мануал: как руками поднять проект cbook (Laravel 11 + Filament + Inertia/Vue) на локальной машине, какие порты он занимает и как им управлять. Актуален на 2026-08-05.

---

## 1. Что нужно на машине

- **Docker-демон** — у нас OrbStack (подойдёт и Docker Desktop). Весь PHP-стек живёт в контейнерах: на хосте **нет и не нужно** ни php, ни composer.
- **Node.js + pnpm** — фронт (Vite) собирается на хосте.
- Код проекта — worktree `cbook/` в корне workspace. Если его нет или он устарел, из корня workspace выполнить `./scripts/sync.sh`.

## 2. Первый запуск с нуля

Все шаги выполняются из папки проекта:

```bash
cd cbook
```

### Шаг 1. Установить PHP-зависимости

Пока нет папки `vendor/`, команда `sail` недоступна, поэтому первый `composer install` делаем через одноразовый docker-образ:

```bash
docker run --rm -v "$(pwd)":/var/www/html -w /var/www/html laravelsail/php84-composer:latest composer install --ignore-platform-reqs
```

### Шаг 2. Создать .env

```bash
cp .env.example .env
```

В `.env` добавить/проверить две строки (чтобы файлы, созданные контейнером, принадлежали вашему пользователю на macOS):

```
WWWUSER=501
WWWGROUP=20
```

Порты в `.env.example` уже настроены на значения по умолчанию (см. карту портов ниже) — для одиночного стенда менять ничего не нужно.

### Шаг 3. Сгенерировать ключ приложения

```bash
docker run --rm -v "$(pwd)":/var/www/html -w /var/www/html laravelsail/php84-composer:latest php artisan key:generate
```

### Шаг 4. Поднять контейнеры

```bash
./vendor/bin/sail up -d
```

Поднимутся четыре контейнера: `laravel.test` (приложение), `mysql`, `redis`, `mailpit`. Проверить, что всё живо: `docker ps` — у контейнеров должен быть статус `healthy`/`Up`.

### Шаг 5. Прогнать миграции

```bash
./vendor/bin/sail artisan migrate
```

### Шаг 6. Собрать фронт

Без этого шага страница отдаёт 500 (`ViteManifestNotFoundException`).

```bash
pnpm install
pnpm dev        # dev-режим с hot-reload (держать запущенным)
# или разовая сборка без dev-сервера:
pnpm build
```

### Шаг 7. Проверить

- Приложение: http://localhost
- Админка Filament: http://localhost/admin
- Почтовый ящик Mailpit: http://localhost:8025

### Шаг 8. Завести администратора

В админ-панель (`/admin`) пускают только пользователей с флагом `is_admin` **и** подтверждённой почтой (`User::canAccessPanel()`). Отдельной команды «создать админа» нет — права выдаются существующему пользователю:

1. Зарегистрироваться на сайте: http://localhost/register
2. Подтвердить почту: письмо со ссылкой никуда не уходит, оно перехватывается Mailpit — открыть http://localhost:8025, найти письмо и кликнуть ссылку подтверждения.
3. Выдать права администратора:

```bash
./vendor/bin/sail artisan app:grant-admin <email>
```

После этого http://localhost/admin открывается под этим пользователем.

## 3. Ежедневный запуск (стенд уже развёрнут)

```bash
cd cbook
./vendor/bin/sail up -d
pnpm dev            # если нужен фронт в dev-режиме
```

## 4. Остановка и снос

| Команда | Что делает |
|---|---|
| `./vendor/bin/sail stop` | Гасит контейнеры; данные БД остаются в volume |
| `./vendor/bin/sail down` | Удаляет контейнеры; данные БД остаются |
| `./vendor/bin/sail down -v` | Полный снос вместе с данными БД — только если БД не жалко |

## 5. Карта портов

### Основной стенд (`cbook/`)

| Сервис | Порт хоста | Что это |
|---|---|---|
| Laravel app | 80 | само приложение (`APP_PORT`) |
| Vite | 5173 | dev-сервер фронта (`pnpm dev`) |
| MySQL 8 | 3306 | общая dev-БД (внутри контейнера — тоже 3306) |
| Redis | 6379 | кэш/очереди |
| Mailpit UI | 8025 | веб-интерфейс перехваченной почты; SMTP — 1025 |
| Filament | — | отдельного порта нет: `/admin` поверх порта приложения |

### Стенды задач (`tasks/<slug>/`)

Параллельные стенды под фичи разводятся по портам формулой `базовый порт + idx*10`, где `idx` — индекс брони. Пример для idx 1:

| Сервис | Формула | idx 1 | Переменная `.env` |
|---|---|---|---|
| Laravel app | 8100 + idx·10 | 8110 | `APP_PORT` |
| Vite | 5173 + idx·10 | 5183 | `VITE_PORT` |
| MySQL 8 | 3100 + idx·10 | 3110 | `FORWARD_DB_PORT` (эфемерная БД) |
| Redis | 6379 + idx·10 | 6389 | `FORWARD_REDIS_PORT` |
| Mailpit SMTP | 1025 + idx·10 | 1035 | `FORWARD_MAILPIT_PORT` |
| Mailpit UI | 8025 + idx·10 | 8035 | `FORWARD_MAILPIT_DASHBOARD_PORT` |

Плюс каждому стенду задачи выдаётся свой номер логической БД Redis (`REDIS_DB`), чтобы стенды не пересекались по ключам.

Как создаются стенды задач (бронь, worktree, гейты тяжёлых операций) — это уже процесс разработки, а не развёртывание; см. `ai/guides/feature-workflow.md` и `ai/guides/coordination.md`.

## 6. Если что-то не работает

- **`/admin` отдаёт 403 Forbidden** — вы залогинены пользователем без прав админа или с неподтверждённой почтой. Подтвердить почту через Mailpit и выдать права: `sail artisan app:grant-admin <email>` (шаг 8). Если вы вообще не залогинены, будет не 403, а редирект на `/admin/login`.
- **Страница отдаёт 500 `ViteManifestNotFoundException`** — не собран фронт: запустить `pnpm dev` или `pnpm build` (шаг 6).
- **Порт занят при `sail up`** — посмотреть, кто держит: `docker ps` (возможно, запущен стенд задачи с теми же портами) или `lsof -i :<порт>`.
- **Контейнер mysql не переходит в healthy** — подождать 20–30 секунд после первого запуска (инициализация БД); если не помогло — `./vendor/bin/sail logs mysql`.
- **Файлы из контейнера создаются от root** — в `.env` не заданы `WWWUSER`/`WWWGROUP` (шаг 2); после правки пересоздать контейнеры: `sail down && sail up -d`.
- Общая панель состояния workspace: `./scripts/status.sh`.
