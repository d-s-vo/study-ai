---
repo: cbook
authored_hash: 348396b73ae00aa5b295da9bf7a6405c6239f0a3
patch_id: dcdaf3a6aa5cc4fb419b4ffd92bd19b4b2f4c959
feat: FEAT-008
branch: feat/frontend-hygiene
reviewer_model: Opus 4.8
review_date: 2026-07-31
verdict: PASS
blockers_total: 0
blockers_open: 0
resolved_by: []
---

# cbook@348396b — REVIEW — chore: гигиена фронта — ESLint/typecheck, фиксация Tailwind v3, чистка скаффолда

**Verdict:** PASS
**Blocking findings:**
- (нет)
**Non-blocking notes:**
- `eslint.config.js` / `package.json` vs FEAT-005 `ci.yml` — CI зовёт только `pnpm build`, новые скрипты `lint`/`typecheck` в пайплайне не вызываются → структурные гейты, которыми spec обосновывает «линтер вместо точечных тестов», в CI **не enforced** (только при локальном прогоне) (severity: minor).
- Интеграция develop: 008 добавляет строгий `tsconfig` (`noUnusedLocals`/`noUnusedParameters`/…) + ESLint; код параллельных FEAT-006/005/007 писался БЕЗ этих флагов → на смерженном develop `lint`/`typecheck` могут вскрыть новые нарушения в чужом коде (severity: minor, зона интеграционного гейта H.6, не per-commit).
- `resources/js/Pages/Auth/Login.vue` (POST submit) — живая приёмка автора смоукнула только GET (`/`, `/login`); отправка формы после удаления `bootstrap.ts` рантаймом не проверена (severity: minor; риск низкий — обоснование в Evidence).
- `eslint.config.js:10` — игнор `resources/js/types/generated.d.ts` ссылается на файл, отсутствующий в базе e0c8ee3 (появляется из FEAT-006); no-op сейчас, forward-correct (severity: nit).

**Evidence:**
- **Атомарность:** 28 файлов, но один логический смысл — гигиена фронта/скаффолда (Tailwind-линия, ESLint/typecheck, типы, чистка Breeze). Основной объём diff — `pnpm-lock.yaml` (1123 стр., механическое следствие смены devDeps). Gate ревьюабельности пройден.
- **Гейты (прогнал сам, worktree tasks/frontend-hygiene, pnpm 10.30.3):** `pnpm exec eslint .` → RC=0 (0 проблем); `pnpm exec vue-tsc --noEmit` → RC=0. `--debug` подтвердил, что `.ts` реально линтуются (4 .ts-файла, включая `app.ts`) — опасение «flat-config не берёт .ts» опровергнуто. Pest/PHPStan L10/Pint требуют Sail — приняты по отчёту автора (impl.md: 32 passed / L10 OK / pint passed).
- **axios/bootstrap:** `git grep axios|bootstrap` по `resources` в 348396b → 0 совпадений (RC=1) — остаточных ссылок нет. `window.axios` нигде не читался; Inertia v2 (`@inertiajs/vue3`) использует собственный axios-инстанс, который сам ставит `X-Requested-With`/`X-Inertia` и шлёт CSRF через cookie `XSRF-TOKEN` → `X-XSRF-TOKEN`. Удалённый `bootstrap.ts` конфигурировал только `window.axios` (Inertia его не трогает) → на путь Inertia-запросов (login/register/profile POST) удаление не влияет. Серверные Pest-тесты auth (FEAT-004) зелёные. Риск низкий; смоук POST рекомендован до доставки.
- **version() no-op:** удалён override `version(): return parent::version($request)` — поведение asset-versioning идентично наследуемому (Inertia хеширует Vite-манифест в предке). Изменения поведения нет.
- **Coverage:** `Feature/ExampleTest` (`GET / → 200`) заменён равноценным `Feature/WelcomeTest` (`GET / → assertOk`). `Unit/ExampleTest` (`true is true`) и `Pest.php` `toBeOne`/`something()` — стоковые заглушки без ценности; реального покрытия не потеряно. `tests/Unit/.gitkeep` — обоснованно (пустая директория ломает phpunit-сьют Unit).
- **Утечки версий:** `git grep laravelVersion|phpVersion|Application::VERSION` → 0 (RC=1). Убраны из `routes/web.php`, `Welcome.vue` (props+footer), импорт `Application` снят. Других утечек нет.
- **Checkbox тип:** `value?: string | number | boolean | null` — `value` (bind `:value`) отделён от `checked` (`v-model:checked`); в `Login.vue` `value` не передаётся, `form.remember: boolean` идёт в `checked`. Совместимо; typecheck зелёный.
- **ESLint-конфиг:** корректный flat-config — `tseslint.config()`, base+ts+vue recommended, `vue-eslint-parser` c ts-субпарсером для `<script lang="ts">`, `route: 'readonly'` глобал (закрывает 8 no-undef в шаблонах, не маскируя реальные no-undef в скриптах), `multi-word-component-names` off по конвенции Inertia. Косметические vue-правила off + `.editorconfig` (4 пробела) вместо переформатирования — оправдано (spec требовал «0 варнингов»; разделение корректность/форматирование — идиоматично, `vue/attributes-order` оставлен и автофикснут).
- **tsconfig-ужесточение:** vue-tsc зелёный под новыми флагами → строгие правила ничего скрытого не ломают.
- **Merge-осмотр (пункт 8, «чужая среда»):** `git merge-tree --write-tree feat/frontend-hygiene {infra-toolchain,user-dto,auth-hardening}` → RC=0 на всех трёх (текстовых конфликтов нет). Пересечения с 006: `HandleInertiaRequests.php` (008 убирает `version()`, 006 правит `share()` — разные регионы), `AuthenticatedLayout.vue`, `UpdateProfileInformationForm.vue` (008 = attributes-order + Boolean/String→примитивы; 006 = свои правки) — 3-way сливается чисто. Семантические риски на смерженном develop вынесены в notes (зона H.6).
- **Гигиена §8:** стоп-скан diff+сообщения+автора (`claude|anthropic|orchestrator|субагент|devlog|FEAT-\d|co-authored|study-cbook-ai|~wip~|…`) → 0 совпадений (RC=1). Автор `Dmitriy <smirnov@whyme.agency>`; комментарии в `eslint.config.js` — человеческий стиль. Сообщение — conventional commits (`chore:`).

**Suggested next:** advisory

## Рубрика (бинарно, commit-review.md §3)

☑ Атомарность/целостность — один смысл, компилируется, гейты зелёные
☑ Логика vs спека/интент — все AC спеки закрыты (Tailwind v3, ESLint/typecheck, Checkbox-тип, tsconfig, чистка скаффолда)
☑ Business-security — маршрутов/ввода не добавляет; удаление версий = минус fingerprint; auth-путь не тронут
☑ Тихие регрессии/parity — version() no-op идентичен; axios не на пути Inertia; POST не смоукнут (note)
☑ Тесты (мутационно) — WelcomeTest ловит регресс роута `/` (сломать рендер Welcome → тест падает); удалены только вакуумные заглушки
☑ N+1/перф — неприменимо (нет запросов к БД)
☑ Over-engineering — нет; скоуп удержан, миграция v4 явно отложена

## Журнал закрытия находок

- note (CI не зовёт lint/typecheck) → advisory, адрес фикс-forward: интеграция FEAT-005 `ci.yml` (добавить шаги `pnpm lint`/`pnpm typecheck`) — на усмотрение оркестратора/владельца.
- note (интеграционный lint/typecheck на смерженном develop) → advisory, зона H.6 (полный гейт интеграционной ветки после батча).
- note (POST-смоук) → advisory, рекомендован живой прогон login-submit до доставки.

## Связи

- Разбор «почему» (автор, ADR-009): `348396b-frontend-hygiene.md`.
- Фича: `../../features/FEAT-008-frontend-hygiene/impl.md` · `spec.md`.
- Гайд ревью: [`../../guides/commit-review.md`](../../guides/commit-review.md).
