#!/usr/bin/env bash

apt_base_packages() {
    printf '%s\n' git cmake ninja-build build-essential pkg-config curl ca-certificates
}

apt_cuda_packages() {
    # CUDA Toolkit 的具体来源和版本策略将在实现阶段单独确认。
    printf '%s\n' nvidia-cuda-toolkit
}
