---
repo: cbook
authored_hash: e0c8ee3ea9dc7e522fbaa3f5928cdb82623a750a
patch_id: c5173dcc4bfc3d506715982d339812f64cdf79c2
feat: FEAT-004
branch: feat/breeze-inertia-auth
reviewer_model: Opus 4.8
review_date: 2026-07-30
verdict: PASS
blockers_total: 0
blockers_open: 0
resolved_by: []
---

# cbook@e0c8ee3 — REVIEW — feat: скелет фронтенда на Inertia/Vue и авторизация через слой репозиториев

**Verdict:** PASS
**Blocking findings:**
- нет
**Non-blocking notes:**
- `app/Http/Middleware/HandleInertiaRequests.php:38` — в Inertia отдаётся сырая Eloquent-модель `$request->user()` (STRICT RULE 4 «только DTO наружу»). Реачабилити: явно выведено из скоупа spec («данные о юзере отдаёт Inertia middleware Breeze как есть») и не ловится arch-тестом (нет импорта `App\Models`, доступ через `Request::user()`). Долг под доменную фазу (severity: minor, отложено spec).
- `UserRepository.php:24,36,47` + `PasswordController.php:31`, `ProfileController.php:40,57`, `NewPasswordController.php:59` — `assert(...)` при `zend.assertions=-1` (prod) компилируется в no-op. Проверено, что это НЕ прячет баг: (а) `assert($user !== null)` избыточен — при null typed-параметр `Authenticatable $user` в методах репозитория самостоятельно бросит `TypeError`; (б) `assert($user instanceof User)` достижимо-ложен только при недефолтном auth-provider (в текущем конфиге guard отдаёт `User`); (в) `assert(is_string($status))` — `Password::reset()` всегда возвращает string. Информационно (severity: nit).
- Крупный коммит (6083 insertions), но хендрайтен-поверхность мала; основной объём — механический Breeze-scaffold + lock-файлы. Разбиение scaffold↔рефактор оставило бы промежуточный red-arch state. Атомарен как единица фичи-скелета (severity: nit).

**Evidence:**
- Прочитано ПЕРЕД diff: spec.md + AC, ADR-003 (keystone, 5 STRICT RULES), разбор автора e0c8ee3-breeze-inertia-auth.md, impl.md.
- Гейты перепрогнаны сам (Sail up): `sail bin phpstan analyse` → `[OK] No errors` (L10); `sail bin pint --test` → `passed`; `sail artisan test` → `33 passed (80 assertions)`, arch-тест `PASS Tests\Feature\ArchitectureTest`, 0 fail/skip.
- Изоляция Eloquent: `grep -rn 'App\Models|User::|->save()|->delete()|->update(|Facades\DB' app/` вне `app/Models/` и `app/Data/Repositories/` → **пусто**. Единственное `User::create` — в `UserRepository::create`. Мутации (`setPassword/updateProfile/delete`) принимают `Authenticatable`, `User` не протекает типом в контроллеры/Task.
- Parity критического пути (сверка с дефолтным Breeze): `setPassword(rotate:true)` = forceFill(password)+setRememberToken+save (= reset-поведение); `rotate:false` = forceFill(password)+save (= бывший `->update`); `updateProfile` fill→isDirty('email')→null→save (точная копия); `destroy` — `$user` захвачен ДО `Auth::logout()`, затем delete + session invalidate/regenerate — порядок и инвалидация сессии сохранены; регистрация `unique:users,email` ≡ `unique:User::class`; `ProfileUpdateRequest` `getAuthIdentifier()` ≡ `->id`.
- Тесты мутационно (UserRepositoryTest, 6 кейсов): create→Hash::check true & не plaintext (ловит удаление Hash::make); setPassword rotate:true→remember_token изменён и не null (ловит отсутствие ротации); **rotate:false→токен == 'keep-me'** (негативный, ловит всегда-ротацию); updateProfile email-change→email_verified_at null; **name-only→email_verified_at НЕ null** (негативный, ловит всегда-сброс); delete→assertDatabaseMissing. Ни один не вакуумен. Breeze Auth-набор (RegistrationTest, ProfileTest, PasswordUpdateTest, PasswordResetTest) покрывает HTTP-высоту и негативы (неверный пароль на delete/update).
- Baseline: 8 записей, все — нетронутый framework-scaffolding (email-verification контроллеры `User|null`, LoginRequest `Stringable`); наших файлов (`UserRepository`, `RegisterUserTask`, отрефакторенные контроллеры) в baseline нет. Обоснованно и минимально.
- Следов системы/ИИ в diff не замечено (это зона Шага 12, отдельный агент — не дублирую).

**Suggested next:** advisory

## Рубрика (бинарно, commit-review.md §3)

☑ Атомарность/целостность (крупный, но единица фичи-скелета; компилируется, гейты зелёные) · ☑ Логика vs спека/интент (все AC покрыты; parity дефолтного Breeze сохранён) · ☑ Business-security (auth-контур: пароли только `Hash::make` в репозитории; логаут+инвалидация сессии при удалении аккаунта; профиль/удаление строго над `$request->user()`; валидация во FormRequest/`$request->validate` до бизнес-логики)
☑ Тихие регрессии/parity (маршруты/редиректы/события сохранены; email_verified_at reset воспроизведён точно) · ☑ Тесты (мутационно — негативные кейсы rotate:false и name-only ловят инверсию условий)
☑ N+1/перф (нет циклов запросов; single-record операции) · ☑ Over-engineering (3 скаляра вместо DTO — обоснованно; пустой BaseTask — канон референса)

## Журнал закрытия находок

- Non-blocking #1 (сырой User в Inertia) → отложено spec под доменную фазу; на приёмку оркестратору как advisory.
- Non-blocking #2 (assert no-op в prod) → информационно, дефекта не влечёт (Evidence выше); закрытия не требует.

## Связи

- Разбор «почему» (автор, ADR-009): `e0c8ee3-breeze-inertia-auth.md` (рядом).
- Фича: `../../features/FEAT-004-breeze-inertia-auth/impl.md` · `spec.md`.
- ADR/keystone: `../../adr/003-layered-architecture.md` (5 STRICT RULES, изоляция Eloquent).
- Гайд ревью: [`../../guides/commit-review.md`](../../guides/commit-review.md).
