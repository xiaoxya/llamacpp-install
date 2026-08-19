#!/usr/bin/env bash

detect_hardware() {
    NVIDIA_GPU_DETECTED=0
    CUDA_TOOLKIT_DETECTED=0
    GPU_SUMMARY="未发现 NVIDIA GPU"
    CUDA_SUMMARY="未发现 nvcc"

    if command_exists nvidia-smi; then
        NVIDIA_GPU_DETECTED=1
        GPU_SUMMARY="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | paste -sd ', ' -)"
        [[ -n "$GPU_SUMMARY" ]] || GPU_SUMMARY="已发现 NVIDIA GPU"
    elif command_exists lspci && lspci -nn 2>/dev/null | grep -qi nvidia; then
        NVIDIA_GPU_DETECTED=1
        GPU_SUMMARY="已通过 PCI 检测到 NVIDIA 设备"
    fi

    if command_exists nvcc; then
        CUDA_TOOLKIT_DETECTED=1
        CUDA_SUMMARY="$(nvcc --version 2>/dev/null | awk '/release/ { print $5 }' | tr -d ',')"
        [[ -n "$CUDA_SUMMARY" ]] || CUDA_SUMMARY="已发现 nvcc"
    fi
}

backend_recommendation() {
    if ((NVIDIA_GPU_DETECTED)); then
        printf '%s\n' cuda
    else
        printf '%s\n' unavailable
    fi
}

backend_confirm_cuda() {
    local recommendation
    recommendation="$(backend_recommendation)"
    if [[ "$recommendation" == cuda ]]; then
        ui_confirm "检测到 NVIDIA GPU。使用 CUDA 后端编译吗？"
    else
        ui_confirm "没有检测到 NVIDIA GPU。首版只支持 CUDA，仍要继续配置并在预检阶段验证吗？"
    fi
}
