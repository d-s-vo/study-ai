#!/usr/bin/env bash
# sync.sh — синхронизация ВХОДЯЩИХ изменений во всём workspace.
#   - git fetch --prune у всех реп из repos.conf;
#   - основные worktree: fast-forward до origin/<base> (ff-only, без «тихого» чинения);
#   - plain-клоны: git pull --ff-only;
#   - по каждой task-ветке: таблица состояния + ПРЕДПИСАНИЕ (rebase / merge / уборка).
#     Сами rebase/merge НЕ выполняются автоматически (конфликты — работа агента задачи).
#   - в конце: обновление ai/state.json и итоговый статус.
#
# GENERIC-КОПИЯ. Вся логика через repos.conf. FRESH_HOURS — параметр. K-priv (fetch по ssh —
# привилегированный) деградирует безопасно при M5=OFF (role.sh → always privileged).
#
# Флаги:
#   --cleanup   выполнить уборку merged-веток (worktree remove + branch -d) — безопасно;
#   --no-fetch  пропустить сетевой fetch (для отладки на локальном состоянии).
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
: "${WS_ROOT:=$(dirname "$SCRIPT_DIR")}"
. "$SCRIPT_DIR/lib/workspace.sh"
. "$SCRIPT_DIR/lib/state.sh"
. "$SCRIPT_DIR/lib/coord.sh"
. "$SCRIPT_DIR/lib/role.sh"

# вычистка протухших сессий присутствия (мёртвый pid / старый heartbeat)
coord_reap

CLEANUP=0
DO_FETCH=1
# Порог «свежести» worktree для уборки (часов). Свежие (< FRESH_HOURS) пропускаем —
# грубая защита ещё живых агентов. Настраивается env FRESH_HOURS (по умолчанию 24).
FRESH_HOURS="${FRESH_HOURS:-24}"
for a in "$@"; do
    case "$a" in
        --cleanup)  CLEANUP=1 ;;
        --no-fetch) DO_FETCH=0 ;;
        -h|--help)  grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) printf '%sНеизвестный флаг: %s%s\n' "$WS_RED" "$a" "$WS_RST" >&2; exit 2 ;;
    esac
done

hr()  { printf '%s\n' "------------------------------------------------------------------------"; }
head_line() { printf '%s== %s ==%s\n' "$WS_BLD" "$*" "$WS_RST"; }

# sync_write_fetch_state <records-tsv> <state-path> — собрать маркер свежести базиса (K-fetch)
# из строк "<имя>\t<base>\t<head>\t<ok>" и атомарно (tmp+mv) записать <state-path>. Вызывается
# ТОЛЬКО под локом sync-fetch. requested_at/by (запрос изолированного агента) очищается —
# fetch обслужил запрос; о висевшем запросе печатается уведомление до перезаписи.
sync_write_fetch_state() {
    _wfs_rec="$1"; _wfs_state="$2"
    _wfs_now="$(coord_now)"
    mkdir -p "$(dirname "$_wfs_state")" 2>/dev/null || true
    if [ -f "$_wfs_state" ]; then
        _wfs_rq="$(jq -r '.requested_at // empty' "$_wfs_state" 2>/dev/null)"
        _wfs_rby="$(jq -r '.requested_by // empty' "$_wfs_state" 2>/dev/null)"
        if [ -n "$_wfs_rq" ]; then
            printf '%s  есть запрос fetch от session=%s (%s) — обслуживаю, очищаю запрос%s\n' \
                "$WS_YEL" "${_wfs_rby:-?}" "$_wfs_rq" "$WS_RST"
        fi
    fi
    _wfs_repos='{}'
    while IFS="$(printf '\t')" read -r rn rb rh rok || [ -n "$rn" ]; do
        [ -n "$rn" ] || continue
        case "$rok" in true|false) : ;; *) rok=false ;; esac
        _wfs_next="$(printf '%s' "$_wfs_repos" | jq \
            --arg n "$rn" --arg b "$rb" --arg h "$rh" --arg at "$_wfs_now" --argjson ok "$rok" \
            '.[$n] = {base:$b, head:$h, fetched_at:$at, ok:$ok}' 2>/dev/null)"
        [ -n "$_wfs_next" ] && _wfs_repos="$_wfs_next"
    done < "$_wfs_rec"
    _wfs_tmp="$_wfs_state.tmp.$$"
    if printf '%s' "$_wfs_repos" | jq --arg u "$_wfs_now" '{updated:$u, repos:.}' > "$_wfs_tmp" 2>/dev/null; then
        mv "$_wfs_tmp" "$_wfs_state" 2>/dev/null || rm -f "$_wfs_tmp"
        printf '%s  маркер свежести базиса обновлён: %s%s\n' "$WS_DIM" "$_wfs_state" "$WS_RST"
    else
        rm -f "$_wfs_tmp"
        printf '%s  не удалось записать маркер свежести (%s)%s\n' "$WS_RED" "$_wfs_state" "$WS_RST" >&2
    fi
}

# ---------------------------------------------------------------------------
# 1. Fetch --prune у всех реп
# ---------------------------------------------------------------------------
head_line "1. fetch --prune"
# K-priv/K-role (M5): fetch клиентских реп по ssh — привилегированный канал (хост). Из
# изолированного агента гвард отсекает шаг fetch ДО ssh (exit 3), read-only части (§2/§3/§4)
# доступны через `sync.sh --no-fetch`. При M5=OFF гвард прозрачен.
FETCH_LOCKED=0
FETCH_TOUCHER=""
FETCH_STATE="$COORD_DIR/fetch-state.json"
FETCH_RECORDS=""
if [ "$DO_FETCH" -eq 1 ]; then
    role_require_privileged "fetch клиентских реп (sync.sh)"
    # Короткий лок, чтобы два параллельных sync не молотили fetch одновременно. Держатель
    # длинный (сетевой fetch всех реп может длиться >300с) → фоновый lock-heartbeat.
    if coord_lock sync-fetch 60; then
        FETCH_LOCKED=1
        coord_lock_toucher sync-fetch & FETCH_TOUCHER=$!
        trap 'kill "$FETCH_TOUCHER" 2>/dev/null; coord_unlock sync-fetch' EXIT INT TERM
    else
        printf '%s  (fetch-лок занят другим sync — продолжаю без него)%s\n' "$WS_DIM" "$WS_RST"
    fi
    FETCH_RECORDS="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/fetchrec.$$")"
    : > "$FETCH_RECORDS"
fi
while IFS= read -r line || [ -n "$line" ]; do
    name="$(ws_name "$line")"; gd="$(ws_gitdir "$line")"; base="$(ws_base "$line")"
    if [ ! -d "$gd" ]; then
        printf '%s  %-18s пропуск: нет каталога %s%s\n' "$WS_YEL" "$name" "$gd" "$WS_RST"
        continue
    fi
    if [ "$DO_FETCH" -eq 1 ]; then
        if git -C "$gd" fetch --prune origin >/dev/null 2>&1; then
            printf '%s  %-18s fetched%s\n' "$WS_GRN" "$name" "$WS_RST"
            _fok=true
        else
            printf '%s  %-18s FETCH FAILED (сеть/доступ?)%s\n' "$WS_RED" "$name" "$WS_RST"
            _fok=false
        fi
        # запись строки маркера только если лок наш (иначе пишет параллельный держатель лока).
        if [ "$FETCH_LOCKED" -eq 1 ]; then
            _fhead="$(git -C "$gd" rev-parse "origin/$base" 2>/dev/null || printf '')"
            printf '%s\t%s\t%s\t%s\n' "$name" "$base" "$_fhead" "$_fok" >> "$FETCH_RECORDS"
        fi
    else
        printf '%s  %-18s (fetch пропущен)%s\n' "$WS_DIM" "$name" "$WS_RST"
    fi
done <<EOF
$(ws_conf_lines)
EOF
# Обновление маркера свежести базиса (K-fetch) — атомарно (tmp+mv) под уже взятым локом.
if [ "$DO_FETCH" -eq 1 ] && [ "$FETCH_LOCKED" -eq 1 ]; then
    sync_write_fetch_state "$FETCH_RECORDS" "$FETCH_STATE"
fi
[ -n "$FETCH_RECORDS" ] && rm -f "$FETCH_RECORDS"
if [ "$FETCH_LOCKED" -eq 1 ]; then
    kill "$FETCH_TOUCHER" 2>/dev/null
    coord_unlock sync-fetch; trap - EXIT INT TERM
fi

# ---------------------------------------------------------------------------
# 2. Основные worktree: fast-forward до origin/<base>
# ---------------------------------------------------------------------------
echo; head_line "2. основные worktree: ff-only до origin/<base>"
while IFS= read -r line || [ -n "$line" ]; do
    name="$(ws_name "$line")"; type="$(ws_type "$line")"
    base="$(ws_base "$line")"; wt="$(ws_mainwt_abs "$line")"; gd="$(ws_gitdir "$line")"
    [ -d "$wt" ] || { printf '%s  %-18s нет worktree%s\n' "$WS_YEL" "$name" "$WS_RST"; continue; }

    # локальная базовая ветка ($base) относительно origin/$base (в bare HEAD != ветка worktree)
    ab="$(ws_ahead_behind "$gd" "$base" "$base")"
    behind="$(printf '%s' "$ab" | awk -F'\t' '{print $1}')"
    ahead="$(printf '%s'  "$ab" | awk -F'\t' '{print $2}')"

    if [ "${ahead:-0}" != "0" ] && [ "${ahead:-0}" != "?" ]; then
        printf '%s  %-18s НАРУШЕНИЕ ДИСЦИПЛИНЫ: %s локальных коммитов в основном worktree.%s\n' \
            "$WS_RED" "$name" "$ahead" "$WS_RST"
        printf '%s    Основной worktree обязан быть чистым слепком origin/%s. ff невозможен — НЕ чиню молча.%s\n' \
            "$WS_RED" "$base" "$WS_RST"
        printf '       Разберите вручную: перенесите коммиты в task-ветку или сбросьте worktree.\n'
        continue
    fi

    if [ "${behind:-0}" = "0" ]; then
        printf '%s  %-18s up-to-date (origin/%s)%s\n' "$WS_GRN" "$name" "$base" "$WS_RST"
        continue
    fi

    if [ "$type" = "plain" ]; then
        if git -C "$wt" pull --ff-only >/dev/null 2>&1; then
            printf '%s  %-18s pull --ff-only (+%s)%s\n' "$WS_GRN" "$name" "$behind" "$WS_RST"
        else
            printf '%s  %-18s pull --ff-only НЕ УДАЛСЯ (грязное дерево/расхождение)%s\n' "$WS_RED" "$name" "$WS_RST"
        fi
    else
        if git -C "$wt" merge --ff-only "origin/$base" >/dev/null 2>&1; then
            printf '%s  %-18s ff-only до origin/%s (+%s)%s\n' "$WS_GRN" "$name" "$base" "$behind" "$WS_RST"
        else
            printf '%s  %-18s ff-only НЕ УДАЛСЯ: грязное дерево мешает обновлению.%s\n' "$WS_RED" "$name" "$WS_RST"
            printf '       Проверьте: git -C %s status  (закоммитьте/уберите изменения и повторите sync).\n' "$wt"
        fi
    fi
done <<EOF
$(ws_conf_lines)
EOF

# 2b. Доп. основные worktree того же bare-репо (поле 6 repos.conf, напр. prod-ветка релиза):
#     отдельный проход — ff-only как основному (не зависит от 'continue' основной ветки выше).
while IFS= read -r line || [ -n "$line" ]; do
    gd="$(ws_gitdir "$line")"
    [ -d "$gd" ] || continue
    while IFS="$(printf '\t')" read -r ename ebr || [ -n "$ename" ]; do
        [ -n "$ename" ] || continue
        ewt="$WS_ROOT/$ename"
        [ -d "$ewt" ] || { printf '%s  %-18s нет worktree%s\n' "$WS_YEL" "$ename" "$WS_RST"; continue; }
        eab="$(ws_ahead_behind "$gd" "$ebr" "$ebr")"
        ebehind="$(printf '%s' "$eab" | awk -F'\t' '{print $1}')"
        eahead="$(printf '%s'  "$eab" | awk -F'\t' '{print $2}')"
        if [ "${eahead:-0}" != "0" ] && [ "${eahead:-0}" != "?" ]; then
            printf '%s  %-18s НАРУШЕНИЕ ДИСЦИПЛИНЫ: %s локальных коммитов в доп. worktree (ветка %s).%s\n' \
                "$WS_RED" "$ename" "$eahead" "$ebr" "$WS_RST"
        elif [ "${ebehind:-0}" = "0" ]; then
            printf '%s  %-18s up-to-date (origin/%s)%s\n' "$WS_GRN" "$ename" "$ebr" "$WS_RST"
        elif git -C "$ewt" merge --ff-only "origin/$ebr" >/dev/null 2>&1; then
            printf '%s  %-18s ff-only до origin/%s (+%s)%s\n' "$WS_GRN" "$ename" "$ebr" "$ebehind" "$WS_RST"
        else
            printf '%s  %-18s ff-only НЕ УДАЛСЯ: грязное дерево мешает обновлению.%s\n' "$WS_RED" "$ename" "$WS_RST"
        fi
    done <<EOF2
$(ws_extra_worktrees "$line")
EOF2
done <<EOF
$(ws_conf_lines)
EOF

# ---------------------------------------------------------------------------
# 3. Task-ветки: таблица + предписания
# ---------------------------------------------------------------------------
echo; head_line "3. task-ветки: состояние и предписания"
TASK_TOTAL=0
CLEANED=0
FMT='  %-34s %-16s %-10s %-11s %-8s\n'
# shellcheck disable=SC2059
printf "$FMT" "ВЕТКА" "FEAT" "behind/ahead" "delivered" "merged"
hr

PRESCRIPTIONS="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/presc.$$")"
: > "$PRESCRIPTIONS"

while IFS= read -r line || [ -n "$line" ]; do
    [ "$(ws_type "$line")" = "bare" ] || continue
    name="$(ws_name "$line")"; base="$(ws_base "$line")"; gd="$(ws_gitdir "$line")"

    while IFS="$(printf '\t')" read -r twt tbr || [ -n "$twt" ]; do
        [ -n "$twt" ] || continue
        TASK_TOTAL=$((TASK_TOTAL+1))
        slug="$(ws_slug "$twt")"
        ab="$(ws_ahead_behind "$gd" "$tbr" "$base")"
        behind="$(printf '%s' "$ab" | awk -F'\t' '{print $1}')"
        ahead="$(printf '%s'  "$ab" | awk -F'\t' '{print $2}')"
        ws_delivered "$gd" "$tbr"; deliv=$?
        ws_merged "$gd" "$tbr" "$base"; mrg=$?
        feat="$(ws_state_feat "$name" "$slug")"; [ -n "$feat" ] || feat="-"

        d_txt="no"; [ "$deliv" -eq 0 ] && d_txt="yes"
        m_txt="no"; [ "$mrg" -eq 0 ] && m_txt="yes"
        # shellcheck disable=SC2059
        printf "$FMT" "$tbr" "$feat" "$behind/$ahead" "$d_txt" "$m_txt"

        # --- предписание ---
        if [ "$mrg" -eq 0 ]; then
            printf '  [%s] MERGED -> убрать: scripts/task.sh rm %s (ветка %s будет удалена)\n' \
                "$slug" "$slug" "$tbr" >> "$PRESCRIPTIONS"
            if [ "$CLEANUP" -eq 1 ]; then
                # Гварды: не трогаем залоченные, грязные и «свежие» worktree — с явной причиной.
                skip_reason=""
                if ws_worktree_locked "$gd" "$twt"; then
                    skip_reason="locked (агент жив)"
                elif [ -n "$(git -C "$twt" status --porcelain 2>/dev/null)" ]; then
                    skip_reason="грязное дерево (незакоммиченные изменения)"
                else
                    wt_mtime="$(stat -f %m "$twt" 2>/dev/null || stat -c %Y "$twt" 2>/dev/null || echo 0)"
                    now_ts="$(date +%s)"
                    if [ $(( now_ts - wt_mtime )) -lt $(( FRESH_HOURS * 3600 )) ]; then
                        skip_reason="свежий (<${FRESH_HOURS}h — возможно живой агент)"
                    fi
                fi
                if [ -n "$skip_reason" ]; then
                    printf '  [%s] ПРОПУСК уборки: %s\n' "$slug" "$skip_reason" >> "$PRESCRIPTIONS"
                elif git -C "$gd" worktree remove "$twt" >/dev/null 2>&1 \
                     && git -C "$gd" branch -d "$tbr" >/dev/null 2>&1; then
                    printf '  [%s] УБРАНО: worktree + ветка %s удалены.\n' "$slug" "$tbr" >> "$PRESCRIPTIONS"
                    CLEANED=$((CLEANED+1))
                    # если есть бронь этого slug — статус merged + перенос в архив (окружение НЕ дропаем).
                    _bk="$COORD_BOOKINGS/$slug.json"
                    if [ -f "$_bk" ]; then
                        if coord_lock booking 30; then
                            _bktmp="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/bk.$$")"
                            if jq --arg u "$(coord_now)" '.status="merged" | .updated=$u' "$_bk" > "$_bktmp" 2>/dev/null; then
                                mv "$_bktmp" "$_bk"
                            else
                                rm -f "$_bktmp"
                            fi
                            mv "$_bk" "$COORD_ARCHIVE/$slug.json" 2>/dev/null
                            coord_unlock booking
                            printf '  [%s] БРОНЬ: merged -> archive/. Тирдаун окружения (НЕ авто): снеси эфемерную task-БД/стенд вручную, если поднимал.\n' \
                                "$slug" >> "$PRESCRIPTIONS"
                        fi
                    fi
                else
                    printf '  [%s] уборка не удалась (см. git worktree remove --force).\n' \
                        "$slug" >> "$PRESCRIPTIONS"
                fi
            fi
        elif [ "${behind:-0}" != "0" ] && [ "${behind:-0}" != "?" ]; then
            if [ "$deliv" -eq 0 ]; then
                printf '  [%s] delivered+behind %s -> merge: git -C %s merge origin/%s\n' \
                    "$slug" "$behind" "$twt" "$base" >> "$PRESCRIPTIONS"
            else
                printf '  [%s] not-delivered+behind %s -> rebase: git -C %s rebase origin/%s\n' \
                    "$slug" "$behind" "$twt" "$base" >> "$PRESCRIPTIONS"
            fi
        fi
    done <<EOF
$(ws_task_worktrees "$line")
EOF
done <<EOF
$(ws_conf_lines)
EOF

hr
if [ "$TASK_TOTAL" -eq 0 ]; then
    printf '  (task-веток нет)\n'
fi
if [ -s "$PRESCRIPTIONS" ]; then
    echo; head_line "предписания (выполняет агент в контексте задачи; авто-rebase/merge не делаем)"
    cat "$PRESCRIPTIONS"
fi
rm -f "$PRESCRIPTIONS"

# ---------------------------------------------------------------------------
# 4. Обновление состояния + итог
# ---------------------------------------------------------------------------
echo; head_line "4. обновление состояния"
ws_state_migrate
if ws_state_write; then
    printf '%s  state.json обновлён: %s%s\n' "$WS_GRN" "$(ws_state_target)" "$WS_RST"
fi

echo
if [ "$CLEANUP" -eq 1 ]; then
    printf '%sИтог: task-веток %s, убрано merged %s.%s\n' "$WS_BLD" "$TASK_TOTAL" "$CLEANED" "$WS_RST"
else
    printf '%sИтог: task-веток %s. Уборка merged: sync.sh --cleanup.%s\n' "$WS_BLD" "$TASK_TOTAL" "$WS_RST"
fi
