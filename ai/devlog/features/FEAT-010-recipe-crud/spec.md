# FEAT-010: CRUD рецептов — Tasks, FormRequests, RecipePolicy, мутационные маршруты

## Статус: SPEC

## Затрагиваемые репозитории
cbook (backend) — один репозиторий. Мультирепный рецепт §3.5 не применяется.

## Цель
Дать защищённые **мутации** домена: создание/изменение/удаление рецепта (вместе с ингредиентами) через слой `Task` (бизнес-операция), валидацию во `FormRequest`, авторизацию по владельцу через `RecipePolicy` и тонкие контроллеры с мутационными маршрутами. Ключевая ценность фичи — **изоляция по владельцу (защита от IDOR)**: чужой пользователь, пытающийся изменить/удалить рецепт, получает 403.

## Контекст
База — `origin/develop` поверх **FEAT-009** (миграции, модели `Recipe`/`Ingredient`, `Difficulty`, `RecipeRepository` с методами `createForUser`/`update`/`delete`/`findModel`, DTO). FEAT-010 добавляет слои записи и авторизации; чтение/страницы (index/show/create/edit) — в **FEAT-011**.

**Зачем Task и Policy (педагогика).** `Task` — одна бизнес-операция (`CreateRecipeTask`): контроллер остаётся тонким (валидация → делегирование → ответ), а логика «как создать рецепт с ингредиентами» живёт в одном тестируемом классе (`final`, зависимости `private readonly` в конструкторе, вход — аргументы `run()`; канон из `ai/memory.md` §Gotchas «Канон Task»). `Policy` централизует ответ на вопрос «можно ли этому пользователю трогать этот рецепт» — авторизация проверяется **до** бизнес-логики, а не размазана по контроллерам; это структурная защита от IDOR (доступ к чужому объекту по прямому id).

Инварианты: `ai/memory.md` §North Star (5 STRICT RULES), `stack-specifics.md` §Backend, `architecture.md` §8 (изоляция по владельцу + обязательные негативные тесты).

## Принятые решения на развилках (зафиксировано)

### 1. Границы FEAT-010 / FEAT-011
- **В 010:** мутационные маршруты (`POST/PUT/DELETE`), контроллеры мутаций (redirect-ответы), Tasks, Store/Update FormRequest, `RecipePolicy` (полная), негативные тесты прав.
- **В 011:** GET-страницы (`index`/`show`/`create`/`edit`), Page Resolvers, Inertia Vue-страницы, пагинация.
- **Проблема redirect-таргета:** контроллеры мутаций после успеха должны редиректить на GET-страницу (`recipes.show`/`recipes.index`), а эти маршруты появляются только в 011. **Решение:** в 010 мутационные контроллеры редиректят на **существующий** маршрут `dashboard` (Breeze, `routes/web.php`), чтобы 010 был самодостаточен и зелёный standalone (маршрут определён, redirect-тесты проходят). В **011** redirect-таргеты перенаправляются на `recipes.show`/`recipes.index` (правка тех же контроллеров) — это явно зафиксировано в «Что НЕ входит» обеих фич. Тесты 010 ассертят `assertRedirect(route('dashboard'))`; 011 обновит их на `recipes.*`.

### 2. Права просмотра — ОБЩИЙ КАТАЛОГ (решение владельца, 2026-07-31)
- **Просмотр** (index/show, реализуется в 011): **любой аутентифицированный+verified видит ВСЕ рецепты** — index отдаёт все рецепты с пагинацией (`RecipeRepository::paginate()`, без owner-скоупа), show доступен для любого рецепта (200). Модель общего каталога.
- **Мутации + форма редактирования** (create/update/delete + страница `edit`) — **только владелец**: create — любой auth+verified создаёт свой рецепт; update/delete/edit — только владелец, чужой → **403** (защита от IDOR).
- `RecipePolicy`: `viewAny → true`, `view → true` (просмотр открыт всем auth+verified — гейтом служит маршрутная мидлвара `auth`+`verified`); `create → true`; `update`/`delete` → владелец. (Отдельного `edit`-метода Policy нет — страница edit авторизуется абилити `update`.)

## Acceptance Criteria
- [ ] Маршруты (в группе `Route::middleware(['auth','verified'])->group(...)`, `routes/web.php`, dot-имена):
  - [ ] `POST /recipes` → `recipes.store`
  - [ ] `PUT /recipes/{recipe}` → `recipes.update`
  - [ ] `DELETE /recipes/{recipe}` → `recipes.destroy`
  - `{recipe}` — **id (int)**, без implicit route-model binding (иначе контроллер сослался бы на `App\Models\Recipe` → нарушение арх-барьера).
- [ ] `app/Policies/RecipePolicy.php`: `viewAny(User): true`, `view(User,Recipe): true` (общий каталог), `create(User): true`, `update(User,Recipe): владелец`, `delete(User,Recipe): владелец`. Автодискавери Laravel 12 (регистрация в провайдере не требуется — сверено).
- [ ] `tests/Feature/ArchitectureTest.php` allow-list расширен: `App\Models` разрешён также в `App\Policies` (Policy получает гидрированную модель для authz, **запросов не делает**; барьер фасада `DB` не меняется). Изменение задокументировано комментарием в тесте (человеческим языком).
- [ ] `POST /recipes` валидным payload под аутентифицированным+verified → рецепт+ингредиенты создаются, `user_id` = текущий пользователь, redirect (302) на `dashboard`.
- [ ] `PUT /recipes/{id}` владельцем → рецепт и ингредиенты обновлены (синхронизация); `DELETE` владельцем → рецепт и ингредиенты удалены (каскад).
- [ ] **Негатив (IDOR):** `PUT`/`DELETE` чужого рецепта (не владелец) → **403** (не 200/302, не 500), данные не изменены. Обязательные тесты.
- [ ] **Негатив (auth):** гость → 302 на login; аутентифицированный, но **не verified** → redirect на `verification.notice` (middleware `verified`).
- [ ] **Негатив (валидация):** невалидный payload (пустой title, `difficulty` вне enum, `steps` не массив, ингредиент без `name`) → 422/redirect с ошибками валидации, запись не создана.
- [ ] `user_id` из payload игнорируется (нельзя назначить чужого владельца) — negative-тест на mass assignment.
- [ ] Гейты: PHPStan L10 (0 подавлений), Pint pass, Pest 0 fail (вкл. новые), арх-барьер зелёный.

## Технический дизайн

### RecipePolicy (авторизация — до бизнес-логики)
- `app/Policies/RecipePolicy.php`, методы принимают `App\Models\User $user` и `App\Models\Recipe $recipe`; владение — `$user->id === $recipe->user_id`.
  ```
  public function viewAny(User $user): bool                { return true; } // общий каталог: все видят список
  public function view(User $user, Recipe $recipe): bool   { return true; } // общий каталог: все видят любой рецепт
  public function create(User $user): bool                 { return true; } // любой auth+verified
  public function update(User $user, Recipe $recipe): bool { return $user->id === $recipe->user_id; }
  public function delete(User $user, Recipe $recipe): bool { return $user->id === $recipe->user_id; }
  ```
  > `view`/`viewAny → true`: реальный гейт просмотра — маршрутная мидлвара `auth`+`verified`. Методы оставлены в Policy для явности контракта и единой точки, если владелец позже сузит просмотр.
- **Арх-барьер:** `RecipePolicy` ссылается на `App\Models\{User,Recipe}` — namespace `App\Policies` добавляется в allow-list правила «Eloquent-модели — только в …» (см. AC). Обоснование: Policy читает атрибуты уже загруженной модели для решения authz, **не выполняет запросов** (правило фасада `DB` неизменно — запросы по-прежнему только в репозитории). Это единственная точка касания модели вне репозитория, и она изолирована (authz-контракт фреймворка).
  > Эта правка арх-инварианта — осознанное расширение allow-list, не новый паттерн/технология. **Решение владельца (2026-07-31): без ADR — достаточно фиксации в этой спеке + человеческого комментария в arch-тесте** (критерии `feature-workflow` §4.5 не требуют ADR).

### Авторизация в контроллере (без модели в сигнатуре)
Контроллер не может тип-хинтить `Recipe`. Схема для update/delete:
```
$recipe = $this->recipes->findModel($id);      // репозиторий отдаёт модель как значение (без явной ссылки на класс)
abort_if($recipe === null, 404);
$this->authorize('update', $recipe);           // Gate → RecipePolicy::update(user, recipe)
$this->updateRecipeTask->run($id, $request->validated());
```
- `$recipe` — переменная выведенного типа `?Recipe`; в исходнике контроллера **нет** `use App\Models\Recipe`/тип-хинта → арх-барьер (сканирует ссылки на классы) не срабатывает. Паттерн скопирован с `Authenticatable` в `UserRepository`/`ProfileController`.
- Для `store`: авторизация «create» = middleware `auth`+`verified` (владения ещё нет); явный `authorize('create', Recipe::class)` **не** вызывается (ссылка на `Recipe::class` в контроллере запрещена барьером). Документировать: create-гейт = маршрутная мидлвара.

### Tasks (`app/Tasks/`, канон: `final`, `private readonly` DI, `run()`)
Task-и **не ссылаются на модели** — оперируют скалярами/массивами и делегируют в `RecipeRepository`:
- `CreateRecipeTask`:
  ```
  final class CreateRecipeTask extends BaseTask {
      public function __construct(private readonly RecipeRepository $recipes) {}
      /** @param array<string,mixed> $data */
      public function run(int $userId, array $data): int {  // id нового рецепта
          [$recipeAttributes, $ingredients] = $this->split($data);
          return $this->recipes->createForUser($userId, $recipeAttributes, $ingredients);
      }
  }
  ```
- `UpdateRecipeTask::run(int $id, array $data): void` — `$this->recipes->update($id, $recipeAttributes, $ingredients)`.
- `DeleteRecipeTask::run(int $id): void` — `$this->recipes->delete($id)`.
- Разделение `$data` на атрибуты рецепта и массив ингредиентов (`$data['ingredients']`) — приватный хелпер в Task (или уже нормализованная структура из FormRequest). Никаких `Eloquent`/`DB` в Task.

### FormRequests (`app/Http/Requests/`, `authorize()` + `rules()`)
- `StoreRecipeRequest` и `UpdateRecipeRequest` (по образцу `RegisterRequest`/`ProfileUpdateRequest`):
  ```
  public function authorize(): bool { return true; } // авторизация ресурса — через Policy в контроллере
  /** @return array<string, ValidationRule|array<mixed>|string> */
  public function rules(): array {
      return [
          'title'                 => ['required','string','max:255'],
          'description'           => ['required','string'],
          'cooking_time'          => ['required','integer','min:1'],
          'servings'              => ['required','integer','min:1'],
          'difficulty'            => ['required', Rule::enum(Difficulty::class)],
          'steps'                 => ['required','array','min:1'],
          'steps.*'               => ['required','string'],
          'ingredients'           => ['required','array','min:1'],
          'ingredients.*.name'    => ['required','string','max:255'],
          'ingredients.*.quantity'=> ['required','numeric','min:0'],
          'ingredients.*.unit'    => ['required','string','max:50'],
      ];
  }
  ```
  - `Rule::enum(Difficulty::class)` — валидирует `low|medium|high` централизованно.
  - `user_id`/`recipe_id` в правилах **отсутствуют** — владелец берётся из `auth()`, не из ввода (IDOR/mass-assignment защита).
  - `UpdateRecipeRequest` — те же правила (полная замена рецепта); при необходимости `sometimes` — решить при импле, дефолт «полный payload».

### Контроллер (`app/Http/Controllers/RecipeController.php`, тонкий)
- Конструкторная DI: `private RecipeRepository $recipes`, `private CreateRecipeTask ...`, `private UpdateRecipeTask ...`, `private DeleteRecipeTask ...` (стиль существующих контроллеров — `private`, не `readonly`).
- `store(StoreRecipeRequest $request): RedirectResponse` — `$id = $this->createRecipeTask->run((int) $request->user()->getAuthIdentifier(), $request->validated()); return redirect()->route('dashboard');` (в 011 → `recipes.show`, $id). Каст `(int)` — `getAuthIdentifier(): mixed` под L10.
- `update(UpdateRecipeRequest $request, int $recipe): RedirectResponse` — authz-схема выше → task → redirect `dashboard` (в 011 → `recipes.show`).
- `destroy(Request $request, int $recipe): RedirectResponse` — `findModel`+`authorize('delete')`→`DeleteRecipeTask::run`→redirect `dashboard` (в 011 → `recipes.index`).
- Никакого Eloquent/`DB`; бизнес-логики нет.

## Тесты
**Добавить:** `tests/Feature/Recipe/RecipeCrudTest.php` (RefreshDatabase авто) —
- Позитив: `actingAs($owner)->post('/recipes', $valid)` → 302 `dashboard`, `assertDatabaseHas('recipes', ['user_id'=>$owner->id,'title'=>...])` + ингредиенты.
- Позитив: владелец `put`/`delete` → данные обновлены/удалены (+каскад ингредиентов).
- **Негатив прав (IDOR):** `actingAs($other)->put("/recipes/{$ownersRecipe->id}", ...)` → **403**, `assertDatabaseHas` неизменённых данных; то же для `delete` → 403.
- **Негатив mass-assignment:** payload с `user_id => $other->id` → созданный рецепт всё равно `user_id = $owner->id` (id из auth, не из ввода).
- **Негатив auth:** гость `post` → redirect login; verified-негатив — неверифицированный `post` → redirect `verification.notice` (использовать `User::factory()->unverified()`).
- **Негатив валидации:** пустой `title` / `difficulty='extreme'` / `steps` не массив / ингредиент без `name` → session errors, запись не создана.
**Обновить:** `tests/Feature/ArchitectureTest.php` — allow-list `+App\Policies` (и, при добавлении, характеризующий red→green кейс, что барьер по-прежнему ловит утечку модели в Task/Controller).
**Удалить:** нет.

> Права/чувствительные данные: негативные тесты (чужой → 403, изоляция по владельцу, mass-assignment) — **обязательны** (`architecture.md` §8, `stack-specifics.md` §Тесты).

## Типизация/качество
- Гейты: `sail bin phpstan analyse` (L10, 0 подавлений), `sail bin pint --test`, `sail artisan test`, арх-барьер зелёный.
- FormRequest-правила — единственный источник серверной валидации мутаций; контроллеры тонкие.
- DTO/типы не меняются (контракт из 009) — `typescript:transform` повторно не требуется (нет новых DTO).

## Безопасность
- **Доступы (authz):** каждый мутационный маршрут — под `auth`+`verified`; update/delete — явный `authorize()` (Policy, владелец) **до** бизнес-логики. Least privilege: пользователь меняет только свои рецепты.
- **IDOR:** прямой доступ по чужому id (`PUT/DELETE /recipes/{чужой}`) → 403 (Policy). Обязательный негативный тест — ядро фичи.
- **Mass assignment:** `user_id`/`recipe_id` вне `$fillable` (FEAT-009) и вне правил FormRequest; владелец — из `auth()`. Подмена владельца через payload невозможна (негативный тест).
- **Валидация:** весь внешний ввод (title/description/числа/enum/steps/ingredients) валидируется во FormRequest **до** Task; `Rule::enum` не допускает произвольный `difficulty`.
- **SQL-инъекции:** запись только через Eloquent/репозиторий (параметризация), без raw SQL с вводом.
- **Гигиена §8:** контроллеры/Tasks/Requests/Policy/тесты — человеческий стиль, без следов системы; правка `ArchitectureTest` (внутренний тест клиента) — человеческий комментарий, без FEAT-номеров.

## Пользовательская документация
User-visible появится вместе со страницами (011). В 010 — только backend-мутации без UI (форма/страницы — 011). Публичной доки не требуется; отметить в `impl.md` (checked, no changes needed; UI-часть — 011).

## Зависимые файлы для изменения
| Файл | Тип изменения |
|---|---|
| `app/Policies/RecipePolicy.php` | новый (viewAny/view/create/update/delete) |
| `app/Tasks/CreateRecipeTask.php` | новый Task |
| `app/Tasks/UpdateRecipeTask.php` | новый Task |
| `app/Tasks/DeleteRecipeTask.php` | новый Task |
| `app/Http/Requests/StoreRecipeRequest.php` | новый FormRequest |
| `app/Http/Requests/UpdateRecipeRequest.php` | новый FormRequest |
| `app/Http/Controllers/RecipeController.php` | новый тонкий контроллер (store/update/destroy) |
| `routes/web.php` | +мутационные маршруты `recipes.store/update/destroy` |
| `tests/Feature/ArchitectureTest.php` | allow-list `+App\Policies` |
| `tests/Feature/Recipe/RecipeCrudTest.php` | новые тесты (позитив + негатив прав/валидации) |

## Что НЕ входит в эту фичу
- **GET-страницы** `index`/`show`/`create`/`edit`, Page Resolvers, Inertia Vue-страницы, пагинация — **FEAT-011**.
- **Перенаправление redirect-таргетов** на `recipes.show`/`recipes.index` — делает 011 (в 010 redirect → `dashboard`).
- Слой данных (миграции/модели/repository/DTO/фабрики) — FEAT-009.
- Filament 5 Resource, изображения (`whyme-agency/laravel-media`), BVI, публичный каталог/поиск — вне пакета.

## Оценка сложности
Средняя-высокая. Риски: (1) соблюсти арх-барьер при авторизации по владельцу — контроллер/Task не должны ссылаться на `Recipe` (паттерн `findModel`+переменная); правка allow-list под `App\Policies` — единственная санкционированная точка касания модели вне репозитория; (2) флейки/состояние между тестами прав (RefreshDatabase покрывает); (3) корректная валидация вложенных ингредиентов (`ingredients.*`). Модель просмотра решена (общий каталог) — `view`/`viewAny → true`; IDOR-контроль касается только мутаций.
