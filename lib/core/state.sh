#!/usr/bin/env bash

state_is_installed() {
    [[ -f "$STATE_FILE" && -L "$CURRENT_LINK" ]]
}

state_load() {
    [[ -f "$STATE_FILE" ]] || return 1
    # 状态文件由本工具生成；实现阶段仍需对允许的键进行白名单解析。
    # shellcheck disable=SC1090
    source "$STATE_FILE"
}

state_previous_release() {
    [[ -L "$CURRENT_LINK" ]] || return 1
    local current
    current="$(readlink -f "$CURRENT_LINK")"
    find "$RELEASES_DIR" -mindepth 1 -maxdepth 1 -type d ! -path "$current" \
        -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk 'NR == 1 { print $2 }'
}
