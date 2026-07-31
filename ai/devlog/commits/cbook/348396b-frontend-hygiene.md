---
repo: cbook
authored_hash: 348396b73ae00aa5b295da9bf7a6405c6239f0a3
patch_id: dcdaf3a6aa5cc4fb419b4ffd92bd19b4b2f4c959
branch: feat/frontend-hygiene
feat: FEAT-008
date: 2026-07-31
final_hash:
fix_chain: []
---

# cbook@348396b — chore: гигиена фронта — ESLint/typecheck, фиксация Tailwind v3, чистка скаффолда

> Коммит-сообщение (как в клиентском репо): `chore: гигиена фронта — ESLint/typecheck, фиксация Tailwind v3, чистка скаффолда`
> Одиночный коммит (без фикс-цепочки на момент написания).

## Кратко (для инженера)

- **`package.json`** — из `devDependencies` убраны `@tailwindcss/vite@^4` (никогда не был подключён ни в
  `vite.config.js`, ни в postcss — смешение линий v3/v4 в манифесте) и `axios@^1` (использовался только
  мёртвым `bootstrap.ts`). Добавлены `eslint@^9`, `@eslint/js`, `typescript-eslint@^8`, `eslint-plugin-vue@^9`,
  `vue-eslint-parser@^9`. Новые скрипты: `lint` (`eslint .`) и `typecheck` (`vue-tsc --noEmit`).
- **`eslint.config.js`** (НОВЫЙ) — flat-config: base `@eslint/js` recommended + `typescript-eslint` recommended
  + `eslint-plugin-vue` `flat/recommended`; для `*.vue` — `vue-eslint-parser` с `@typescript-eslint/parser`
  под `<script lang="ts">`. Игноры: `vendor`, `node_modules`, `public/build`, `resources/js/types/generated.d.ts`
  (автоген FEAT-006 — не линтуем). Ziggy `route` объявлен глобалом. Отключены: `vue/multi-word-component-names`
  (Inertia-страницы/UI-примитивы односложны по конвенции) и группа чисто-косметических правил
  (`vue/html-indent`, `max-attributes-per-line`, `html-closing-bracket-newline`, `html-self-closing`,
  singleline/multiline-content-newline) — форматирование в проекте держит `.editorconfig` (4 пробела), а не ESLint.
- **`tsconfig.json`** — добавлены `noUnusedLocals`, `noUnusedParameters`, `noImplicitReturns`,
  `noFallthroughCasesInSwitch`; `allowJs` оставлен `true` (осознанно, чтобы не расширять скоуп — `include`
  всё равно не захватывает `.js`-конфиги).
- **`Checkbox.vue`** — `value?: any` → `value?: string | number | boolean | null` (закрытие мандата «0 any»).
- **`bootstrap.ts`** удалён; импорт `./bootstrap` убран из `app.ts`; axios-часть `global.d.ts` (`import AxiosInstance`,
  `Window.axios`) удалена; `axios` вычищен из зависимостей. Inertia несёт собственный HTTP-клиент — сборка это
  подтвердила (`pnpm build` зелёный без axios/bootstrap).
- **`HandleInertiaRequests.php`** — удалён no-op override `version()` (`return parent::version($request)`);
  `share()` (UserData из FEAT-006) не тронут.
- **`routes/web.php`**, **`Welcome.vue`** — убраны `laravelVersion`/`phpVersion` (демо-данные + мелкий
  version-fingerprint); `canLogin`/`canRegister` оставлены как осмысленные. Из `Welcome.vue` удалён и
  footer-блок с версиями, и импорт `Illuminate\Foundation\Application` из роутов.
- **`tests/Pest.php`** — удалены стоковые `expect()->extend('toBeOne', …)` и `function something()`;
  оставлен только `pest()->extend(TestCase::class)->use(RefreshDatabase::class)->in('Feature')`.
- **`tests/Feature/ExampleTest.php`**, **`tests/Unit/ExampleTest.php`** удалены; `tests/Unit/.gitkeep` добавлен,
  чтобы конвенционная директория `tests/Unit` (тест-сьют в `phpunit.xml`) не исчезла.
- **`tests/Feature/UserRepositoryTest.php`** — убран дубль `uses(RefreshDatabase::class)` (трейт уже применён
  глобально для `Feature` в `Pest.php`).
- **`tests/Feature/WelcomeTest.php`** (НОВЫЙ) — один осмысленный тест `GET / → 200` взамен удалённого стокового
  `ExampleTest`, страхует правку роута/страницы Welcome.
- **9 Breeze-компонентов/страниц** (Login, Register, Modal, TextInput, AuthenticatedLayout, ConfirmPassword,
  ForgotPassword, ResetPassword, VerifyEmail, UpdatePasswordForm, UpdateProfileInformationForm) — только
  автофикс `vue/attributes-order` (перестановка атрибутов, `v-model`/`id` вперёд); поведение не меняется.
  В `UpdateProfileInformationForm.vue` дополнительно `Boolean`/`String` → примитивы `boolean`/`string`
  (`@typescript-eslint/no-wrapper-object-types`).

## Детально (для новичка)

### Почему остаёмся на Tailwind v3, а не мигрируем на v4
В манифесте одновременно висели v3-линия (`tailwindcss@^3` + `postcss.config.js` + `tailwind.config.js` +
`autoprefixer`) и пакет `@tailwindcss/vite@^4`. Второй — плагин альтернативной v4-линии, где Tailwind
подключается через Vite-плагин, а не через PostCSS. Он **нигде не был подключён** (ни в `vite.config.js`,
ни в postcss), то есть был мёртвым весом, вводящим в заблуждение «а на какой мы линии?». Решение фичи —
зафиксировать фактически работающую v3 и убрать неиспользуемый v4-пакет; сама миграция v3→v4 явно отложена
(вне скоупа). Сборка (`app.css` 34.83 kB, `@tailwindcss/forms` на месте) подтвердила, что удаление пакета
ничего не ломает.

### Почему ESLint не форматирует, а `.editorconfig` — да
`eslint-plugin-vue` `flat/recommended` по умолчанию требует 2-пробельный `vue/html-indent`, а house-style
проекта — `.editorconfig` `indent_size = 4`. Если бы ESLint «чинил» отступы, он переформатировал бы весь
Breeze-скаффолд в 2 пробела вопреки `.editorconfig` — тысяча строк косметического diff, воюющего с редактором.
Идиоматичный разбор ролей: ESLint отвечает за **корректность** (неиспользованные переменные, слабые типы,
`no-undef`, vue-специфика), форматирование — за форматтером/`.editorconfig`. Поэтому чисто-косметические
vue-правила выключены явным блоком с человеческим комментарием, а не переформатированием. При этом
`vue/attributes-order` (не форматирование — порядок атрибутов; Prettier его не трогает) **оставлен включённым**
и автофикснут: он несёт реальную ценность консистентности и даёт нулевой конфликт с форматтером.

### Почему `route` пришлось объявить глобалом
`route()` (Ziggy) в шаблонах (`:href="route('login')"`) — глобальная функция; в `<script lang="ts">` её
видит TS через `global.d.ts` (`var route`), но в template-выражениях типовой информации нет, и eslint core
`no-undef` ругался. Объявление `route: 'readonly'` в `languageOptions.globals` закрывает 8 таких ошибок,
не ослабляя проверку в остальном.

### Почему `tests/Unit/.gitkeep`
`phpunit.xml` держит тест-сьют `Unit` с `<directory>tests/Unit</directory>`. Удаление единственного файла
(`ExampleTest.php`) оставило директорию пустой, а git пустые директории не отслеживает → `artisan test`
падал с «Test directory tests/Unit not found». `.gitkeep` сохраняет конвенционную структуру под будущие
unit-тесты без искусственного контента.

### Почему axios можно удалять
Grep по `resources/` показал `axios` только в `bootstrap.ts` (`window.axios = axios`) и его типовом
объявлении в `global.d.ts`. `window.axios` в коде нигде не читается. Inertia (`@inertiajs/vue3`) использует
собственный внутренний HTTP-клиент и на `window.axios` не полагается — доказано зелёной сборкой и живым
рендером страниц после удаления. Это убирает и мёртвую зависимость, и лишнюю глобальную поверхность.

## Почему так, а не иначе (отклонения от spec)

1. **Добавлен `tests/Feature/WelcomeTest.php`** — спека оставляла выбор «осмысленный welcome-тест или счесть
   избыточным». Взят первый вариант: фича правит `routes/web.php` (пропсы) и `Welcome.vue`, поэтому `GET / → 200`
   — дешёвый регресс-гард взамен удалённого стокового `ExampleTest`.
2. **`tests/Unit/.gitkeep`** — не был перечислен в spec; вынужденная мелочь, чтобы удаление
   `tests/Unit/ExampleTest.php` не сломало `phpunit.xml`-сьют Unit (см. выше).
3. **Косметические vue-правила выключены, `vue/attributes-order` — оставлен и автофикснут.** Spec требовал
   «0 ошибок/варнингов». Достигнуто разделением «корректность vs форматирование»: форматирование отдано
   `.editorconfig`, а не переформатированием скаффолда (что противоречило бы house-style и раздуло бы diff).
4. **Известная грабля pnpm 11.x (`onlyBuiltDependencies` → esbuild)** — НЕ воспроизвелась: локальный pnpm
   10.30.3, `pnpm-workspace.yaml` не трогался, сборка esbuild отработала штатно.

## Гейты (итог)

- Pest — **32 passed** (79 assertions), 0 fail/skip (было 33 в FEAT-004: −2 Example, +1 Welcome).
- PHPStan **L10** — `[OK] No errors` (baseline FEAT-004 не расширялся и не осиротел).
- Pint `--test` — `passed`.
- `pnpm lint` — 0 проблем; `pnpm typecheck` (`vue-tsc --noEmit`) — чисто; `pnpm build` — ✓ (Tailwind v3, без axios).
- Живая приёмка (изолированный Sail-стенд :8140, снят после): `GET /` → 200, `component:"Welcome"`, ноль утечек
  `laravelVersion`/`phpVersion`; `GET /login` → 200, `component:"Auth/Login"`, `canResetPassword` в пропсах.
  Checkbox `remember` — тип-правка подтверждена зелёными build/typecheck.

## Связи

- Фича: `../../features/FEAT-008-frontend-hygiene/` (`spec.md`, `impl.md`).
- Соседняя грабля-первоисточник (pnpm/esbuild): журнал FEAT-005/`infra-toolchain`.
