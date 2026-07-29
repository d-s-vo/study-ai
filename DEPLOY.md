# DEPLOY — доставка и деплой стандартным git (выполняет человек)

Интеграция и деплой клиентского репозитория `cbook`
(`github.com/d-s-vo/nuxt4-ts-project-cbook`) **обычными командами git** — без `gh` CLI и без
ручной возни с PR в вебе.

> **Принцип.** Агент делает код ВНУТРИ workspace. Ты — всё, что уходит на GitHub.
> Направление всегда: **фича → `develop` → `main`**. В `main` напрямую фичи не мержим.
> Единственный не-«голый git» шаг — вынос ветки из workspace (см. §1): push оттуда намеренно
> заблокирован охранной обвязкой (скан следов ИИ), и `deliver.sh` — санкционированный гейт.

---

## ⚠️ ДВА РАЗНЫХ РЕПОЗИТОРИЯ — НЕ ПЕРЕПУТАЙ (частая ошибка)

| Каталог | Что это | Ветки | origin | Для чего |
|---|---|---|---|---|
| `study-cbook-ai/` | **репо ЗНАНИЙ** (workspace) | только `main` | `study-ai.git` | контекст/скрипты; **git-деплой тут НЕ делать** |
| `~/cbook-int/` (клон клиента) | **клиентский проект** | `main`, `develop`, `feat/*` | `nuxt4-ts-project-cbook` | сюда §2–§4 (merge/push) |

Если `git switch develop` даёт `fatal: invalid reference: develop` — ты **в `study-cbook-ai`** (там нет
`develop`). Перейди в клиентский клон: `cd ~/cbook-int`. Быстрая проверка «где я»:
```bash
git remote get-url origin    # клиентский клон → …/nuxt4-ts-project-cbook ; если …/study-ai.git — ты не там
```

---

## 0. Предпосылки (один раз)

- Работай из **обычного терминала** (не через `!` в сессии Claude).
- Заведи **ОДИН** рабочий клон клиентского репо для интеграции (не плоди клоны — параллельные
  клоны дрейфуют и рождают лишние мерж-петли):
  ```bash
  git clone https://github.com/d-s-vo/nuxt4-ts-project-cbook ~/cbook-int
  cd ~/cbook-int
  git remote get-url origin      # ДОЛЖНО быть …/nuxt4-ts-project-cbook (проверка, что не в репо знаний)
  ```
  **Все команды §2–§4 выполняются ТОЛЬКО из этого клона** (`cd ~/cbook-int`), НЕ из `study-cbook-ai`.

---

## 1. Вынести ветку фичи на GitHub

Ветка `feat/<slug>` создана агентом в запертом workspace. Выносим её на origin через гейт чистоты:
```bash
cd /Users/dmitry/server/sites/study-cbook-ai
./scripts/deliver.sh cbook feat/<slug>
```
Спросит повторить имя ветки → запушит на GitHub, прогнав скан следов ИИ.

> Почему не «голый git»: прямой push из workspace заблокирован рельсами (`pushurl=DISABLED` +
> pre-push хук). `deliver.sh` — единственный санкционированный путь, и он делает скан.
> *(Полностью без deliver.sh — см. «Альтернатива» внизу; но она обходит скан чистоты.)*

---

## 2. Влить фичу в `develop` — стандартный git

Из интеграционного клона (⚠️ **ВСЕГДА `fetch` первым** — иначе расхождения):
```bash
cd ~/cbook-int
git fetch origin
git switch develop
git merge --ff-only origin/develop       # подтянуть develop к origin
git merge origin/feat/<slug>             # влить фичу
git push origin develop
```

---

## 3. Деплой `develop` → `main` — стандартный git

Когда `develop` готов к релизу:
```bash
git fetch origin
git switch main
git merge --ff-only origin/main
git merge origin/develop
git push origin main
```
Это и есть деплой. Между релизами `develop→main` больше не трогаем.

---

## 4. Удалить ветку фичи — стандартный git

```bash
git push origin --delete feat/<slug>
```
Затем скажи агенту «готово» — он приберёт локально (`sync.sh --cleanup` → `task.sh rm <slug>`).

---

## Проверка состояния (в любой момент)

```bash
git fetch origin --prune
git branch -r
git log --oneline --graph --decorate -8 origin/main origin/develop
```

---

## ⚠️ Правила (чтобы не было петель, как в прошлый раз)

1. **ВСЕГДА `git fetch` перед merge.** Используй ОДИН интеграционный клон; не плоди клоны
   (расхождение = лишние мерж-коммиты — ровно то, что уже случалось).
2. **Фича → `develop`, никогда напрямую в `main`.**
3. **`deliver.sh` / push / merge / delete — только человек.** Агенту это запрещено рельсами.
4. **Ветку удаляй сразу после мержа** (после `main`, либо после `develop`, если больше не нужна).
5. `--ff-only` при подтягивании `develop`/`main` ловит случайные петли: если ругается —
   клон разошёлся с origin, выровняй его (`git reset --hard origin/<branch>` в чистом клоне) и повтори.
6. **Коммиты и сообщения — чистые** (без «claude»/следов). Через `deliver.sh` скан это гарантирует;
   в обход — не ходить.

---

## Альтернатива: полностью «голый git» (без `deliver.sh`) — на твою ответственность

Если хочешь вынести ветку тоже обычным git — забери её из workspace-bare напрямую в свой клон и
запушь:
```bash
cd ~/cbook-int
git fetch /Users/dmitry/server/sites/study-cbook-ai/.repos/cbook.git feat/<slug>:feat/<slug>
git push origin feat/<slug>
```
⚠️ **Это обходит скан следов ИИ** (`deliver.sh` его делает, обычный push из твоего клона — нет).
Применяй, только если уверен в чистоте ветки. Дальше — §2–§4 как обычно.
