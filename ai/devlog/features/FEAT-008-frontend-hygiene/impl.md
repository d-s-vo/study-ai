---
feat: FEAT-008
repos: [cbook]
tags: [frontend, tooling, cleanup, typing]
class: 'гигиена фронта: смешение Tailwind-линий, отсутствие ESLint/typecheck-гейтов, any/wrapper-типы, мёртвый Breeze-скаффолд'
prevention: 'ESLint flat-config (typescript-eslint + vue) + скрипты lint/typecheck; ужесточённый tsconfig (noUnusedLocals/Parameters/noImplicitReturns/noFallthroughCasesInSwitch)'
---

# FEAT-008: Гигиена фронта и скаффолда — Implementation

## Статус: DONE
## Дата: 2026-07-31

Ветка `feat/frontend-hygiene`, коммит **`348396b`** (as-authored). Доставка — за пользователем.

## Что сделано

| Файл | Изменение |
|---|---|
| `package.json` | − `@tailwindcss/vite@^4` (не подключён), − `axios@^1` (мёртв); + eslint-стек (`eslint`, `@eslint/js`, `typescript-eslint`, `eslint-plugin-vue`, `vue-eslint-parser`); + скрипты `lint`/`typecheck` |
| `eslint.config.js` | НОВЫЙ — flat-config (base+ts+vue recommended), парсер vue+ts, игноры (vendor/node_modules/public/build/generated.d.ts), `route` глобал, off косметических vue-правил + `multi-word-component-names` |
| `tsconfig.json` | + `noUnusedLocals`, `noUnusedParameters`, `noImplicitReturns`, `noFallthroughCasesInSwitch`; `allowJs` оставлен `true` |
| `resources/js/Components/Checkbox.vue` | `value?: any` → `value?: string \| number \| boolean \| null` |
| `resources/js/bootstrap.ts` | удалён (мёртвый `window.axios`) |
| `resources/js/app.ts` | убран `import './bootstrap'` |
| `resources/js/types/global.d.ts` | удалены `import { AxiosInstance }` и `Window.axios`; убран лишний `eslint-disable no-var` |
| `app/Http/Middleware/HandleInertiaRequests.php` | удалён no-op override `version()`; `share()` не тронут |
| `routes/web.php` | убраны `laravelVersion`/`phpVersion` + импорт `Application` |
| `resources/js/Pages/Welcome.vue` | убраны version-пропсы и footer-строка версий |
| `tests/Pest.php` | удалены стоковые `toBeOne`/`something()` |
| `tests/Feature/ExampleTest.php`, `tests/Unit/ExampleTest.php` | удалены |
| `tests/Unit/.gitkeep` | НОВЫЙ — сохраняет конвенционную директорию для тест-сьюта Unit |
| `tests/Feature/UserRepositoryTest.php` | убран дубль `uses(RefreshDatabase::class)` |
| `tests/Feature/WelcomeTest.php` | НОВЫЙ — `GET / → 200` взамен удалённого ExampleTest |
| `resources/js/Pages/Profile/Partials/UpdateProfileInformationForm.vue` | `Boolean`/`String` → `boolean`/`string` (no-wrapper-object-types) + автофикс attributes-order |
| 9 Breeze SFC (Login, Register, Modal, TextInput, AuthenticatedLayout, ConfirmPassword, ForgotPassword, ResetPassword, VerifyEmail, UpdatePasswordForm) | только автофикс `vue/attributes-order` (перестановка атрибутов, поведение не меняется) |

## Отклонения от spec

1. **+ `tests/Feature/WelcomeTest.php`** — спека оставляла выбор на импле; взят вариант «осмысленный welcome-тест»
   (правка роута/страницы → дешёвый регресс-гард `GET / → 200`).
2. **+ `tests/Unit/.gitkeep`** — не в spec; вынужденно, иначе пустая `tests/Unit` (git не хранит пустые
   директории) ломает тест-сьют `Unit` в `phpunit.xml` (`artisan test` → «directory not found»).
3. **Косметические vue-правила отключены, `vue/attributes-order` оставлен и автофикснут.** «0 варнингов»
   достигнуто разделением ролей ESLint (корректность) / `.editorconfig` (форматирование, 4 пробела) — вместо
   переформатирования всего скаффолда в 2 пробела (противоречило бы `.editorconfig` и раздуло бы diff).
   Обоснование — в разборе коммита.

## Ключевые решения по ходу реализации

- **Tailwind: зафиксирована v3.** `@tailwindcss/vite@^4` был мёртвым весом (нигде не подключён) — удалён;
  миграция v3→v4 явно вне скоупа. Решение сформулировано нейтрально (без следов системы) в разборе коммита.
- **ESLint = корректность, форматтер = форматирование.** House-style — `.editorconfig` 4 пробела; выключены
  `vue/html-indent`, `max-attributes-per-line`, `html-closing-bracket-newline`, `html-self-closing`,
  singleline/multiline-content-newline. `vue/multi-word-component-names` off (Inertia-страницы односложны).
- **Находки ESLint (всё починено → 0):** до правок — 18 ошибок + 1279 варнингов. Ошибки: 8× `no-undef` на
  Ziggy `route` (→ объявлен глобалом), 8× `multi-word-component-names` (→ off по конвенции), 2×
  `no-wrapper-object-types` `Boolean`/`String` (→ примитивы в источнике). Варнинги: ~1186 `vue/html-indent`
  + ~90 прочих косметических (→ отданы `.editorconfig`, правила off) и 24 `vue/attributes-order`
  (→ автофикс, правило оставлено включённым). Плюс снят осиротевший `eslint-disable no-var` в `global.d.ts`.
- **axios безопасно удаляется:** grep подтвердил использование только в `bootstrap.ts`/`global.d.ts`;
  `window.axios` нигде не читается; Inertia несёт свой HTTP-клиент (доказано зелёной сборкой и живым рендером).
- **pnpm 11.x/esbuild-грабля НЕ воспроизвелась:** локально pnpm 10.30.3, `pnpm-workspace.yaml` не трогался,
  esbuild собрался штатно.

## Как тестировали

- `pnpm typecheck` (`vue-tsc --noEmit`) — чисто.
- `pnpm lint` — **0 проблем** (было 18 ошибок + 1279 варнингов).
- `pnpm build` (gate `frontend-build`) — ✓ 809 модулей, Tailwind v3 (`app.css` 34.83 kB), без axios/bootstrap.
- `sail artisan test` (gate `backend-tests`) — **32 passed** (79 assertions), 0 fail/skip.
- `sail bin phpstan analyse` (**L10**) — `[OK] No errors` (baseline FEAT-004 не расширялся/не осиротел).
- `sail bin pint --test` — `passed`.
- Живая приёмка (изолированный Sail-стенд :8140 / Vite 5213 / FORWARD_DB 3140 / redis_db 8; снят `sail down -v`):
  `GET /` → 200, `component:"Welcome"`, ноль `laravelVersion`/`phpVersion`; `GET /login` → 200,
  `component:"Auth/Login"`, `canResetPassword` в пропсах. Checkbox `remember` — тип-правка подтверждена build/typecheck.

## Пользовательская документация

Welcome-страница теряет footer-строку версий Laravel/PHP — незначительное user-visible изменение демо-страницы.
Публичной доки не требует. README (владелец — FEAT-005) не трогался этой фичей; строки про `pnpm lint`/`pnpm typecheck`
можно добавить поверх смерженной базы 005 при желании (не сделано, чтобы не пересекать зоны).

## Итог

Все шесть гейтов зелёные (pest / phpstan L10 / pint / lint / typecheck / build). Фронт-манифест приведён к одной
Tailwind-линии (v3), введены структурные гейты `lint`/`typecheck`, устранены `any`/wrapper-типы, вычищен мёртвый
Breeze-скаффолд. Рантайм-поведение бэка не менялось. Риски минимальны; будущий долг — миграция Tailwind v3→v4
(осознанно отложена) и опциональные README-строки про новые npm-скрипты.
