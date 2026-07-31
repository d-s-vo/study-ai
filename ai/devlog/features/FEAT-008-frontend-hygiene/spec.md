# FEAT-008: Гигиена фронта и скаффолда — Tailwind-линия, ESLint/typecheck, типы, чистка Breeze

## Статус: SPEC

## Затрагиваемые репозитории
cbook (frontend + тест-скаффолд) — один репозиторий. Мультирепный рецепт §3.5 не применяется.

## Цель
Навести гигиену фронта и убрать «мёртвый» Breeze/Laravel-скаффолд: зафиксировать текущую Tailwind-линию (v3) и убрать неподключённый v4-пакет; ввести ESLint flat-config + скрипты `lint`/`typecheck`; убрать `any` в `Checkbox.vue` и ужесточить `tsconfig`; вычистить стоковый скаффолд (Pest-заглушки, ExampleTest'ы, дубль трейта, мёртвый `window.axios`, no-op `version()`, версии Laravel/PHP на welcome).

## Контекст
База — `origin/develop @ e0c8ee3`, поверх FEAT-005/006/007 (гейты/CI, DTO+типы, auth+baseline уже зелёные). Текущее состояние:
- **Tailwind:** фактически v3 (`tailwindcss@^3.2.1` + `postcss.config.js` + `tailwind.config.js` + `autoprefixer`). Но в `package.json` висит `@tailwindcss/vite@^4.0.0` — **не подключён** ни в `vite.config.js`, ни в `postcss`. Смешение линий v3/v4 в манифесте.
- **ESLint/typecheck:** `package.json` scripts — только `build`/`dev`. `stack-specifics.md` цитирует `pnpm lint` (ESLint) и `pnpm vue-tsc --noEmit` — их нет.
- **`any`:** `Checkbox.vue:8` — `value?: any` (нарушение мандата «0 any»).
- **`tsconfig.json`:** `strict:true`, но нет `noUnusedLocals`/`noUnusedParameters`/`noImplicitReturns`/`noFallthroughCasesInSwitch`; `allowJs:true` (обдумать).
- **Мёртвый скаффолд:** `tests/Pest.php` (`toBeOne`, `something()`); `tests/Feature/ExampleTest.php` + `tests/Unit/ExampleTest.php`; `tests/Feature/UserRepositoryTest.php:10` — **дубль** `uses(RefreshDatabase::class)` (уже применён глобально в `Pest.php` для `Feature`); `resources/js/bootstrap.ts` (`window.axios`) + axios-часть `global.d.ts` + зависимость `axios` (используется **только** в bootstrap/global — проверено grep'ом); `HandleInertiaRequests::version()` — no-op обёртка над `parent::version()`; `routes/web.php:14-15` — `laravelVersion`/`phpVersion` на `Welcome` (демо-данные).

Инварианты: `stack-specifics.md` §Frontend (0 `any`/`as`, TS strict, ESLint), `ai/memory.md` North Star.

## Acceptance Criteria
- [ ] `@tailwindcss/vite` удалён из `package.json`; текущая линия зафиксирована как **Tailwind v3** (postcss + `tailwind.config.js` + `autoprefixer`); `pnpm build` собирается, стили не сломаны. Миграция на v4 — вне скоупа (зафиксировать в README/комментарии решение остаться на v3).
- [ ] ESLint flat-config (`eslint.config.js`) с `eslint-plugin-vue` + `typescript-eslint`; `package.json` scripts: `lint` (eslint), `typecheck` (`vue-tsc --noEmit`). `pnpm lint` и `pnpm typecheck` — зелёные (весь найденный линтом долг починен).
- [ ] `Checkbox.vue` — `value?: any` заменён на конкретный тип (напр. `string | number | boolean | null`); `vue-tsc` проходит.
- [ ] `tsconfig.json` ужесточён: `noUnusedLocals`, `noUnusedParameters`, `noImplicitReturns`, `noFallthroughCasesInSwitch` (+ решение по `allowJs`); проект проходит `vue-tsc --noEmit` под новыми флагами.
- [ ] Скаффолд вычищен: `tests/Pest.php` без `toBeOne`/`something()`; `tests/Feature/ExampleTest.php` и `tests/Unit/ExampleTest.php` удалены; дубль `uses(RefreshDatabase::class)` в `UserRepositoryTest.php` убран; `bootstrap.ts`+axios-часть `global.d.ts` удалены и зависимость `axios` вычищена из `package.json` (подтверждено, что нигде больше не используется); `HandleInertiaRequests::version()` (no-op) удалён; `laravelVersion`/`phpVersion` убраны из `routes/web.php` и из `Welcome.vue` props.
- [ ] Полный набор гейтов зелёный: `sail artisan test` (0 fail после удаления Example-тестов), `sail bin phpstan analyse` (L10), `sail bin pint --test`, `pnpm lint`, `pnpm typecheck`, `pnpm build`.

## Технический дизайн

### Tailwind (фиксация v3)
- Удалить `@tailwindcss/vite` из `devDependencies`. Оставить `tailwindcss@^3`, `@tailwindcss/forms`, `postcss`, `autoprefixer`, `postcss.config.js`, `tailwind.config.js` как есть.
- Убедиться, что `resources/css`/entry подключает Tailwind через postcss (v3-путь), не через v4-плагин Vite.

### ESLint flat-config
- `eslint.config.js`: `typescript-eslint` (recommended) + `eslint-plugin-vue` (`flat/recommended`), парсер `vue-eslint-parser` с `@typescript-eslint/parser` для `<script lang="ts">`. Игноры: `vendor`, `node_modules`, `public/build`, `resources/js/types/generated.d.ts` (автоген — не линтуем).
- Devdeps: `eslint`, `typescript-eslint`, `eslint-plugin-vue`, `vue-eslint-parser` (+ при необходимости `@vue/eslint-config-typescript`).
- Scripts: `"lint": "eslint . --ext .ts,.vue"` (или flat-эквивалент), `"typecheck": "vue-tsc --noEmit"`.
- **Починить всё, что линт найдёт** — 0 ошибок/варнингов на выходе (правки в существующих Vue/TS без изменения поведения).

### Типы
- `Checkbox.vue`: `value?: string | number | boolean | null` (HTML input value + возможный null). Проверить единственного потребителя (`Login.vue` — `value` не передаёт, только `v-model:checked`), регресса нет.
- `tsconfig.json`: добавить `noUnusedLocals`, `noUnusedParameters`, `noImplicitReturns`, `noFallthroughCasesInSwitch`. `allowJs`: **решение** — оставить `true` пока (в проекте есть `.js`-конфиги, но `include` их не захватывает; отключение безопасно, но некритично — зафиксировать выбор; по умолчанию оставить `true`, чтобы не расширять скоуп). Прогнать `vue-tsc` и починить всплывшие неиспользуемые импорты/переменные (частый источник — вычищенные скаффолдом места).

### Чистка скаффолда
- `tests/Pest.php`: удалить блок `expect()->extend('toBeOne', ...)` и функцию `something()`; сохранить `pest()->extend(TestCase::class)->use(RefreshDatabase::class)->in('Feature')`.
- Удалить `tests/Feature/ExampleTest.php`, `tests/Unit/ExampleTest.php` (стоковые «true is true» / «get / → 200» — покрыто осмысленными тестами; welcome-роут после чистки версий проверяется отдельно при необходимости).
- `UserRepositoryTest.php:10`: убрать локальный `uses(RefreshDatabase::class)` — трейт уже применяется глобально для `Feature` в `Pest.php` (файл лежит в `tests/Feature`).
- `resources/js/bootstrap.ts`: удалить файл (или опустошить) — `window.axios` не используется; убрать его импорт из `app.ts`, если есть.
- `resources/js/types/global.d.ts`: удалить `import { AxiosInstance }` и `Window.axios`-объявление; сохранить ziggy `route` и augment `@inertiajs/core PageProps`.
- `package.json`: удалить `axios` из devDependencies (подтверждено grep'ом — только bootstrap/global).
- `HandleInertiaRequests.php`: удалить переопределённый no-op `version()` (наследуемое поведение идентично). ⚠️ Координация: этот файл правит и FEAT-006 (`share()`); FEAT-008 идёт после — правит только `version()`, не конфликтуя с `share()`.
- `routes/web.php`: убрать `laravelVersion`/`phpVersion` (и `canLogin`/`canRegister` — оставить, они осмысленны для Welcome; убрать только версии) из `Inertia::render('Welcome', [...])`.
- `Welcome.vue`: убрать `laravelVersion`/`phpVersion` из `defineProps` и из шаблона (футер с версиями). Проверить, что удаление не ломает layout.

## Тесты
**Обновить:** после удаления Example-тестов и версий welcome — прогнать `sail artisan test`, убедиться 0 fail; welcome-роут (`GET /` → 200) при желании покрыть одним осмысленным тестом взамен удалённого `ExampleTest` (решение импла: либо оставить покрытие в отдельном feature-тесте, либо счесть избыточным).
**Удалить:** `tests/Feature/ExampleTest.php`, `tests/Unit/ExampleTest.php` — стоковые заглушки без ценности.
**Добавить:** отдельных новых тестов фича не требует; страховка — `pnpm typecheck` + `pnpm lint` как структурные гейты (completeness через линтер вместо точечных тестов).

> Чувствительные данные/permissions не затрагиваются — правило негативных тестов неприменимо.

## Типизация/качество
- Гейты (все зелёные): `sail artisan test`, `sail bin phpstan analyse` (L10), `sail bin pint --test`, `pnpm lint`, `pnpm typecheck`, `pnpm build`.
- Мандат «0 `any`» выполнен (Checkbox). ESLint + ужесточённый tsconfig — **структурная профилактика** класса «слабая типизация/мёртвый код» (заменяет точечные тесты для этих классов).
- Автоген `generated.d.ts` (из FEAT-006) — в ESLint-игнорах, не линтуется.

## Безопасность
- **Доступы:** маршрутов/эндпоинтов не добавляет; удаление `laravelVersion`/`phpVersion` из welcome — мелкое сокрытие версий (минус информация для fingerprinting).
- **Данные:** удаление `window.axios` убирает неиспользуемую глобальную поверхность; чувствительных данных не касается.
- **Валидация:** пользовательского ввода не добавляет.
- **Гигиена §8:** комментарии/конфиги — человеческий стиль; решение «остаёмся на Tailwind v3» формулируется нейтрально, без следов системы.

## Пользовательская документация
Welcome-страница теряет строку версий Laravel/PHP — незначительное user-visible изменение демо-страницы. README (владелец правок — FEAT-005) может получить строки про `pnpm lint`/`pnpm typecheck` поверх смерженной базы 005; если добавляем — отметить в `impl.md`. Публичной доки правка не требует.

## Зависимые файлы для изменения
| Файл | Тип изменения |
|---|---|
| `package.json` | убрать `@tailwindcss/vite`, `axios`; добавить eslint-devdeps + scripts `lint`/`typecheck` |
| `eslint.config.js` | новый — flat-config (vue + typescript-eslint) |
| `tsconfig.json` | ужесточение флагов (noUnusedLocals и т.д.) |
| `resources/js/Components/Checkbox.vue` | `value?: any` → конкретный тип |
| `resources/js/bootstrap.ts` | удалить (мёртвый `window.axios`) |
| `resources/js/app.ts` | убрать импорт `bootstrap` (если есть) |
| `resources/js/types/global.d.ts` | убрать axios-объявление |
| `tests/Pest.php` | убрать `toBeOne`/`something()` |
| `tests/Feature/ExampleTest.php`, `tests/Unit/ExampleTest.php` | удалить |
| `tests/Feature/UserRepositoryTest.php` | убрать дубль `uses(RefreshDatabase::class)` |
| `app/Http/Middleware/HandleInertiaRequests.php` | удалить no-op `version()` |
| `routes/web.php` | убрать `laravelVersion`/`phpVersion` |
| `resources/js/Pages/Welcome.vue` | убрать версии из props/шаблона |
| eslint-фиксы | по факту находок линтера |

## Зависимости/границы (сверка с 005/006/007)
- **Порядок:** реализуется **последней** (005→006→007→008) — наследует чистые гейты, DTO/типы и auth без baseline.
- **`package.json`:** единственный владелец **npm-скриптов и devDependencies** — FEAT-008. FEAT-005 `package.json` не трогал (только composer/README). Конфликта нет.
- **`HandleInertiaRequests.php`:** правят и FEAT-006 (`share()` → UserData), и FEAT-008 (удаление `version()`). Разные методы; 008 после 006 → ребейз, правка `version()` не пересекается с `share()`. **Единственная точка совместного касания файла — координировать при интеграции.**
- **`resources/js/types/global.d.ts`:** FEAT-006 оставил axios-часть нетронутой специально; FEAT-008 её удаляет здесь. `index.d.ts` (типы `auth.user`) — зона 006, 008 не трогает. Оба под types-каталогом → интеграция по очереди.
- **`resources/js/types/generated.d.ts`:** создан FEAT-006; FEAT-008 добавляет его в ESLint-игнор (не редактирует).
- **`tsconfig.json` / ESLint:** ужесточение — только FEAT-008, поверх уже типизированного (006) и очищенного (007) кода, чтобы strict-флаги/линтер прошли без каскада правок в чужих фичах.
- **Оставляет систему зелёной:** после 008 — все гейты (pest, phpstan L10, pint, lint, typecheck, build) зелёные; цепочка 005→008 завершена.

## Что НЕ входит
- Инфраструктура/CI/pnpm-перевод composer (FEAT-005).
- UserData DTO / автоген типов (FEAT-006).
- Throttle / FormRequest / baseline (FEAT-007).
- **Миграция Tailwind v3 → v4** (явно отложена; фича фиксирует v3).
- Доменный фронт (страницы Recipe/Ingredient), редизайн UI.

## Оценка сложности
Средняя. Риски: (1) ужесточение `tsconfig` + ESLint может вскрыть неожиданный объём мелкого долга в Breeze-компонентах — держать в скоупе «починить найденное», не расползаться в редизайн; (2) удаление `axios`/`bootstrap.ts` — перепроверить, что `app.ts` не импортирует bootstrap и Inertia сам не полагается на `window.axios`; (3) совместное касание `HandleInertiaRequests.php` с FEAT-006 — аккуратная последовательная интеграция.
