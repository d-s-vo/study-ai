#!/usr/bin/env bash
# role.sh — ролевой маркер сессии (K-role, МОДУЛЬ M5 «контейнерный слой»). Слой РАННЕГО
# внятного отказа ПОВЕРХ физической границы K-priv (не замена!): даже без маркера
# привилегированная операция упадёт сама (в изолированном контейнере нет ssh-клиента/ключа/
# docker-сокета) — helper лишь превращает криптический сбой в понятный отказ ДО обращения к ssh.
#
# При M5=OFF (нет контейнерной модели агента) файл ВЫРОЖДАЕТСЯ в no-op: role_current всегда
# печатает privileged, role_require_privileged — прозрачный возврат 0. Оставить безопасно:
# на обычном одно-хостовом проекте гвард ничего не блокирует.
#
# Источник роли (в порядке приоритета):
#   1) AGENT_ROLE задан явно → доверяем как есть: isolated → isolated; любое иное → privileged.
#      `AGENT_ROLE=isolated` объявляется ТОЛЬКО в compose environment сервиса agent
#      (.devcontainer/docker-compose.yml) — единый источник; хостовая сессия маркер не задаёт.
#   2) AGENT_ROLE не задан → пиненная эвристика-страховка: НЕТ `command -v ssh` И есть /.dockerenv
#      → isolated, иначе privileged. Ложное срабатывание возможно только в сторону isolated
#      (safe-fail: отказ, а не эскалация); для edge-кейса — явный override `AGENT_ROLE=privileged`.
#
# bash 3.2-совместимо. Публичные функции:
#   role_current                    — печатает isolated|privileged
#   role_require_privileged <op> — при isolated: внятный отказ + exit 3; при privileged: no-op

# --- цвет (только для терминала на stderr) ---
if [ -t 2 ]; then
    _MR_RED="$(printf '\033[31m')"; _MR_RST="$(printf '\033[0m')"
else
    _MR_RED=""; _MR_RST=""
fi

# role_current — печатает роль текущего процесса: isolated|privileged.
role_current() {
    if [ -n "${AGENT_ROLE:-}" ]; then
        if [ "$AGENT_ROLE" = "isolated" ]; then
            printf 'isolated\n'
        else
            printf 'privileged\n'
        fi
        return 0
    fi
    # эвристика-страховка (пиненный предикат): нет ssh-клиента И файл /.dockerenv существует.
    if ! command -v ssh >/dev/null 2>&1 && [ -f /.dockerenv ]; then
        printf 'isolated\n'
    else
        printf 'privileged\n'
    fi
}

# role_require_privileged <op> — гвард привилегированной операции. При isolated печатает
# внятный отказ с указанием хостового канала и завершает процесс с кодом 3 (НЕ доходя до
# ssh/докера). При privileged — молча возвращает 0 (на хосте/при M5=OFF гвард прозрачен).
role_require_privileged() {
    _mrp_op="${1:-операция}"
    if [ "$(role_current)" = "isolated" ]; then
        printf '%s%s — привилегированная операция, недоступна из изолированного агента.%s\n' \
            "$_MR_RED" "$_mrp_op" "$_MR_RST" >&2
        printf 'Выполните на ХОСТЕ (привилегированный канал).\n' >&2
        printf 'Ложное срабатывание (хост без docker/ssh)? — задайте AGENT_ROLE=privileged.\n' >&2
        exit 3
    fi
    return 0
}
