---
repo: cbook
authored_hash: e847f28c5119d8dc6388dcf083603c42e16c9303
patch_id: 07862cced0913552bb6ae7037a95ca400c9e2282
branch: feat/filament-admin
feat: FEAT-013
date: 2026-08-03
---

# cbook@e847f28 — управление рецептами через админ-панель

> Коммит-сообщение (как в клиентском репо): `feat: управление рецептами через админ-панель`

## Кратко (для инженера)

- `app/Filament/Resources/Recipes/RecipeResource.php` — `$model = Recipe::class` (Eloquent-модель в Filament-слое — прочитайте раздел ниже, это ADR-011, не случайность); `getPages()` → `index`/`create`/`edit` (без отдельного `view` — редактирование доступно сразу).
- `app/Filament/Resources/Recipes/Schemas/RecipeForm.php` — форма: `Select('user_id')` (автор, опции из `UserRepository::selectOptions()`, `disabledOn('edit')` — автора нельзя сменить после создания), скалярные поля рецепта, `Select('difficulty')` от `Difficulty` enum, `Repeater::simple()` для `steps` (плоский список строк), `Repeater` со schema для `ingredients` (`name`/`quantity`/`unit`, 3 колонки).
- `app/Filament/Resources/Recipes/Tables/RecipesTable.php` — колонки рецепта + `user.name` (автор) + `ingredients_count` (`->counts('ingredients')`); `EditAction` в строке, `DeleteBulkAction` с кастомным `->using()`.
- `app/Filament/Resources/Recipes/Pages/CreateRecipe.php` — `handleRecordCreation()` не делает `Recipe::create()`: достаёт `user_id` из данных формы, вызывает `CreateRecipeTask::run((int) $authorId, $data)`, затем перечитывает созданную модель через `RecipeRepository::findModel()` для возврата в Filament (`assert($recipe !== null)`).
- `app/Filament/Resources/Recipes/Pages/EditRecipe.php` — `mutateFormDataBeforeFill()` подмешивает `ingredients` в данные формы через `RecipeRepository::ingredientsAsFormData()` (ингредиенты — связь, не колонка `recipes`, поэтому форма их сама не увидит без явной подгрузки); `handleRecordUpdate()` → `UpdateRecipeTask::run($record->id, $data)`; `getHeaderActions()` → `DeleteAction::make()->using(...)` вызывает `DeleteRecipeTask::run($record->id)` вместо стандартного `$record->delete()`.
- `app/Data/Repositories/RecipeRepository.php` — `+ingredientsAsFormData(int $recipeId): array` — грузит рецепт с `ingredients`, мапит в `{name, quantity, unit}[]` под форму.
- `tests/Feature/ArchitectureTest.php` — allow-list правила №1 (`App\Models` → только...) расширен на `'App\Filament'`.

## Детально (для новичка)

### Зачем это всё: конфликт Filament с изоляцией Eloquent и как его разрешает ADR-011

До этого коммита в проекте действовал жёсткий машинно-проверяемый барьер (`ArchitectureTest`): класс `App\Models\Recipe` разрешено импортировать только внутри `App\Data\Repositories`, `App\Policies`, фабрик и сидеров — нигде больше, включая контроллеры (они получали модель только через репозиторий и никогда не тип-хинтили её напрямую, см. `632c4aa`). Проблема в том, что Filament `Resource` устроен вокруг Eloquent-модели по своей природе: `protected static ?string $model = Recipe::class` — обязательный контракт, а таблица/форма/пагинация строятся поверх `getEloquentQuery()`, который возвращает `Builder<Recipe>`. Взять и написать `RecipeResource`, назвав в нём `App\Models\Recipe`, — значит физически покраснить барьер (это было проверено red→green: без строки `'App\Filament'` в allow-list `ArchitectureTest` падает именно на этом файле).

ADR-011 (`ai/adr/011-filament-admin-boundary.md`) разбирает три варианта и выбирает гибрид (вариант C): **чтение** модели в `app/Filament` — разрешаем (расширяем allow-list правила №1); **мутации** — по-прежнему запрещены напрямую, идут через уже существующие `Tasks`/`RecipeRepository`, ничего нового не изобретается. Второе правило барьера (обращение к фасаду `DB` — только в репозиториях) не тронуто вовсе — оно продолжает быть машинным guard'ом против сырых записей в обход домена, в том числе из Filament.

### Почему это не "дыра" в архитектуре, а точечное и доказанное решение

Ключевая деталь: расширение allow-list — не "на всякий случай", а обосновано конкретным фактом (red→green demo из ADR) и обёрнуто минимально — только чтение. Если бы `CreateRecipe`/`EditRecipe` делали `$this->record->save()` напрямую, они бы обошли `RecipeRepository::create/update`, которые делают транзакционную синхронизацию ингредиентов (создать/удалить/пересоздать строки `ingredients` атомарно с рецептом) — получился бы второй, параллельный путь мутации агрегата "рецепт+ингредиенты", с риском рассинхрона и дублирования бизнес-правил. Поэтому обе мутационные страницы — `CreateRecipe`/`EditRecipe` — переопределяют Filament-хуки (`handleRecordCreation`, `handleRecordUpdate`, действие `DeleteAction`) так, чтобы реальная запись всегда шла через тот же `CreateRecipeTask`/`UpdateRecipeTask`/`DeleteRecipeTask`, что и публичные маршруты `/recipes` из FEAT-010. Единственное, для чего Resource сам трогает модель, — это *прочитать* её обратно после мутации (`RecipeRepository::findModel($id)`), чтобы вернуть Filament ожидаемый им объект `Model`.

### Почему ингредиенты — `Repeater` в форме, а не `RelationManager`

Спека формулировала раздел ингредиентов как связь ("RelationManager"), но реализация — `Repeater` внутри той же формы рецепта. Это осознанное отклонение, а не недосмотр, по трём причинам:

1. **RelationManager не существует на этапе создания.** RelationManager Filament привязан к уже существующей родительской записи (у только что открытой формы создания рецепта родителя ещё нет — он появится после сохранения). А по бизнес-правилу (`CreateRecipeTask`) рецепт и его ингредиенты должны создаваться одной транзакцией с самого начала, а не рецепт сначала, ингредиенты — отдельным дозаполнением после.
2. **`UpdateRecipeTask` синхронизирует ингредиенты через полное удаление+пересоздание списка**, что соответствует модели "весь список отправляется формой целиком" (как и делает `Repeater` — при сохранении формы Filament получает актуальный полный массив `ingredients`), а не отдельным CRUD-действиям над одной строкой связи, на которые рассчитан RelationManager (добавить одну запись, отредактировать одну запись).
3. **Смысловая модель домена.** Спека сама описывает `Ingredient` как часть композиции агрегата `Recipe`, без независимого жизненного цикла (ингредиент не существует и не имеет смысла без рецепта). `Repeater`, редактируемый как часть формы рецепта, ближе к этой модели, чем независимый RelationManager с собственным CRUD и собственной страницей — который подразумевал бы, что ингредиент можно создать/удалить вне контекста формы рецепта.

`EditRecipe::mutateFormDataBeforeFill()` — техническая деталь, которая следует из этого выбора: `ingredients` не колонка таблицы `recipes`, а отдельная связь `hasMany`, поэтому стандартное автозаполнение формы Filament (которое читает атрибуты модели) её не увидит без явной подгрузки — отсюда `RecipeRepository::ingredientsAsFormData()`, вызванный именно в этом хуке.

### Автор рецепта: `Select` только на создании, супер-доступ админа

`Select::make('user_id')` с `disabledOn('edit')` — автора можно выбрать только при создании, при редактировании поле показывается, но недоступно для изменения (правило "владелец рецепта не меняется задним числом" даже для админа). Опции берутся из `UserRepository::selectOptions()` — списка `id => name`, добавленного предыдущим коммитом; сам Select не делает запрос к `User` напрямую. Что до видимости: `RecipesTable`/`ListRecipes` показывают рецепты всех авторов, потому что для админа `RecipePolicy::before()` (из `b0a56ff`) уже даёт супер-доступ — никакого дополнительного скоупинга в самом Resource не требуется, авторизация Filament-ресурсов по умолчанию идёт через ту же Policy модели.

### L10-детали без подавлений

В `CreateRecipe`/`EditRecipe` встречаются места вида `assert($recipe instanceof Recipe)` и явные приведения `(int) $authorId` вместо `$record->getKey()`. Причина — проектное правило (унаследованное из более ранних фич): подавления `mixed → int` через каст запрещены как способ "заглушить" статанализатор. Вместо этого код опирается на типизированную модель: после `assert()` PHPStan знает точный тип `$recipe`/`$record` (не `Model`, а именно `Recipe`), и его `id` уже типизирован как `int` — без нужды кастовать `getKey(): int|string` вручную. Итог по всей фиче — PHPStan level 10, 0 ошибок, 0 подавлений в `app/Filament`.

## Почему так, а не иначе

- **Вариант A (Filament мутирует Eloquent напрямую)** — отклонён ADR-011: дублирует транзакционную синхронизацию ингредиентов из `RecipeRepository`, размазывает бизнес-логику по Resource.
- **Вариант B (модель вообще не появляется в `app/Filament`)** — отклонён ADR-011: означал бы кастомную реализацию table query/сортировки/пагинации в обход штатного механизма Filament — много хрупкого кода ради принципа, который и так частично защищён правилом про `DB`.
- **`RelationManager` для ингредиентов (буквально по тексту спеки)** — отклонено в пользу `Repeater`: см. три причины выше (create-time атомарность, модель синхронизации Update-таска, смысловая композиция агрегата).

## Связи

- ADR: `ai/adr/011-filament-admin-boundary.md` — этот коммит реализует пункты 1–2 решения (allow-list, граница можно/нельзя) целиком.
- Фундамент: `cbook/632c4aa-recipe-crud.md` (`CreateRecipeTask`/`UpdateRecipeTask`/`DeleteRecipeTask`, `RecipeRepository`, используемые здесь без изменений их публичного контракта).
- Предыдущий коммит: `cbook/b0a56ff-admin-access.md` (супер-доступ админа, `selectOptions()`).
- Следующий коммит: `cbook/1869e8f-admin-tests.md` (тесты create/edit/delete через панель, включая проверку синхронизации ингредиентов).
