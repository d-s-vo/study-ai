# INFRA — развёртывание инфраструктуры и карта портов

Справочник команд подъёма стендов workspace и занимаемых портов. Актуален на 2026-08-03
(активная задача: `tasks/filament-admin`, бронь индекс 1).

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

### Стенд задачи `filament-admin` (бронь idx 1, активен)

| Сервис        | Порт хоста | Примечание                                |
|---------------|-----------|--------------------------------------------|
| Laravel app   | 8110      | http://127.0.0.1:8110, /admin — там же     |
| Vite          | 5183      |                                            |
| MySQL 8       | 3110      | эфемерная БД задачи (не dev-БД!)           |
| Redis         | 6389      | `FORWARD_REDIS_PORT`, логическая БД 5      |
| Mailpit       | 8035 / 1035 | UI / SMTP (`FORWARD_MAILPIT_*`)          |

Redis/Mailpit бронью не выделяются (бронь даёт только логический `REDIS_DB`) — их хост-порты
разводим вручную в `.env` по той же формуле `+idx*10`: redis `6379+idx*10`,
mailpit smtp `1025+idx*10`, mailpit UI `8025+idx*10`. Для idx 1 это сделано (6389/1035/8035).

## 3. Прочие занятые ресурсы

- `redis_db` брони: filament-admin → **5** (логическая БД внутри общего Redis).
- Гейты сериализации тяжёлых операций: `./scripts/gate.sh <build|test|migrate> -- <cmd>`.
- Панель состояния: `./scripts/status.sh`; брони/агенты: `./scripts/coord.sh board`.
