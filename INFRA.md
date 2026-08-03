# INFRA — развёртывание инфраструктуры и карта портов

Справочник команд подъёма стендов workspace и занимаемых портов. Актуален на 2026-08-03.

---

## 1. Развёртывание с нуля (порядок команд)

Все команды — из корня workspace, если не сказано иное. На хосте НЕТ php/composer —
всё через Sail/Docker (демон — OrbStack).

```bash
# 1. Синхронизация workspace (fetch реп, ff основных worktree, предписания)
./scripts/sync.sh

# 2. Бронь фичи (атомарно выдаёт FEAT-номер, индекс → порты, redis-db)
./scripts/coord.sh book <slug>            # + --adr, если нужен decision-ADR

# 3. Ветка + worktree клиентского кода
./scripts/task.sh new <slug>              # → tasks/<slug>/, ветка feat/<slug>

# 4. Bootstrap зависимостей (внутри tasks/<slug>/)
cd tasks/<slug>
#    vendor/ ещё нет, sail недоступен → первичная установка через docker-образ:
docker run --rm -v "$(pwd)":/var/www/html -w /var/www/html \
  laravelsail/php84-composer:latest composer install --ignore-platform-reqs
docker run --rm -v "$(pwd)":/var/www/html -w /var/www/html \
  laravelsail/php84-composer:latest php artisan key:generate
pnpm install

# 5. Изоляция окружения (в .env, значения — из вывода coord.sh book, НЕ хардкод)
#    APP_PORT=<backend>  VITE_PORT=<frontend>  FORWARD_DB_PORT=<aux>
#    REDIS_DB=<redis_db>  WWWUSER=501  WWWGROUP=20
#    (.env и .env.testing создаются из *.example; в git не попадают)

# 6. Подъём контейнеров Sail
./vendor/bin/sail up -d                   # laravel.test, mysql, redis, mailpit
docker ps                                 # проверка портов/health

# 7. Миграции (тяжёлая операция → сериализация через gate)
cd /Users/dmitry/server/sites/study-cbook-ai
./scripts/gate.sh migrate -- sh -c 'cd tasks/<slug> && ./vendor/bin/sail artisan migrate --force'

# 8. Фронт (без этого страница отдаёт 500 ViteManifestNotFoundException)
cd tasks/<slug>
pnpm dev                                  # dev-режим (Vite на VITE_PORT)
#   или разовая сборка:
pnpm build                                # тяжёлое → из корня: ./scripts/gate.sh build -- ...
```

Ежедневный вход в существующий стенд: `./scripts/sync.sh` → `cd tasks/<slug>` →
`./vendor/bin/sail up -d` → при необходимости `pnpm dev`.

Остановка стенда: `./vendor/bin/sail stop` (контейнеры гасятся, данные БД остаются в volume).
Полный снос (только после доставки, эфемерная БД задачи): `./vendor/bin/sail down -v`.

## 2. Карта портов

Формула брони по индексу idx: backend `8100+idx*10`, frontend `5173+idx*10`, aux `3100+idx*10`.

### Основной стенд (worktree `cbook/`, только чтение)

| Сервис        | Порт хоста | Примечание                    |
|---------------|-----------|--------------------------------|
| Laravel app   | 80        | Sail APP_PORT                  |
| Vite          | 5173      | pnpm dev                       |
| MySQL 8       | 3306      | общая dev-БД                   |
| Redis         | 6379      |                                |
| Mailpit UI    | 8025      | SMTP — 1025                    |
| Filament      | —         | /admin поверх app-порта        |

### Стенды задач (по броне; сейчас активных нет)

Порты стенда задачи с индексом idx (пример в скобках — idx 1):

| Сервис        | Формула порта   | idx 1     | Переменная .env                  |
|---------------|-----------------|-----------|-----------------------------------|
| Laravel app   | 8100 + idx*10   | 8110      | `APP_PORT`                        |
| Vite          | 5173 + idx*10   | 5183      | `VITE_PORT`                       |
| MySQL 8       | 3100 + idx*10   | 3110      | `FORWARD_DB_PORT` (эфемерная БД)  |
| Redis         | 6379 + idx*10   | 6389      | `FORWARD_REDIS_PORT`              |
| Mailpit SMTP  | 1025 + idx*10   | 1035      | `FORWARD_MAILPIT_PORT`            |
| Mailpit UI    | 8025 + idx*10   | 8035      | `FORWARD_MAILPIT_DASHBOARD_PORT`  |

Бронь выдаёт только backend/frontend/aux и логический `REDIS_DB`; Redis/Mailpit-порты
разводим вручную в `.env` по той же формуле `+idx*10`.

## 3. Прочие занятые ресурсы

- `redis_db` — номер логической БД Redis из брони (`coord.sh book`).
- Гейты сериализации тяжёлых операций: `./scripts/gate.sh <build|test|migrate> -- <cmd>`.
- Панель состояния: `./scripts/status.sh`; брони/агенты: `./scripts/coord.sh board`.
