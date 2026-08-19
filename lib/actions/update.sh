#!/usr/bin/env bash

action_update() {
    preflight_common update
    if ! state_is_installed; then
        die "没有发现现有部署，请先执行安装"
    fi

    local new_ref
    new_ref="$(ui_input "请输入新的 llama.cpp tag、分支或 commit" "$SOURCE_REF")"
    ui_message "更新框架将执行：\n\n1. 在独立 release 目录编译 $new_ref\n2. 启动临时健康检查\n3. 原子切换 current 软链接\n4. 重启 systemd 服务\n5. 失败时自动恢复原链接"
    log_info "更新执行逻辑尚未启用，本次未修改系统"
}
