#!/usr/bin/env bash

preflight_common() {
    local action="$1"
    log_info "执行 $action 预检"

    if [[ "$action" != status && "${DRY_RUN:-0}" != 1 ]] && ! is_root; then
        die "该操作需要 root 权限，请使用 sudo 运行"
    fi

    command_exists git || log_warn "未安装 git；正式安装阶段将补齐依赖"
    command_exists cmake || log_warn "未安装 cmake；正式安装阶段将补齐依赖"

    if ((NVIDIA_GPU_DETECTED == 0)); then
        log_warn "没有检测到 NVIDIA GPU"
    fi
    if ((CUDA_TOOLKIT_DETECTED == 0)); then
        log_warn "没有检测到 CUDA Toolkit；正式实现将提供安装或退出选择"
    fi
}

preflight_model() {
    [[ "$MODEL_PATH" == *.gguf ]] || die "请选择本地 .gguf 模型"
    if [[ ! -f "$MODEL_PATH" ]]; then
        log_warn "模型当前不存在：$MODEL_PATH；框架预览允许继续"
    elif [[ ! -r "$MODEL_PATH" ]]; then
        die "模型不可读：$MODEL_PATH"
    fi
}
