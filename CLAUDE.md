# cbook — рабочее пространство агентской разработки

Кулинарная книга (cookbook). Миграция на Laravel 11 + Filament + Inertia/Vue со слоистой архитектурой; ранее — Nuxt 4/Vue 3. Это workspace двухконтурной модели: внутренний репозиторий знаний
**study-cbook-ai** (корень этой папки, origin — https://github.com/d-s-vo/study-ai.git) хранит весь контекст работы;

клиентский код живёт в gitignored-worktree клиентских реп (cbook, git-хост
github.com/d-s-vo/nuxt4-ts-project-cbook, SSH-порт 22, ключ `~/.ssh/id_ed25519`); в клиентский репозиторий уходит
только чистый коммит «от лица человека».

## С чего начать (роутер)

1. Начало любой сессии: `./scripts/sync.sh` (fetch реп, ff, предписания по task-веткам).
2. Определи тип работы по таблице **`ai/architecture.md §0`** — это главный роутер задач; он
   укажет нужный гайд (feature-workflow, adr-execution, debugging, live-acceptance).
3. Потерял ориентацию — `./scripts/status.sh` (панель: репы, ветки, статусы).

**Правило моделей субагентов:** рутина → `Sonnet 5`; архитектура/спеки/security/дебаг/ревью
→ `Opus 4.8`; сомневаешься → `Opus 4.8`. Правило распространяется на вложенных
агентов. Крупную/шумную работу и широкий поиск делегируй субагентам — держи у себя сводки, не сырой ход.

## Структура

```
study-cbook-ai/                    # = внутренний репозиторий знаний (ТОЛЬКО артефакты системы)
├── ai/                         # architecture, guides, adr, devlog, ops, memory, state.json
├── scripts/                    # интерфейс к workspace (см. ниже) + lib/ + repos.conf
├── githooks/                   # охранная обвязка (см. ai/ops/security-rails.md)

├── .repos/                     # bare-клоны клиентских реп (gitignored; pushurl=DISABLED)
├── cbook/          # worktree основной ветки клиента (gitignored)
├── tasks/<slug>/               # worktree задач (gitignored)

└── local/                      # локальная инфраструктура; секреты НЕ коммитятся никуда
```

Имена папок worktree — контракт из `CLAUDE.md` клиента. Не переименовывать.
Операторские/средовые доки — в `ai/ops/`; методология — в `ai/guides/`, `ai/adr/`, `ai/devlog/`.

## Команды workspace

| Команда | Назначение | Кто |
|---|---|---|
| `./scripts/sync.sh [--cleanup]` | входящие изменения: fetch, ff, предписания, уборка merged | агент, старт сессии |
| `./scripts/status.sh` | панель: репы, ветки, статусы | агент |

| `./scripts/coord.sh agents/board/book/update/unbook/reap` | координация параллельных агентов: присутствие и брони | агент |

| `./scripts/task.sh [--repo <имя>] new/add/rm/ls` | worktree задач (ветка `feat/<slug>`) | агент |

| `./scripts/gate.sh <ресурс> -- <команда>` | сериализация тяжёлых операций (полный тест/build/…) | агент |
| `./scripts/commit.sh` | коммит в клиентский worktree (сканер чистоты + формат сообщения) | агент |
| `./scripts/ai-commit.sh "<msg>" <пути>` | коммит своей зоны в study-cbook-ai под локом | агент |

| `./scripts/deliver.sh <repo> <branch>` | доставка в git клиента — ТОЛЬКО пользователь | пользователь |

| `./scripts/ai-push.sh` | пуш study-cbook-ai в origin | агент |

Основные worktree — только чтение и `sync.sh`; вся работа — в `tasks/<slug>`.
Порядок старта задачи: `coord.sh book <slug>` → `task.sh new <slug>`.
Реестр реп — в `scripts/repos.conf`. Параллельная работа — `ai/guides/coordination.md`.

## Жёсткие правила (нарушение = инцидент)

1. **Ноль следов системы в клиентских репах:** никаких упоминаний ИИ/агентов/номеров задач/ссылок
   на `ai/`/файлов системы — ни в коде, ни в коммитах, ни в ветках, ни в MR. Обвязка блокирует
   физически (стоп-словарь `githooks/stopwords.txt`), но правило первично.
2. Постоянные комментарии в коде — только «как писал бы человек», по стилю файла. Временные пометки —
   только с маркером `~wip~`, удаляются до коммита (хук блокирует).

3. Коммиты в клиентский worktree — только через `./scripts/commit.sh`; формат сообщений:
   `<type>: <описание> (conventional commits; type ∈ feat|fix|chore|refactor|docs|test|style|perf|build|ci)` (источник истины — `FORMAT_RE` в скрипте). Обход хуков (`--no-verify`)
   запрещён и заблокирован.

4. **`git push` агентам запрещён всегда** (клетка + pushurl=DISABLED). Доставка — пользователь через
   `deliver.sh`. Исключение: `ai-push.sh` (study-cbook-ai → origin) агентам разрешён.

5. `.env`-файлы и секреты не коммитятся никуда, включая study-cbook-ai (root-хук блокирует).
   Боевые креды (БД, S3/MinIO, API-токены, Cloudflare Tunnel) из .env — наружу не выносить и в тестах не использовать; тесты — на .env.testing с test_*-значениями.
6. Внутри клиентских worktree действует их `CLAUDE.md` — читать и соблюдать (root-cause
   фиксы; user-visible изменения отражать в клиентском CLAUDE.md / README проекта).
7. `git stash` в worktree запрещён (общий `.git`). Сессии запускать из корня workspace.

Охранная обвязка (хуки, стоп-словарь, гейт Write/Edit, сканер секретов/ПДн) — это эшелоны против
ЧЕСТНЫХ ошибок и следов. От скомпрометированного/инъецированного агента с доступом к ssh+сети они
не защищают полностью — это достижимо только sandbox/devcontainer с сетевым белым списком
(см. `ai/ops/security-rails.md`).

## Модель веток и деплоя клиента

`develop` — интеграционная ветка → merge в `main` = деплой. Наша доставка:
ветка `feat/<slug>` → MR в `develop` (создаёт пользователь).

## Локальный стенд

Порты и сервисы: Laravel app :80 (Sail APP_PORT), Vite :5173, PostgreSQL :5432, Redis :6379, Mailpit :8025; Filament — /admin. Подробности и env-профили — `ai/ops/local-setup.md`.
Гейты и команды стека — `ai/guides/stack-specifics.md`.
