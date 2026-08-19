#!/usr/bin/env bash

die() {
    printf '错误：%s\n' "$*" >&2
    exit 1
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

is_root() {
    [[ "${EUID:-$(id -u)}" -eq 0 ]]
}

join_by() {
    local separator="$1"
    shift
    local first=1 item
    for item in "$@"; do
        if ((first)); then
            first=0
        else
            printf '%s' "$separator"
        fi
        printf '%s' "$item"
    done
}

run_cmd() {
    if [[ "${DRY_RUN:-0}" == 1 ]]; then
        printf '[dry-run]'
        printf ' %q' "$@"
        printf '\n'
        return 0
    fi
    "$@"
}
