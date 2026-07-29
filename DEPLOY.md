# DEPLOY — доставка на GitHub обычным git (выполняет человек)

## Два каталога — где что (НЕ путать)

| Каталог | Что это | git-деплой тут? |
|---|---|---|
| `/Users/dmitry/server/sites/study-cbook-ai/` | **песочница агента** (тут ИИ пишет код; заперта — `pushurl=DISABLED`) | ❌ НЕТ. Отсюда только `deliver.sh` |
| `/Users/dmitry/server/sites/study/` | **твоя рабочая копия проекта** (обычный клон, origin = nuxt4-ts-project-cbook) | ✅ ДА. Тут весь `merge`/`push` |

Всё интеграция/деплой — **в `/study`**. Новый клон НЕ нужен. Проверка «где я»:
`git remote get-url origin` → `…/nuxt4-ts-project-cbook` (в песочнице было бы `…/study-ai.git`).

---

## Цикл: feat → develop → main

### 1. Вынести ветку агента из песочницы на GitHub
Единственная не-git команда (шлюз из запертой песочницы, сканит следы ИИ):
```bash
cd /Users/dmitry/server/sites/study-cbook-ai
./scripts/deliver.sh cbook feat/<slug>
```

### 2. Дальше — обычный git в `/study`
```bash
cd /Users/dmitry/server/sites/study
git fetch origin

# фича → develop
git switch develop
git reset --hard origin/develop          # выровнять develop с origin (клон чистый, develop — интеграционная)
git merge origin/feat/<slug>
git push origin develop

# деплой develop → main (когда готов)
git switch main
git reset --hard origin/main
git merge origin/develop
git push origin main

# уборка ветки
git push origin --delete feat/<slug>
```
После — скажи агенту «готово», он снимет worktree в песочнице (`task.sh rm <slug>`).

> ⚠️ После merge рабочее дерево `/study` отражает состояние ветки (по мере миграции — Laravel).
> Дерево держи чистым (коммить/убирай локальные правки до merge), иначе `reset --hard` их снесёт.

---

## Правила (чтобы не запутаться)
1. **git-деплой — только в `/study`**, никогда в `study-cbook-ai` (там песочница с замком → `push` упрётся в `DISABLED_use_deliver_sh`).
2. **Всегда `git fetch` перед merge.**
3. **Фича → `develop`, никогда напрямую в `main`.**
4. Ветку удаляй сразу после мержа.

---

## (Опционально) без `deliver.sh`
Забрать ветку агента прямо из песочницы в `/study` и запушить обычным git:
```bash
cd /Users/dmitry/server/sites/study
git fetch /Users/dmitry/server/sites/study-cbook-ai/.repos/cbook.git feat/<slug>:feat/<slug>
git push origin feat/<slug>
```
⚠️ Обходит второй скан `deliver.sh` (первый — `commit.sh` при коммите агента — остаётся).
