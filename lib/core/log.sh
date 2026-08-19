#!/usr/bin/env bash

log_init() {
    LOG_FILE="${LOG_FILE:-/tmp/llama-cpp-deploy-$(date +%Y%m%d-%H%M%S).log}"
}

log_info() {
    printf '[INFO] %s\n' "$*" | tee -a "$LOG_FILE" >&2
}

log_warn() {
    printf '[WARN] %s\n' "$*" | tee -a "$LOG_FILE" >&2
}

on_error() {
    local line="$1" status="$2"
    printf '[ERROR] 第 %s 行执行失败，状态码：%s\n' "$line" "$status" | tee -a "$LOG_FILE" >&2
}
