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

> 📍 **Комментарий `# на ветке: X` показывает, на какой ветке ты ДОЛЖЕН быть в момент команды.**
> `reset --hard` бьёт по ТЕКУЩЕЙ ветке — если ошибёшься веткой, снесёшь не ту. Перед каждым
> `reset --hard` проверяй `git branch --show-current`.

```bash
cd /Users/dmitry/server/sites/study     # твой клон проекта, ВНЕ песочницы
git status                               # на ветке: любая — дерево должно быть чистым (иначе reset --hard снесёт)
git fetch origin                         # на ветке: любая — обновить ссылки на origin

# --- фича → develop ---
git switch develop                       # → теперь на ветке: develop
git branch --show-current                # проверь: develop (перед reset --hard!)
git reset --hard origin/develop          # на ветке: develop — выровнять с origin
git merge origin/feat/<slug>             # на ветке: develop — влить фичу
git push origin develop                  # на ветке: develop — запушить

# --- деплой develop → main (когда готов; можно пропустить, если прод не нужен) ---
git switch main                          # → теперь на ветке: main
git branch --show-current                # проверь: main (перед reset --hard!)
git reset --hard origin/main             # на ветке: main — выровнять с origin
git merge origin/develop -m 'merge develop in master'    # на ветке: main — влить develop
git push origin main                     # на ветке: main — прод-деплой

# --- уборка ветки на GitHub ---
git push origin --delete feat/<slug>     # на ветке: любая — удалить фичу с origin
git switch develop                       # → вернуться на рабочую develop
```
После — скажи агенту «готово». Уборку песочницы (worktree `task.sh rm <slug>`, снятие брони)
делает **агент**, не ты — тебе в песочнице руками ничего чистить не надо.

> ⚠️ После merge рабочее дерево `/study` отражает состояние ветки (по мере миграции — Laravel).
> Дерево держи чистым (коммить/убирай локальные правки до merge), иначе `reset --hard` их снесёт.

---

## Грабли, на которые уже наступали (читай перед деплоем)

1. **«no such file or directory» на `./scripts/...` или `.repos/...`** — ты в НЕ том каталоге.
   Эти пути живут ТОЛЬКО в корне песочницы `study-cbook-ai/`, их нельзя звать ни из `/study`, ни из
   worktree задачи. Каждый блок команд начинается со своего `cd` — выполняй его. Проверка «где я»:
   `pwd`.
2. **Шелл «застрял» в удалённой папке worktree** (`…/tasks/<slug>/`). После того как агент выполнил
   `task.sh rm <slug>`, этой папки БОЛЬШЕ НЕТ — если твой шелл стоял внутри, любая команда падает с
   «no such file or directory». Лечение: `cd /Users/dmitry/server/sites/study-cbook-ai` (или в `/study`).
3. **`reset --hard` не на той ветке = снёс не ту ветку.** `git reset --hard origin/main`, запущенный
   пока ты на `develop`, перепишет ЛОКАЛЬНЫЙ `develop` на `main`. Всегда сперва `git switch <ветка>`,
   затем `git branch --show-current` для проверки, и только потом `reset --hard`.
4. **Два репозитория — два origin, не смешивай:**
   - клиентский код: `/study`, origin `…/nuxt4-ts-project-cbook` — сюда `merge`/`push` (этот файл);
   - база знаний агента: `study-cbook-ai`, origin `…/study-ai.git` — публикуется ОТДЕЛЬНО командой
     `./scripts/ai-push.sh` из песочницы. Это НЕ «деплой проекта», это публикация заметок агента.
5. **Уборку песочницы делает агент, не ты.** `task.sh rm`, снятие брони `coord unbook` — это его зона
   в песочнице. Твоя часть заканчивается на `git push` в `/study` + «готово» агенту.

---

## Правила (чтобы не запутаться)
1. **git-деплой — только в `/study`**, никогда в `study-cbook-ai` (там песочница с замком → `push` упрётся в `DISABLED_use_deliver_sh`).
2. **Всегда `git fetch` перед merge.**
3. **Фича → `develop`, никогда напрямую в `main`.**
4. Ветку удаляй сразу после мержа.
5. **Перед `reset --hard`** — проверь ветку (`git branch --show-current`) и чистоту дерева (`git status`).

---

## (Опционально) без `deliver.sh`
Забрать ветку агента прямо из песочницы в `/study` и запушить обычным git:
```bash
cd /Users/dmitry/server/sites/study
git fetch /Users/dmitry/server/sites/study-cbook-ai/.repos/cbook.git feat/<slug>:feat/<slug>
git push origin feat/<slug>
```
⚠️ Обходит второй скан `deliver.sh` (первый — `commit.sh` при коммите агента — остаётся).
