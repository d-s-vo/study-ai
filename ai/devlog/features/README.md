# features/ — фичи полного цикла

Каждая нетривиальная фича — отдельная папка `FEAT-NNN-slug/`:

```
FEAT-NNN-slug/
├── spec.md    # ТЗ ДО реализации (тройная проверка: полнота / логика / безопасность)
├── impl.md    # как реализовали ПОСЛЕ работы (+ YAML frontmatter с тегами баг-класса)
└── retro.md   # ретроспектива (опционально, для крупных)
```

**Конвенция целиком** (нумерация, YAML frontmatter, каталог тегов, grep-сценарии, правила) — в
[`../README.md`](../README.md). **Алгоритм работы над фичей** — в
[`../../guides/feature-workflow.md`](../../guides/feature-workflow.md).

- Нумерация FEAT-NNN — **сквозная** на все репозитории `cbook` (если их несколько).
- Trivial-fix (1-2 файла, <50 LOC, не миграция/контракт/keystone) сюда **не** заводится — его канал `../YYYY-MM-DD.md` §Quickfixes.
- Следующий номер: `ls` этой папки → `tail`.
- Диапазонная резервация: если внутри самой системы (`study-cbook-ai`) идёт многофичевая инициатива по
  `adr-execution.md`, план ADR может заранее зарезервировать диапазон номеров под свои шаги — без
  брони `coord.sh book` (это не клиентский код, ни портов, ни task-БД не требует). Резервация
  фиксируется одной строкой-примечанием под таблицей маппинга, со ссылкой на ADR и его секцию плана.

## Маппинг FEAT-NNN ↔ ветка (режим секретности, модуль M6)

Если включён режим секретности (`architecture.md` §8) — публичные имена веток в клиентских репах
`feat/<понятный-slug>` **без FEAT-номеров**. Соответствие FEAT ↔ ветка ведём здесь, во внутреннем
реестре. При M6=OFF номер FEAT может жить прямо в имени ветки — таблица ниже не обязательна.

<!-- FEAT-MAP:BEGIN -->
| FEAT | Ветка (клиентская репа) | Репо | Статус | Коммит | Что |
|------|-------------------------|------|--------|--------|-----|
| FEAT-002 | feat/laravel-skeleton | cbook | done | 9f4b857 | greenfield-скелет Laravel 12 + enterprise-слои + QA-тулчейн |
| FEAT-003 | feat/enterprise-skeleton | cbook | done | 2038821 | активация конфига Pint (pint.json) + strict_types/psr12 по базе |
| FEAT-004 | feat/breeze-inertia-auth | cbook | done | e0c8ee3 | Breeze (Inertia/Vue3/TS/Tailwind) + рефактор авторизации в слои (UserRepository/RegisterUserTask) |
| FEAT-005 | feat/infra-toolchain | cbook | done | 74fe7ab | redis+mailpit, окружение под mysql, CI GitHub Actions |
| FEAT-006 | feat/user-dto | cbook | done | fd0e5fe | UserData DTO граница Inertia + автоген TS-типов (typescript:transform) |
| FEAT-007 | feat/auth-hardening | cbook | done | a1f6c53 | auth-hardening: throttle register/forgot/reset, FormRequest-валидация, email-верификация (a1f6c53+f4a9d63+6605919) |
| FEAT-008 | feat/frontend-hygiene | cbook | done | 348396b | ESLint flat-config, pnpm lint/typecheck, фронт-гигиена |
<!-- FEAT-MAP:END -->

> Строки таблицы — `⚙️ RUNTIME`: append-only, пишутся `scripts/feat-map.sh` (или вручную под
> `scripts/edit-shared.sh`). Статус меняется reserved → in-progress → done по ходу исполнения.
> Пустая таблица (без даже примерной строки) — тоже валидное состояние на старте проекта.
