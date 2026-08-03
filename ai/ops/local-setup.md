# Локальное развёртывание — Laravel 12 (PHP 8.4), строгая слоистая архитектура (Task/Repository/DTO/Resolver) + Inertia.js + Vue 3 + TypeScript (Vite); Filament 5 — админ-панель

Локальный стенд — Laravel Sail (Docker Compose обвязка вокруг Laravel), поднимает полностью
локальный стек: PHP-приложение (app), MySQL 8 (mysql), Redis (кэш/очереди), Mailpit (перехват
почты), плюс фронтенд-тулчейн Vite/pnpm поверх Inertia.js + Vue 3 + TypeScript. Полный опросник по
стеку — `ai/guides/stack-specifics.md`, этот файл — операторская выжимка «как реально поднять стенд
руками».

Полностью локальный стек: собственная БД, кэш/очередь, бэкенд, фронтенд (и вспомогательные сервисы,
если есть). Развёрнуто из ветки `develop` (уточнить точное имя основной dev-ветки клиентского репо).

<!-- В этом профиле модуль M5 (контейнерный режим запуска агента) выключен — врезка про
     разницу «изолированный агент в контейнере» vs «привилегированный на хосте» не нужна. -->

## Env-профили

| Профиль | Файл | БД / кэш | Когда использовать |
|---|---|---|---|
| Локальный (по умолчанию) | `.env` | Sail `mysql` :3306, Redis :6379 | Повседневная разработка (`sail up -d`) |
| Тестовый | `.env.testing` | эфемерная БД + `RefreshDatabase` | Прогон Pest-тестов (`sail artisan test`) |
| Shared-dev | — | — | (уточнить) — не задан на момент инициализации |
| Staging | — | — | (уточнить) — не задан на момент инициализации |

## Что поднято и порты

| Сервис | Адрес | Контейнер / процесс | Примечание |
|--------|-------|---------------------|------------|
| MySQL 8 | `mysql:3306` (внутри сети Sail), хост `DB_HOST=mysql` | Sail-сервис `mysql` | БД приложения |
| Redis | `redis:6379`, хост `REDIS_HOST=redis` | Sail-сервис `redis` | кэш/очереди |
| Бэкенд (app) | `http://localhost:80` (Sail `APP_PORT`) | Sail-сервис `laravel.test`/`app` | Filament-админка — `/admin` |
| Фронтенд (Vite) | `http://localhost:5173` | `pnpm dev` (вне Sail, на хосте) | HMR для Inertia/Vue |
| Mailpit | UI `http://localhost:8025`, SMTP `:1025` | Sail-сервис `mailpit` | перехват исходящей почты |

Суперпользователь/тестовый аккаунт: (уточнить) — сидер под тестовую учётку на момент инициализации
не задокументирован.

> **Параллельные worktree-стенды (`tasks/<slug>/`).** Порты выше — дефолтного стенда из корня.
> Стенд задачи НЕ должен занимать те же хост-порты. Источник истины сдвига — бронь `coord.sh book`
> (поля `ports.backend/frontend/aux` и `redis_db`; формула `база + index*10` — в `scripts/coord.sh`
> `cmd_book`, см. `ai/guides/coordination.md`). Для Sail проброс хост-портов задаётся `FORWARD_*`
> в `.env` worktree: `APP_PORT` = `ports.backend`, Vite = `ports.frontend`, `FORWARD_REDIS_PORT` /
> `FORWARD_MAILPIT_PORT` (и `FORWARD_MAILPIT_DASHBOARD_PORT`) сдвигать от базы (6379/1025/8025),
> чтобы параллельный стенд не конфликтовал с дефолтным; изоляция Redis — по `redis_db` брони.
> НЕ выводить сдвиг формулой на глаз — брать из брони (вскрыто в волне Recipe FEAT-009…011).

## Ключевые файлы

- `docker-compose.yml` (генерируется Sail) — инфраструктурные сервисы (app, mysql, redis, mailpit).
- `.env` / `.env.example` — конфиг бэкенда (локальный профиль); `.env.testing` — тестовый профиль.
- `storage/logs/` — логи Laravel (`laravel.log`); для live-tail — `sail artisan pail`.

## Системные зависимости

Обязательно на хосте: Docker + Docker Compose (на них держится Laravel Sail — сам PHP/composer
живут внутри контейнера `app`, отдельно на хосте не нужны). Node.js + pnpm — для фронтенд-тулчейна
(Vite/Vue/TS), запускается на хосте, не в контейнере. PHP + composer на хосте — опционально
(удобно для IDE-подсказок/статик-анализа вне контейнера, но не обязательно — `sail artisan`/
`sail composer` работают без них).

## Команды старта

Перед подъёмом — синхронизация workspace:
```bash
./scripts/sync.sh && ./scripts/status.sh
```

### 1. Инфраструктура
```bash
./vendor/bin/sail up -d
```
Проверка: `./vendor/bin/sail ps` — все сервисы (app, mysql, redis, mailpit) `running`/`healthy`.

### 2. Бэкенд
```bash
./vendor/bin/sail artisan migrate
```
Проверка: `curl -I http://localhost/admin` — HTTP 200/302 (Filament отвечает).

### 3. Фронтенд
```bash
pnpm dev
```
Проверка: Vite поднял dev-сервер на `http://localhost:5173`, HMR подключается к странице.

## Команды остановки

```bash
./vendor/bin/sail down
```

## Первичная инициализация (уже выполнена / повторить при чистой установке)

```bash
composer install && pnpm install
./vendor/bin/sail up -d
./vendor/bin/sail artisan key:generate
./vendor/bin/sail artisan migrate
# сидинг данных — если появятся сидеры: ./vendor/bin/sail artisan db:seed
pnpm dev
```

## Пересоздание БД с нуля

```bash
./vendor/bin/sail artisan migrate:fresh
```

## Что упало / было обойдено (блокеры и воркэраунды)

(пока нет записей) — список ведётся по мере реального столкновения с проблемами стенда, заранее не
выдумывается.

## Не настраивалось (осознанно)

- Cloudflare Tunnel — легаси-механизм внешнего доступа (Nuxt-контур); локально не поднимается,
  актуальность для Laravel/Sail-стенда — (уточнить).
- MinIO/S3-хранилище — не поднимается по умолчанию, только по необходимости (работа с файловым
  хранилищем рецептов/изображений).
