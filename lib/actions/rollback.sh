#!/usr/bin/env bash

action_rollback() {
    preflight_common rollback
    if ! state_is_installed; then
        die "没有发现现有部署"
    fi

    local previous
    previous="$(state_previous_release || true)"
    [[ -n "$previous" ]] || die "没有可回滚的旧版本"
    ui_message "将把 $CURRENT_LINK 切换到：\n$previous\n\n随后重启服务并执行健康检查。"
    log_info "回滚执行逻辑尚未启用，本次未修改系统"
}
