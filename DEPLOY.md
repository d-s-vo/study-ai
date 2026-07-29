# DEPLOY — доставка на GitHub обычным git (выполняет человек)

## Что есть что — ДВА разных каталога (не путать)

| Каталог | Что это | git-деплой тут? |
|---|---|---|
| `study-cbook-ai/` | **песочница агента** (тут ИИ пишет код; заперта, пушить нельзя) | ❌ НЕТ. Тут только `deliver.sh` |
| `~/cbook/` | **твоя рабочая копия проекта** (обычный клон, как у любого разработчика) | ✅ ДА. Тут весь merge/push |

Твоя рабочая копия — это НЕ `study-cbook-ai`. Все `merge`/`push` — в `~/cbook`.
Проверка «где я»: `git remote get-url origin` → должно быть `…/nuxt4-ts-project-cbook`
(если `…/study-ai.git` — ты в песочнице, уйди в `~/cbook`).

**Клон один раз** (если ещё нет). Имя папки — **любое** (тут `~/cbook`, но можно `~/my-cbook` и т.д.);
это просто твоя копия проекта в домашней папке, НЕ путать с запертым `study-cbook-ai/cbook`:
```bash
git clone https://github.com/d-s-vo/nuxt4-ts-project-cbook ~/cbook
```

---

## Цикл доставки (feat → develop → main)

### 1. Вынести ветку агента из песочницы на GitHub
Единственная не-git команда — это «дверь» из запертой песочницы (сканит следы ИИ):
```bash
cd /Users/dmitry/server/sites/study-cbook-ai
./scripts/deliver.sh cbook feat/<slug>
```

### 2. Дальше — обычный git в ТВОЕЙ копии
```bash
cd ~/cbook
git fetch origin

# фича → develop
git switch develop
git merge origin/feat/<slug>
git push origin develop

# деплой develop → main (когда готов к релизу)
git switch main
git merge origin/develop
git push origin main

# уборка ветки
git push origin --delete feat/<slug>
```
Затем скажи агенту «готово» — он приберёт worktree в песочнице (`task.sh rm <slug>`).

---

## Правила (чтобы не запутаться снова)
1. **git-деплой — только в `~/cbook`**, никогда в `study-cbook-ai` (там нет `develop`, там песочница).
2. **Всегда `git fetch` перед `merge`.**
3. **Фича → `develop`, никогда напрямую в `main`.**
4. Ветку удаляй сразу после мержа.

---

## (Опционально) полностью без `deliver.sh`
Если хочешь совсем без скриптов — забери ветку агента из песочницы напрямую в свою копию:
```bash
cd ~/cbook
git fetch /Users/dmitry/server/sites/study-cbook-ai/.repos/cbook.git feat/<slug>:feat/<slug>
git push origin feat/<slug>
```
⚠️ Это обходит второй скан `deliver.sh` (первый скан — `commit.sh` при коммите агента — остаётся). Дальше — §2 как обычно.
