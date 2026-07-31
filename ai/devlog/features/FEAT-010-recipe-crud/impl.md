---
feat: FEAT-010
repos: [cbook]
tags: [backend, authz, security, validation, tests]
class: 'мутации домена Recipe: Tasks, FormRequests, RecipePolicy (анти-IDOR), мутационные маршруты; /profile под verified'
prevention: 'обязательные негативные тесты прав (чужой → 403), mass-assignment-негатив, red→green правки арх-барьера'
---

# FEAT-010: CRUD рецептов — Implementation

## Статус: DONE (merged → develop)
## Дата: 2026-07-31

## Что сделано

| Файл | Изменение |
|---|---|
| `app/Policies/RecipePolicy.php` | новая `final` Policy: viewAny/view/create → true (общий каталог, гейт — middleware auth+verified), update/delete → владелец |
| `app/Tasks/CreateRecipeTask.php` | новый Task: split payload → `RecipeRepository::createForUser` |
| `app/Tasks/UpdateRecipeTask.php` | новый Task: split payload → `RecipeRepository::update` |
| `app/Tasks/DeleteRecipeTask.php` | новый Task: делегат `RecipeRepository::delete` |
| `app/Http/Requests/StoreRecipeRequest.php` | новый FormRequest: полный набор правил (title/description/числа/`Rule::enum(Difficulty)`/steps.*/ingredients.*); `user_id` в правилах отсутствует |
| `app/Http/Requests/UpdateRecipeRequest.php` | наследует StoreRecipeRequest (полная замена рецепта — правила совпадают) |
| `app/Http/Controllers/RecipeController.php` | новый тонкий контроллер store/update/destroy: `findModel`+`abort_if 404`+`Gate::authorize` до Task; redirect → `dashboard` (страницы — FEAT-011) |
| `routes/web.php` | +`recipes.store/update/destroy` (`whereNumber`), группа profile переведена `auth` → `['auth','verified']` |
| `tests/Feature/ArchitectureTest.php` | allow-list +`App\Policies` с человеческим комментарием (Policy получает гидрированную модель, запросов не делает) |
| `tests/Feature/Recipe/RecipeCrudTest.php` | 13 кейсов: позитив create/update/delete, IDOR-негативы (403), mass-assignment-негатив, guest/unverified, 404, датасет валидационных негативов |
| `tests/Feature/ProfileTest.php` | +негатив: unverified `GET /profile` → redirect `verification.notice` |

Коммит: `632c4aa` `feat: мутации рецептов с проверкой владельца` (ветка `feat/recipe-crud`).
**Merged → develop fast-forward 2026-07-31 (вершина develop = `632c4aa`, хеш не менялся).** Интеграционный прогон гейтов на develop-дереве после merge: Pest 65/242 (0 fail), PHPStan L10 No errors, Pint pass. Уборка выполнена: стенд снесён (`sail down -v`, volumes удалены), worktree убран, бронь в архиве, feat-map — done.

## Отклонения от spec

1. **`(int) $request->user()->getAuthIdentifier()` заменён на `$request->user()->id`.** Спека предлагала каст `(int)` под L10, но гейт статанализа запрещает касты mixed→int как подавление. Root-cause: Larastan резолвит `$request->user()` в модель `User` по конфигу auth — `$user->id` уже типизирован `int`, каст не нужен. Арх-барьер не задет: имя класса `App\Models\User` в исходнике контроллера не упоминается (доступ по выведенному типу), что подтверждено зелёным барьером.
2. **`UpdateRecipeRequest` наследует `StoreRecipeRequest`**, а не дублирует правила (спека допускала «те же правила», дефолт «полный payload» сохранён).
3. Явного `authorize('create')` в store нет — как и предписывала спека (create-гейт = маршрутная middleware; ссылка `Recipe::class` в контроллере запрещена барьером).

## Ключевые решения по ходу реализации

- **Авторизация без модели в сигнатуре** — паттерн спеки работает: `findModel($id)` → `abort_if(null, 404)` → `Gate::authorize('update', $found)`. Larastan сужает `?Recipe` через `abort_if`, PHPStan L10 чист без подавлений.
- **Policy автодискавери** Laravel 12 подтверждён живьём: `App\Policies\RecipePolicy` подхватывается для `App\Models\Recipe` без регистрации в провайдере (живая приёмка вернула 403 чужому).
- **`whereNumber('recipe')`** на PUT/DELETE — нечисловой id даёт 404 на уровне роутера, а не ошибку приведения в контроллере.
- **Red→green правки арх-барьера доказан**: временное удаление `App\Policies` из allow-list → барьер падает на `RecipePolicy.php` (use App\Models); возврат → зелёный.

## Как тестировали

- Гейты (worktree-стенд Sail, порты брони 8120/5193/3120): Pest **65 passed (242 assertions), 0 fail** (было 51 на базисе); PHPStan **L10 No errors, 0 подавлений**; Pint **passed**.
- **Живая приёмка** (HTTP-сценарий curl на :8120, два пользователя): login 302 ×2; owner `POST /recipes` → 302 → `/dashboard`, рецепт+ингредиент в БД; stranger `PUT`/`DELETE` чужого → **403** оба; owner `PUT` → 302; owner `DELETE` → 302; после удаления `recipes=0 ingredients=0` (каскад подтверждён). Тестовые данные стенда убраны самим сценарием.
- Верифицированность: unverified-редиректы (`verification.notice`) покрыты фича-тестами (recipes POST + `/profile`).

## Пользовательская документация

Checked, no changes needed: UI/страниц в фиче нет (мутации backend-only, формы придут в FEAT-011), публичное поведение для пользователя не меняется. Перевод `/profile` под verified — поведенческая правка, но она отражена в README клиента ещё нотой FEAT-007 о включённой email-верификации; отдельной правки не требует.

## Ревью

- **Ревью чистоты** (внешний ревьюер без доступа к `ai/`): **ЧИСТО** — следов системы нет, стиль/язык комментариев соответствуют сложившемуся разделению (scaffolding Breeze — англ., доменный код — рус.).
- **Независимое коммит-ревью ADR-010** (`632c4aa-review.md`): **Verdict PASS**, блокеров нет; гейты перепроверены ревьюером независимо. 3 advisory-нита **приняты без фикса с записью** (все — тестовые, закрыть попутно в FEAT-011, которая и так правит эти тесты под новые redirect-таргеты):
  1. IDOR-негатив update не ассертит неизменность ингредиентов (риск нулевой: authorize до Task);
  2. 404-путь покрыт тестом для update, но не для destroy (код-путь идентичен);
  3. тест спуфа владельца не изолирует один слой защиты (двухслойность validated()+fillable сознательная).

## Итог

Работает: защищённые мутации домена Recipe целиком (валидация → авторизация владельца → Task → Repository), IDOR закрыт Policy + обязательными негативными тестами, подмена владельца через payload невозможна. Риски: redirect-таргеты временно ведут на `dashboard` — FEAT-011 перенаправит на `recipes.show/index` и обновит соответствующие ассерты; каталог просмотра (`view/viewAny → true`) станет наблюдаемым только со страницами 011.
