#!/usr/bin/env bash
# scan.sh — общий сканер стоп-словаря для охранной обвязки.
# POSIX/bash-3.2 совместимо: без mapfile, без ассоциативных массивов, grep -E (без -P).
# Источится (source) хуками и обёртками. Все функции печатают человекочитаемые
# нарушения в stdout и возвращают код 0 (чисто) / 1 (есть нарушения).  ⇐ ИНВАРИАНТ №7.
#
# Ожидает (или выставляет по умолчанию) переменные:
#   STOPWORDS_FILE  — путь к stopwords.txt
#   ALLOW_FILE      — путь к allowpatterns.txt
#
# Публичные функции:
#   scan_text_file <file>   — скан содержимого файла построчно
#   scan_stream             — скан текста со stdin построчно
#   scan_string <string>    — скан одной строки/команды
#   scan_is_allowed <line>  — 0 если строку разрешает allowpatterns

# --- определение путей относительно самого себя ---
_scan_src="${BASH_SOURCE[0]:-$0}"
_scan_lib_dir="$(cd "$(dirname "$_scan_src")" && pwd)"
SCAN_GITHOOKS_DIR="$(dirname "$_scan_lib_dir")"
: "${STOPWORDS_FILE:=$SCAN_GITHOOKS_DIR/stopwords.txt}"
: "${ALLOW_FILE:=$SCAN_GITHOOKS_DIR/allowpatterns.txt}"

# Кейс-инсенситивный ASCII-скан; для кириллицы в stopwords продублированы
# капитализированные варианты, т.к. BSD grep -i не всегда фолдит Unicode.

# scan_is_allowed <line-content>
# Возвращает 0, если строку разрешает любой паттерн из ALLOW_FILE.
scan_is_allowed() {
    _sia_content="$1"
    [ -f "$ALLOW_FILE" ] || return 1
    [ -s "$ALLOW_FILE" ] || return 1
    while IFS= read -r _sia_pat || [ -n "$_sia_pat" ]; do
        case "$_sia_pat" in
            ''|'#'*) continue ;;
        esac
        if printf '%s\n' "$_sia_content" | grep -qiE -- "$_sia_pat" 2>/dev/null; then
            return 0
        fi
    done < "$ALLOW_FILE"
    return 1
}

# scan_text_file <file>
# Печатает нарушения, возвращает 1 если есть хоть одно.
scan_text_file() {
    _stf_src="$1"
    [ -f "$_stf_src" ] || return 0
    _stf_hits="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/scan_hits.$$")"
    _stf_viol=0
    while IFS= read -r _stf_pat || [ -n "$_stf_pat" ]; do
        case "$_stf_pat" in
            ''|'#'*) continue ;;
        esac
        grep -inE -- "$_stf_pat" "$_stf_src" > "$_stf_hits" 2>/dev/null || continue
        while IFS= read -r _stf_hit || [ -n "$_stf_hit" ]; do
            _stf_lineno="${_stf_hit%%:*}"
            _stf_content="${_stf_hit#*:}"
            if scan_is_allowed "$_stf_content"; then
                continue
            fi
            printf '    [стоп-слово] паттерн="%s"  строка %s: %s\n' \
                "$_stf_pat" "$_stf_lineno" "$_stf_content"
            _stf_viol=1
        done < "$_stf_hits"
    done < "$STOPWORDS_FILE"
    rm -f "$_stf_hits" 2>/dev/null
    return $_stf_viol
}

# scan_stream — читает текст со stdin, сканирует, печатает нарушения.
scan_stream() {
    _ss_tmp="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/scan_stream.$$")"
    cat > "$_ss_tmp"
    scan_text_file "$_ss_tmp"
    _ss_rc=$?
    rm -f "$_ss_tmp" 2>/dev/null
    return $_ss_rc
}

# scan_string <string> — скан одной строки/команды, печатает нарушения.
scan_string() {
    printf '%s\n' "$1" | scan_stream
}
