#!/usr/bin/env bash

action_status() {
    preflight_common status
    if state_is_installed; then
        local current
        current="$(readlink -f "$CURRENT_LINK")"
        ui_message "已检测到部署。\n\n当前版本：$current\n配置目录：$CONFIG_DIR\n模型目录：$MODEL_DIR\n服务：$SERVICE_NAME"
    else
        ui_message "尚未检测到 llama.cpp Server 部署。"
    fi
}
