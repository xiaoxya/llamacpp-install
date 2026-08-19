#!/usr/bin/env bash

config_defaults() {
    UI_MODE="${UI_MODE:-auto}"
    DRY_RUN="${DRY_RUN:-0}"
    REQUESTED_ACTION="${REQUESTED_ACTION:-}"

    SERVICE_NAME="llama-server"
    SERVICE_USER="llama"
    INSTALL_ROOT="/opt/llama.cpp"
    RELEASES_DIR="$INSTALL_ROOT/releases"
    CURRENT_LINK="$INSTALL_ROOT/current"
    CONFIG_DIR="/etc/llama.cpp"
    STATE_FILE="/var/lib/llama.cpp/install.state"
    MODEL_DIR="/var/lib/llama.cpp/models"

    SOURCE_URL="https://github.com/ggml-org/llama.cpp.git"
    SOURCE_REF="master"
    BACKEND="cuda"
    MODEL_PATH=""
    SERVER_HOST="0.0.0.0"
    SERVER_PORT="80"
    CONTEXT_SIZE="4096"
    GPU_LAYERS="999"
    THREADS="$(command_exists nproc && nproc || printf '4')"
    PARALLEL="1"
    EXTRA_ARGS=""
    KEEP_RELEASES="2"
}

validate_config() {
    [[ "$BACKEND" == cuda ]] || die "首版仅支持 CUDA 后端"
    [[ -n "$MODEL_PATH" ]] || die "必须选择本地 GGUF 模型"
    [[ "$MODEL_PATH" == /* ]] || die "模型必须使用绝对路径"
    [[ "$MODEL_PATH" == *.gguf ]] || die "模型文件必须使用 .gguf 扩展名"
    case "$MODEL_PATH" in
        /home/*|/root/*|/run/user/*)
            die "systemd 沙箱不会访问用户主目录；请把模型移到 $MODEL_DIR 或独立数据盘"
            ;;
    esac
    [[ "$SERVER_PORT" =~ ^[0-9]+$ ]] || die "端口必须是整数"
    ((SERVER_PORT >= 1 && SERVER_PORT <= 65535)) || die "端口超出有效范围"
    [[ "$CONTEXT_SIZE" =~ ^[0-9]+$ ]] || die "上下文长度必须是整数"
    [[ "$GPU_LAYERS" =~ ^[0-9]+$ ]] || die "GPU 层数必须是非负整数"
}

config_summary() {
    cat <<EOF
系统     │ ${DISTRO_NAME:-未知} (${PACKAGE_FAMILY:-未知})
GPU      │ ${GPU_SUMMARY:-未发现 NVIDIA GPU}
CUDA     │ ${CUDA_SUMMARY:-未检测}
后端     │ $BACKEND
版本     │ $SOURCE_REF
模型     │ $MODEL_PATH
监听     │ $SERVER_HOST:$SERVER_PORT
上下文   │ $CONTEXT_SIZE
GPU 层数 │ $GPU_LAYERS
CPU 线程 │ $THREADS
并发     │ $PARALLEL
保留版本 │ $KEEP_RELEASES
EOF
}
