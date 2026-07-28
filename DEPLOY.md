# DEPLOY — терминальный чеклист (выполняет человек)

Пошаговая доставка и деплой клиентского репозитория `cbook`
(`github.com/d-s-vo/nuxt4-ts-project-cbook`) через workspace.

> **Принцип.** Агент делает всё ВНУТРИ workspace (код, `commit.sh`) и наружу НЕ пушит.
> Всё, что уходит на GitHub — **только ты, в обычном терминале** (не через `!` в сессии).
> Направление всегда: **фича → `develop` → `main`**. В `main` напрямую фичи не мержим.

---

## 0. Предпосылки (один раз)

- Запускать из **обычного терминала** (не из чата Claude) и из корня workspace:
  ```bash
  cd /Users/dmitry/server/sites/study-cbook-ai
  ```
- Для терминальных PR — GitHub CLI (иначе используй веб-UI, см. fallback):
  ```bash
  brew install gh          # если не установлен
  gh auth login            # авторизация в GitHub
  ```

Переменная для удобства (репозиторий клиента):
```bash
REPO=d-s-vo/nuxt4-ts-project-cbook
```

---

## 1. Доставка фичи на GitHub

Выполняется ПОСЛЕ того, как агент закоммитил работу в ветку `feat/<slug>`
(агент сообщит имя ветки). Пуш ветки:

```bash
cd /Users/dmitry/server/sites/study-cbook-ai
./scripts/deliver.sh cbook feat/<slug>
```

`deliver.sh` просканирует исходящие коммиты (сообщения/дифф/автор), попросит
**повторно ввести имя ветки** для подтверждения и запушит `feat/<slug>` на GitHub.

---

## 2. PR фичи в `develop` и merge

**Терминал (gh):**
```bash
gh pr create  --repo $REPO --base develop --head feat/<slug> --fill
gh pr merge   --repo $REPO feat/<slug> --merge --delete-branch
```
(`--delete-branch` сразу удаляет ветку после мержа.)

**UI-fallback:** открой PR `base: develop` ← `compare: feat/<slug>` → **Merge** → **Delete branch**.

---

## 3. Деплой: `develop` → `main`

Когда `develop` готов к релизу (набралось нужное):

**Терминал (gh):**
```bash
gh pr create --repo $REPO --base main --head develop --title "Release" --body "Deploy develop -> main"
gh pr merge  --repo $REPO develop --merge
```

**UI-fallback:** PR `base: main` ← `compare: develop` → **Merge**.

> Это **единственный** `develop→main` мерж на релиз. Между релизами main не трогаем.

---

## 4. Сообщи агенту

После мержа скажи в чате «готово» — агент приберёт локально:
`./scripts/sync.sh --cleanup` → `./scripts/task.sh rm <slug>`.

---

## Проверка состояния (в любой момент)

```bash
cd /Users/dmitry/server/sites/study-cbook-ai
git -C .repos/cbook.git fetch origin --prune
git -C .repos/cbook.git ls-remote --heads origin     # какие ветки на GitHub
git -C .repos/cbook.git log --oneline --graph --decorate -6 origin/main origin/develop
```

---

## ⚠️ Правила (чтобы не было «плясок»)

1. **Один канал:** доставка/PR/merge — только через этот чеклист. Личный клон
   `/study` для git-операций **не трогать** (параллельный клон дрейфует → петли в истории).
2. **Фича — в `develop`, никогда напрямую в `main`.**
3. **`deliver.sh` / push / merge / удаление веток — только человек**, в обычном терминале.
   Агенту эти операции запрещены рельсами физически.
4. **Ветку удаляй сразу после мержа** (`--delete-branch` или кнопка Delete).
5. **Коммиты и сообщения — чистые** (без «claude»/следов). Через `commit.sh`/`deliver.sh`
   это обеспечивается автоматически; в обход рельсов — не ходить.
