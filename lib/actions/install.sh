#!/usr/bin/env bash

collect_install_config() {
    backend_confirm_cuda || die "用户取消 CUDA 后端配置"
    BACKEND=cuda

    SOURCE_REF="$(ui_input "请输入要编译的 llama.cpp tag、分支或 commit" "$SOURCE_REF")"
    MODEL_PATH="$(ui_input "请输入本地 GGUF 模型的绝对路径" "$MODEL_DIR/model.gguf")"
    CONTEXT_SIZE="$(ui_input "上下文长度" "$CONTEXT_SIZE")"
    GPU_LAYERS="$(ui_input "卸载到 GPU 的层数（999 表示尽可能全部卸载）" "$GPU_LAYERS")"
    THREADS="$(ui_input "CPU 线程数" "$THREADS")"
    PARALLEL="$(ui_input "服务并发槽位" "$PARALLEL")"
}

install_pipeline_preview() {
    cat <<EOF
执行计划
01  安装 ${PACKAGE_FAMILY} 编译依赖和 CUDA Toolkit
02  创建非登录系统用户 $SERVICE_USER
03  克隆源码并检出 $SOURCE_REF
04  验证本地 GGUF 的读取权限
05  使用 CUDA profile 编译 llama-server
06  写入新的 release 目录
07  安装环境配置和 systemd unit
08  原子切换 $CURRENT_LINK
09  启动服务并检查 127.0.0.1:$SERVER_PORT
10  清理多余版本，保留当前及上一版本
EOF
}

action_install() {
    preflight_common install
    collect_install_config
    validate_config
    preflight_model

    local summary
    summary="$(config_summary)"
    ui_message "部署配置\n$summary"
    install_pipeline_preview

    if [[ "${DRY_RUN:-0}" == 1 ]]; then
        log_info "dry-run 完成，未修改系统"
        return 0
    fi

    ui_confirm "确认以上配置并进入实现阶段吗？\n当前版本只展示框架，不会修改系统。" || \
        die "用户取消操作"
    ui_message "框架确认完成。依赖安装、编译和系统写入将在下一阶段实现，本次未修改系统。"
}
