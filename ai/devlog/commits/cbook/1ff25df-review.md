---
repo: cbook
authored_hash: 1ff25dfe1089ac52b14919f1ae712e8f1c66e78c
patch_id: 2fed2fa22856b95ecd05d0b2769e6f705f2f3101
feat: FEAT-005
branch: feat/infra-toolchain
reviewer_model: Opus 4.8
review_date: 2026-07-31
verdict: PASS
blockers_total: 0
blockers_open: 0
resolved_by: []
---

# cbook@1ff25df — REVIEW — ci: прогонять линт и проверку типов фронтенда

**Verdict:** PASS
**Blocking findings:**
- нет
**Non-blocking notes:**
- Разбор «почему» (ADR-009) для этого коммита автором пока не написан — обязанность автора/оркестратора
  до merge (гейт покрытия §9 считает review-файлы; разбор — параллельная обязанность Шага 12 п.2.5)
  (severity: minor, процессная, вне дифа).
- Спека FEAT-005 (границы) относила добавление `pnpm lint`/`typecheck` в CI к FEAT-008 «поверх уже
  смерженной базы»; здесь шаги добавлены превентивно в ветке 005. Благодаря `--if-present` шаги —
  гарантированный no-op до появления скриптов (доказано, см. Evidence), красного CI не дают; мотив
  (энфорс со стороны CI к моменту merge ветки гигиены) санкционирован оркестратором (severity: nit).
**Evidence:**
- **Узкий скоуп** (по прецеденту cc3df94); `trivial-scope` по объёму (один файл, +4 строки), проверен
  по существу.
- `git show 1ff25df`: единственное изменение — в job `frontend` между шагами Install и Build добавлены
  `- name: Lint / run: pnpm run --if-present lint` и `- name: Typecheck / run: pnpm run --if-present
  typecheck` (ci.yml:111-114). Отступы совпадают с соседними шагами, YAML-структура корректна; порядок
  верен (после `pnpm install --frozen-lockfile`, до `pnpm build`).
- **Семантика `--if-present` доказана живым прогоном на pnpm 10.30.3** (тот же мажор, что резолвит CI
  `version: 10`): в `package.json` секция `scripts` содержит только `build`/`dev` (ни `lint`, ни
  `typecheck` нет) → `pnpm run --if-present lint` → **exit 0**, `pnpm run --if-present typecheck` →
  **exit 0**; контроль без флага: `pnpm run lint` → `ERR_PNPM_NO_SCRIPT`, **exit 1**. То есть до
  merge ветки гигиены шаги — no-op, после — станут реальными гейтами (fail скрипта = fail шага:
  `--if-present` глушит только отсутствие скрипта, не его ошибки).
- Job `tests` не тронут (его build-шаг без lint/typecheck — осознанно: гейт фронта живёт в `frontend`).
- **Стоп-словарь по дифу** (`githooks/stopwords.txt`, grep -iE): чисто. Сообщение
  `ci: прогонять линт и проверку типов фронтенда` — conventional (`ci` ∈ допустимых типов), «от лица
  человека», без следов системы.
**Suggested next:** none (процессная нота: дописать разбор ADR-009 автором до merge)

## Рубрика (сокращённая, trivial-scope)

☑ Атомарность (один смысл: CI-энфорс фронт-гейтов) · ☑ Отсутствие изменения поведения ДО появления
скриптов (no-op доказан) и корректное поведение ПОСЛЕ (fail скрипта валит шаг) · ☑ Чистота
(стоп-словарь чист, conventional message) · ☑ Регрессий нет (прочие job'ы/шаги не тронуты)

## Журнал закрытия находок

- Находок нет. Процессная нота (нет разбора ADR-009) — к автору/оркестратору до merge.

## Связи

- Ревью соседних коммитов ветки: `74fe7ab-review.md` (итог цепочки), `cc3df94-review.md`.
- Фича: `../../features/FEAT-005-infra-toolchain/impl.md` · `spec.md` (границы CI-шагов — FEAT-008).
- Гайд ревью: [`../../guides/commit-review.md`](../../guides/commit-review.md).
