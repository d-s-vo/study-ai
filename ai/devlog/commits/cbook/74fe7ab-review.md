---
repo: cbook
authored_hash: 74fe7ab903d627ec6ea9d3fceaefc70849113b96
patch_id: d108f08cd5716c884e1d626fba313fea0e60df50
feat: FEAT-005
branch: feat/infra-toolchain
reviewer_model: Opus 4.8
review_date: 2026-07-31
verdict: FAIL
blockers_total: 1
blockers_open: 1
resolved_by: []
---

# cbook@74fe7ab — REVIEW — chore: поднять redis и mailpit, выровнять окружение под mysql и завести CI

**Verdict:** FAIL
**Blocking findings:**
- `.github/workflows/ci.yml:74` и `:99` — `uses: pnpm/action-setup@v4` **без входа `version:`**, при
  этом `package.json` **не содержит поля `packageManager`** (проверено: `json.load` → `packageManager=None`,
  `engines=None`, секции `pnpm` нет), а `pnpm-workspace.yaml` несёт только `onlyBuiltDependencies: [esbuild]`
  (не версию). По документации pnpm/action-setup **v4** `version` **обязателен**, когда в `package.json`
  нет `packageManager` (подтверждено из README действия: «Optional when there is a `packageManager` field
  … otherwise this field is **required**»; фолбэка на bundled-версию нет → шаг падает с ошибкой). Контрпример:
  на **любом** PR/push в `develop` шаг «Setup pnpm» в job'ах `tests` и `frontend` завершается ошибкой →
  оба job'а красные → CI красный на чистом `develop`. Это прямо ломает цель фичи и AC («CI зелёный на
  `develop`», «`pnpm build` через `pnpm install --frozen-lockfile`»). Дефект не пойман, т.к. CI ни разу
  не прогонялся на GitHub Actions — верифицировались только локальные гейты (impl.md «Как тестировали»),
  а корректность workflow лишь *рассуждалась*.
  Достижимость: путь активируется **в этой же фиче** (workflow триггерится на push/PR в `develop` сразу
  после merge, без off-флага) → по §4.2 это FAIL, не WARN.
  Фикс — в зоне владения FEAT-005: добавить `with: version: <9|10>` (или `run_install`) к обоим шагам
  `pnpm/action-setup@v4` в `ci.yml`; править `package.json` (зона FEAT-008) **не требуется**.

**Non-blocking notes:**
- `compose.yaml:70` (mailpit-сервис) — у `mailpit` нет явного `healthcheck`, тогда как AC формулирует
  «все контейнеры healthy». Образ `axllent/mailpit:latest` несёт собственный `HEALTHCHECK` в Dockerfile,
  поэтому контейнер всё же рапортует health-статус (совпадает с живой приёмкой impl.md «mailpit — healthy»).
  Дефекта нет; для явности можно добавить healthcheck на UI-порт (severity: nit).
- `composer.json` `dev` → `pnpm dlx concurrently …` — `concurrently` уже в `devDependencies`, поэтому
  `pnpm exec concurrently` не тянул бы пакет из сети каждый запуск. Отклонение спекой санкционировано
  («`pnpm dlx` … или локальный `concurrently`»); корректности не влияет (severity: nit).
- Сборка фронта дублируется: job `tests` делает `pnpm build` (для Vite-манифеста, отклонение #2) и
  отдельный job `frontend` — тоже `pnpm build`. Это соответствует дизайну спеки (изолированный gate
  сборки) и приемлемо, но при исправлении блокера имеет смысл оставить как есть (severity: nit).

**Evidence:**
- Прочитано ПЕРЕД diff: `spec.md` + AC, `impl.md` (DONE, 2 задокументированных отклонения), разбор
  автора `74fe7ab-infra-toolchain.md`, `ai/memory.md` (STRICT rules/gotchas), `architecture.md §8` (гигиена).
- `git show --stat 74fe7ab` → 8 файлов, +189/−21 (`.env.example`, `.env.testing.example`, `.github/workflows/ci.yml`,
  `.gitignore`, `README.md`, `compose.yaml`, `composer.json`, `phpunit.xml`). Атомарен как единица инфра-фичи.
- **Стоп-словарь по дифу** (`githooks/stopwords.txt`, grep -iE по всему `git show`): **чисто** — ни
  ИИ/агентов, ни FEAT-номеров, ни `ai/`/devlog/spec.md/impl.md, ни `study-cbook-ai`, ни co-authored/generated.
  Имена job'ов/шагов CI нейтральные (Code style / Static analysis / Tests / Frontend build) — как в
  обычном OSS-репо. §8 соблюдён (перепроверка попутная; глубокая «ревью чистоты» — зона Шага 12).
- **ci.yml** — синтаксис GitHub Actions валиден по структуре (jobs: code-style/static-analysis/tests/frontend;
  on: pull_request+push branches [develop]); версии действий актуальные (checkout@v4, setup-php@v2,
  pnpm/action-setup@v4, setup-node@v4). `composer.json` — валидный JSON (`json.load` ok; ключи scripts:
  setup/dev/lint/analyse/test/post-* — `lint`/`analyse` добавлены, `test` сохранён).
- **CI job `tests` — разбор precedence (корректно):** после `cp .env.testing.example .env` OS-env job'а
  (`DB_HOST=127.0.0.1`, `DB_*`) перекрывают значения из `.env` — репозиторий env у Laravel **immutable**,
  реальные env-переменные не переопределяются `.env`. Значит override `DB_HOST=mysql→127.0.0.1` работает
  как задумано; `DB_DATABASE/USERNAME/PASSWORD` совпадают с кредами service-контейнера. `phpunit.xml`
  добавляет `DB_CONNECTION=mysql` (нет в job-env → без конфликта), `DB_HOST` не задаёт → берётся из
  job-env (127.0.0.1). Порядок шагов верен: Setup pnpm → Setup Node (`cache: pnpm`) → build → migrate → test.
- **.env / секреты:** `.env.testing.example` — только `test_*` (боевых кред Neon/MinIO/Cloudflare/токенов
  нет; hard-rule 5 соблюдён). `.env.example` — плейсхолдеры (`DB_USERNAME=cbook`, `DB_PASSWORD=password`
  — стандарт Sail, не секрет). CI-креды — литералы `test_*`/`root_secret` только для эфемерного service-MySQL
  (не боевые). `.env.testing` внесён в `.gitignore` — живой профиль наружу не течёт.
- **compose.yaml** построчно: `redis` (image/ports/volume `sail-redis`/healthcheck `redis-cli ping`/сеть
  sail) и `mailpit` (image/порты 1025+8025/сеть) — соответствуют spec; том `sail-redis` заведён;
  `depends_on` += redis; runtime-блок `laravel.test` (8.4) не тронут (готча «Sail дефолтит на свежий PHP»
  не сработала).
- **Отклонения impl.md оценены как обоснованные:** (#1 `.env.testing`→`.example` — вынуждено guard-хуком,
  интент сохранён, CI копирует шаблон; #2 `pnpm build` в `tests` — необходим для Vite-манифеста Inertia
  Feature-тестов, закрывает риск #1). Ни одно отклонение не является дефектом.
- Локальные гейты (impl.md) — зелёные (Pint pass, PHPStan L10 No errors, Pest 33 passed на MySQL-`testing`,
  pnpm build ok) + живая приёмка (redis/mailpit healthy, письмо доставлено). Не перепрогонял (дорого, уже
  зелёные) — блокер лежит **вне** локального контура: в ненаблюдавшемся GitHub-Actions-прогоне.

**Suggested next:** fix-forward-FEAT-005 (fix-now)

## Рубрика (бинарно, commit-review.md §3)

☑ Атомарность/целостность (8 файлов, единая инфра-фича; локальные гейты зелёные) · ☑ Логика vs спека/интент
(AC compose/env/phpunit/composer/README покрыты; precedence override верен) · ☑ Business-security (новых
маршрутов нет; только `test_*`/плейсхолдеры; боевых кред нет)
☒ **Тихие регрессии — CI не запускается зелёным** (`pnpm/action-setup@v4` без version → красный CI на
develop; критический путь — деливери-гейт фичи) · ☑ Тесты (инфра-фича, отдельных тестов не требует;
валидация прогоном на MySQL-`testing`)
☑ N+1/перф (неприменимо) · ☑ Over-engineering (нет; 4 нейтральных job'а, изолированный build-gate по спеке)

## Журнал закрытия находок

- Blocking #1 (`pnpm/action-setup@v4` без `version:` → красный CI) → **ОТКРЫТ**. Фикс — добавить
  `with: version: <9|10>` к обоим шагам в `ci.yml` (зона FEAT-005). Merge заблокирован до фикс-коммита
  и его повторного ревью (§6). Вердикт исходного коммита снимет только исходный ревьюер.
- Non-blocking (mailpit healthcheck / `pnpm dlx` / дубль build) → nit, закрытия не требуют.

## Связи

- Разбор «почему» (ADR-009): `74fe7ab-infra-toolchain.md` (рядом).
- Фича: `../../features/FEAT-005-infra-toolchain/impl.md` · `spec.md`.
- Гайд ревью: [`../../guides/commit-review.md`](../../guides/commit-review.md).
- Гигиена §8: `../../architecture.md` §8 (стоп-словарь — попутная перепроверка).
