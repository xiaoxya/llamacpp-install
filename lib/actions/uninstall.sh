#!/usr/bin/env bash

action_uninstall() {
    preflight_common uninstall
    ui_message "卸载框架默认删除：\n\n- systemd unit\n- $CONFIG_DIR\n- $INSTALL_ROOT\n- $SERVICE_USER 系统用户\n\n默认保留：\n- $MODEL_DIR 下的 GGUF 模型"
    ui_confirm "确认进入卸载流程吗？\n\n当前版本只展示范围，不会删除文件。" || die "用户取消操作"
    log_info "卸载执行逻辑尚未启用，本次未修改系统"
}
