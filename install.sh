#!/usr/bin/env bash
set -Eeuo pipefail

# llama.cpp CUDA 单文件部署脚本
# 支持：Debian / Ubuntu / Arch Linux、local GGUF、systemd、更新与回滚

readonly APP_NAME="llama.cpp CUDA 部署"
readonly SOURCE_URL="https://github.com/ggml-org/llama.cpp.git"
readonly INSTALL_ROOT="/opt/llama.cpp"
readonly RELEASES_DIR="$INSTALL_ROOT/releases"
readonly CURRENT_LINK="$INSTALL_ROOT/current"
readonly PREVIOUS_LINK="$INSTALL_ROOT/previous"
readonly CONFIG_DIR="/etc/llama.cpp"
readonly STATE_FILE="$CONFIG_DIR/install.conf"
readonly SERVICE_FILE="/etc/systemd/system/llama-server.service"
readonly SERVICE_NAME="llama-server"
readonly DEFAULT_MODEL_DIR="/var/lib/llama.cpp/models"
readonly UI_WIDTH=68

UI_MODE="auto"
REQUESTED_ACTION=""
DISTRO_ID=""
DISTRO_NAME=""
PACKAGE_FAMILY=""
SOURCE_REF="master"
MODEL_DIR="$DEFAULT_MODEL_DIR"
MODEL_PATH=""
SERVICE_USER="${SUDO_USER:-llama}"
SERVICE_GROUP=""
SERVER_HOST="0.0.0.0"
SERVER_PORT="80"
CTX_SIZE="4096"
GPU_LAYERS="all"
THREADS="$(command -v nproc >/dev/null 2>&1 && nproc || printf '4')"
PARALLEL="1"
EXTRA_ARGS_TEXT=""
HEALTH_TIMEOUT="180"
PARSED_WORDS=()
NVCC_PATH=""

die() {
    printf '错误：%s\n' "$*" >&2
    exit 1
}

info() {
    printf '[+] %s\n' "$*"
}

warn() {
    printf '[!] %s\n' "$*" >&2
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

run() {
    printf '  $'
    printf ' %q' "$@"
    printf '\n'
    "$@"
}

on_error() {
    local line="$1" status="$2"
    printf '\n[失败] 第 %s 行，退出码 %s。\n' "$line" "$status" >&2
}

usage() {
    cat <<'EOF'
llama.cpp CUDA 单文件部署脚本

用法：
  sudo ./install.sh
  sudo ./install.sh --action install|configure|update|rollback|status|uninstall

选项：
  --action ACTION  直接选择操作
  --ui MODE        auto、whiptail、dialog 或 text
  --self-test      运行脚本内置测试，不修改系统
  -h, --help       显示帮助
EOF
}

parse_cli() {
    while (($#)); do
        case "$1" in
            --action)
                (($# >= 2)) || die "--action 缺少参数"
                REQUESTED_ACTION="$2"
                shift
                ;;
            --ui)
                (($# >= 2)) || die "--ui 缺少参数"
                UI_MODE="$2"
                shift
                ;;
            --self-test) REQUESTED_ACTION="self-test" ;;
            -h|--help)
                usage
                exit 0
                ;;
            *) die "未知参数：$1" ;;
        esac
        shift
    done
}

ui_init() {
    case "$UI_MODE" in
        auto)
            if command_exists whiptail; then
                UI_MODE="whiptail"
            elif command_exists dialog; then
                UI_MODE="dialog"
            else
                UI_MODE="text"
            fi
            ;;
        whiptail|dialog)
            command_exists "$UI_MODE" || die "找不到界面工具：$UI_MODE"
            ;;
        text) ;;
        *) die "不支持的 UI 模式：$UI_MODE" ;;
    esac
}

ui_height() {
    local text="$1" padding="${2:-5}" minimum="${3:-7}" maximum="${4:-22}"
    local lines=1 rest="$text" height
    while [[ "$rest" == *$'\n'* ]]; do
        rest="${rest#*$'\n'}"
        ((lines += 1))
    done
    height=$((lines + padding))
    ((height < minimum)) && height="$minimum"
    ((height > maximum)) && height="$maximum"
    printf '%s\n' "$height"
}

ui_message() {
    local message="${1//\\n/$'\n'}" height
    height="$(ui_height "$message")"
    case "$UI_MODE" in
        whiptail)
            whiptail --title "$APP_NAME" --ok-button "确定" \
                --msgbox "$message" "$height" "$UI_WIDTH"
            ;;
        dialog)
            dialog --title "$APP_NAME" --ok-label "确定" \
                --msgbox "$message" "$height" "$UI_WIDTH"
            ;;
        text)
            printf '┌─ %s\n%s\n└─\n' "$APP_NAME" "$message"
            ;;
    esac
}

ui_confirm() {
    local prompt="${1//\\n/$'\n'}" height answer
    height="$(ui_height "$prompt" 5 7 16)"
    case "$UI_MODE" in
        whiptail)
            whiptail --title "确认 · $APP_NAME" --yes-button "继续" --no-button "返回" \
                --yesno "$prompt" "$height" "$UI_WIDTH"
            ;;
        dialog)
            dialog --title "确认 · $APP_NAME" --yes-label "继续" --no-label "返回" \
                --yesno "$prompt" "$height" "$UI_WIDTH"
            ;;
        text)
            printf '┌─ 确认\n%s\n' "$prompt" >&2
            read -r -p "└─ 继续？[y/N] › " answer
            [[ "$answer" =~ ^[Yy]$ ]]
            ;;
    esac
}

ui_input() {
    local prompt="$1" default_value="${2:-}" result
    case "$UI_MODE" in
        whiptail)
            whiptail --title "$APP_NAME" --ok-button "确认" --cancel-button "取消" \
                --inputbox "$prompt" 8 "$UI_WIDTH" "$default_value" 3>&1 1>&2 2>&3
            ;;
        dialog)
            dialog --stdout --title "$APP_NAME" --ok-label "确认" --cancel-label "取消" \
                --inputbox "$prompt" 8 "$UI_WIDTH" "$default_value"
            ;;
        text)
            read -r -p "› $prompt [$default_value]：" result
            printf '%s\n' "${result:-$default_value}"
            ;;
    esac
}

# 参数：提示、默认 tag、tag/说明成对出现。
ui_menu() {
    local prompt="$1" default_tag="$2"
    shift 2
    local -a items=("$@")
    local count height list_height index=1 default_index=1 answer i
    count=$((${#items[@]} / 2))
    list_height="$count"
    ((list_height > 15)) && list_height=15
    height=$((list_height + 7))

    case "$UI_MODE" in
        whiptail)
            whiptail --title "$APP_NAME" --ok-button "选择" --cancel-button "退出" \
                --notags --default-item "$default_tag" \
                --menu "$prompt" "$height" "$UI_WIDTH" "$list_height" \
                "${items[@]}" 3>&1 1>&2 2>&3
            ;;
        dialog)
            dialog --stdout --title "$APP_NAME" --ok-label "选择" --cancel-label "退出" \
                --no-tags --default-item "$default_tag" \
                --menu "$prompt" "$height" "$UI_WIDTH" "$list_height" "${items[@]}"
            ;;
        text)
            printf '┌─ %s · %s\n' "$APP_NAME" "$prompt" >&2
            for ((i = 0; i < ${#items[@]}; i += 2)); do
                [[ "${items[i]}" == "$default_tag" ]] && default_index="$index"
                printf '│ %d  %s\n' "$index" "${items[i + 1]}" >&2
                ((index += 1))
            done
            read -r -p "└─ 选择 [默认 $default_index] › " answer
            if [[ -z "$answer" ]]; then
                printf '%s\n' "$default_tag"
            elif [[ "$answer" =~ ^[0-9]+$ ]] && ((answer >= 1 && answer <= count)); then
                printf '%s\n' "${items[(answer - 1) * 2]}"
            else
                die "无效选择：$answer"
            fi
            ;;
    esac
}

require_root() {
    [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "请使用 sudo 运行此操作"
}

detect_platform() {
    [[ "$(uname -s)" == "Linux" ]] || die "仅支持 Linux"
    [[ -r /etc/os-release ]] || die "无法读取 /etc/os-release"

    local id="" id_like="" pretty=""
    while IFS='=' read -r key value; do
        value="${value%\"}"
        value="${value#\"}"
        case "$key" in
            ID) id="$value" ;;
            ID_LIKE) id_like="$value" ;;
            PRETTY_NAME) pretty="$value" ;;
        esac
    done < /etc/os-release

    DISTRO_ID="$id"
    DISTRO_NAME="${pretty:-$id}"
    case " $id $id_like " in
        *" debian "*|*" ubuntu "*) PACKAGE_FAMILY="apt" ;;
        *" arch "*) PACKAGE_FAMILY="pacman" ;;
        *) die "不支持的发行版：$DISTRO_NAME" ;;
    esac
}

install_dependencies() {
    info "安装编译依赖"
    case "$PACKAGE_FAMILY" in
        apt)
            run apt-get update
            run apt-get install -y git cmake ninja-build build-essential curl ca-certificates pciutils
            ;;
        pacman)
            run pacman -Syu --needed --noconfirm git cmake ninja base-devel curl ca-certificates pciutils
            ;;
    esac
}

locate_cuda() {
    local candidate
    if command_exists nvcc; then
        NVCC_PATH="$(command -v nvcc)"
        return 0
    fi
    for candidate in /usr/local/cuda/bin/nvcc /opt/cuda/bin/nvcc; do
        if [[ -x "$candidate" ]]; then
            NVCC_PATH="$candidate"
            export PATH="$(dirname "$candidate"):$PATH"
            return 0
        fi
    done
    return 1
}

check_cuda() {
    if ! command_exists nvidia-smi; then
        die "未检测到 NVIDIA 驱动（nvidia-smi）。请先正确安装显卡驱动"
    fi
    info "GPU：$(nvidia-smi --query-gpu=name --format=csv,noheader | paste -sd ', ' -)"

    if locate_cuda; then
        info "CUDA：$(nvcc --version | awk '/release/ { print $5 }' | tr -d ',')"
        return
    fi

    ui_confirm "未检测到 CUDA Toolkit（nvcc）。\n是否尝试从当前发行版仓库安装？" || \
        die "CUDA Toolkit 是源码编译 CUDA 后端的必要条件"
    case "$PACKAGE_FAMILY" in
        apt) run apt-get install -y nvidia-cuda-toolkit ;;
        pacman) run pacman -S --needed --noconfirm cuda ;;
    esac
    locate_cuda || die "CUDA Toolkit 安装后仍找不到 nvcc，请检查 PATH"
}

ensure_service_user() {
    if id "$SERVICE_USER" >/dev/null 2>&1; then
        SERVICE_GROUP="$(id -gn "$SERVICE_USER")"
        return
    fi
    [[ "$SERVICE_USER" == "llama" ]] || die "服务用户不存在：$SERVICE_USER"
    local nologin_shell
    nologin_shell="$(command -v nologin || printf '/usr/sbin/nologin')"
    run useradd --system --home-dir /nonexistent --shell "$nologin_shell" llama
    SERVICE_GROUP="$(id -gn llama)"
}

human_size() {
    local file="$1" bytes
    bytes="$(stat -c '%s' "$file")"
    if ((bytes >= 1073741824)); then
        awk -v n="$bytes" 'BEGIN { printf "%.1f GiB", n / 1073741824 }'
    elif ((bytes >= 1048576)); then
        awk -v n="$bytes" 'BEGIN { printf "%.1f MiB", n / 1048576 }'
    else
        printf '%s KiB' "$((bytes / 1024))"
    fi
}

select_model() {
    MODEL_DIR="$(ui_input "GGUF 模型目录" "$MODEL_DIR")" || die "已取消"
    local -a models=() menu_items=()
    local file display choice i default_choice="manual" manual_default

    if [[ -d "$MODEL_DIR" ]]; then
        while IFS= read -r -d '' file; do
            models+=("$file")
        done < <(find -L "$MODEL_DIR" -maxdepth 3 -type f -iname '*.gguf' -print0 | sort -z)
    fi

    for ((i = 0; i < ${#models[@]}; i++)); do
        display="${models[i]#"$MODEL_DIR"/} · $(human_size "${models[i]}")"
        menu_items+=("$i" "$display")
        [[ "${models[i]}" == "$MODEL_PATH" ]] && default_choice="$i"
    done
    menu_items+=("manual" "手动输入 GGUF 文件路径")
    if [[ "$default_choice" == "manual" && ${#models[@]} -gt 0 && -z "$MODEL_PATH" ]]; then
        default_choice="0"
    fi

    choice="$(ui_menu "选择本地模型（找到 ${#models[@]} 个）" \
        "$default_choice" "${menu_items[@]}")" || die "已取消模型选择"
    if [[ "$choice" == "manual" ]]; then
        manual_default="${MODEL_PATH:-$MODEL_DIR/model.gguf}"
        MODEL_PATH="$(ui_input "GGUF 文件绝对路径" "$manual_default")" || die "已取消"
    else
        MODEL_PATH="${models[choice]}"
    fi

    [[ "$MODEL_PATH" == /* ]] || die "模型必须使用绝对路径"
    [[ "$MODEL_PATH" == *.gguf || "$MODEL_PATH" == *.GGUF ]] || die "文件扩展名必须是 .gguf"
    [[ -f "$MODEL_PATH" ]] || die "模型不存在：$MODEL_PATH"
}

# 安全解析类似 shell 的参数字符串：支持空格、单/双引号和反斜线，
# 不执行变量替换、命令替换、重定向或任何 shell 代码。
parse_words() {
    local input="$1" state="normal" token="" char
    local token_started=0 i
    PARSED_WORDS=()

    for ((i = 0; i < ${#input}; i++)); do
        char="${input:i:1}"
        case "$state" in
            normal)
                case "$char" in
                    ' '|$'\t')
                        if ((token_started)); then
                            PARSED_WORDS+=("$token")
                            token=""
                            token_started=0
                        fi
                        ;;
                    "'") state="single"; token_started=1 ;;
                    '"') state="double"; token_started=1 ;;
                    '\\') state="escape"; token_started=1 ;;
                    *) token+="$char"; token_started=1 ;;
                esac
                ;;
            single)
                [[ "$char" == "'" ]] && state="normal" || token+="$char"
                ;;
            double)
                case "$char" in
                    '"') state="normal" ;;
                    '\\') state="double_escape" ;;
                    *) token+="$char" ;;
                esac
                ;;
            escape) token+="$char"; state="normal" ;;
            double_escape) token+="$char"; state="double" ;;
        esac
    done

    [[ "$state" == "normal" ]] || die "附加参数中存在未闭合的引号或反斜线"
    ((token_started)) && PARSED_WORDS+=("$token")
    return 0
}

validate_source_ref() {
    [[ -n "$SOURCE_REF" ]] || die "源码版本不能为空"
    [[ "$SOURCE_REF" != -* ]] || die "源码版本不能以连字符开头"
    [[ "$SOURCE_REF" =~ ^[A-Za-z0-9._/-]+$ ]] || die "源码版本包含不安全字符"
}

validate_extra_args() {
    local arg
    for arg in "${PARSED_WORDS[@]}"; do
        case "$arg" in
            -m|--model|--model=*|--host|--host=*|--port|--port=*|\
            -c|--ctx-size|--ctx-size=*|-ngl|--gpu-layers|--gpu-layers=*|\
            --n-gpu-layers|--n-gpu-layers=*|-t|--threads|--threads=*|\
            -np|--parallel|--parallel=*)
                die "附加参数不能重复覆盖交互式字段：$arg"
                ;;
        esac
    done
}

collect_runtime_config() {
    SERVICE_USER="$(ui_input "systemd 服务运行用户" "$SERVICE_USER")" || die "已取消"
    SERVER_HOST="$(ui_input "监听地址" "$SERVER_HOST")" || die "已取消"
    SERVER_PORT="$(ui_input "监听端口" "$SERVER_PORT")" || die "已取消"
    CTX_SIZE="$(ui_input "上下文长度（0 表示读取模型默认值）" "$CTX_SIZE")" || die "已取消"
    GPU_LAYERS="$(ui_input "GPU 层数（数字、auto 或 all）" "$GPU_LAYERS")" || die "已取消"
    THREADS="$(ui_input "CPU 线程数" "$THREADS")" || die "已取消"
    PARALLEL="$(ui_input "并发槽位" "$PARALLEL")" || die "已取消"
    EXTRA_ARGS_TEXT="$(ui_input "附加 llama-server 参数（可留空）" "$EXTRA_ARGS_TEXT")" || die "已取消"

    [[ -n "$SERVICE_USER" && "$SERVICE_USER" != *[[:space:]]* ]] || die "服务用户名无效"
    [[ -n "$SERVER_HOST" && "$SERVER_HOST" != *[[:space:]]* ]] || die "监听地址无效"
    [[ "$SERVER_PORT" =~ ^[0-9]+$ ]] && ((SERVER_PORT >= 1 && SERVER_PORT <= 65535)) || die "端口无效"
    [[ "$CTX_SIZE" =~ ^[0-9]+$ ]] || die "上下文长度必须是非负整数"
    [[ "$GPU_LAYERS" =~ ^[0-9]+$ || "$GPU_LAYERS" == "auto" || "$GPU_LAYERS" == "all" ]] || \
        die "GPU 层数必须是数字、auto 或 all"
    [[ "$THREADS" =~ ^[1-9][0-9]*$ ]] || die "CPU 线程数必须是正整数"
    [[ "$PARALLEL" =~ ^[1-9][0-9]*$ ]] || die "并发槽位必须是正整数"

    parse_words "$EXTRA_ARGS_TEXT"
    validate_extra_args
}

config_summary() {
    cat <<EOF
系统     │ $DISTRO_NAME
源码版本 │ $SOURCE_REF
模型     │ $MODEL_PATH
服务用户 │ $SERVICE_USER
监听     │ $SERVER_HOST:$SERVER_PORT
上下文   │ $CTX_SIZE
GPU 层数 │ $GPU_LAYERS
CPU 线程 │ $THREADS
并发     │ $PARALLEL
附加参数 │ ${EXTRA_ARGS_TEXT:-无}
EOF
}

check_model_access() {
    if runuser -u "$SERVICE_USER" -- test -r "$MODEL_PATH"; then
        return
    fi
    die "用户 $SERVICE_USER 无法读取模型。请调整模型文件及父目录权限，或选择能读取它的服务用户"
}

sanitize_ref() {
    printf '%s' "$1" | tr -cs '[:alnum:]._-' '-'
}

build_release() {
    local ref="$1" release_id release_dir
    release_id="$(date +%Y%m%d-%H%M%S)-$(sanitize_ref "$ref")-$$"
    release_dir="$RELEASES_DIR/$release_id"
    mkdir -p "$RELEASES_DIR"

    info "克隆 llama.cpp：$ref" >&2
    run git clone --filter=blob:none "$SOURCE_URL" "$release_dir" >&2
    run git -C "$release_dir" checkout "$ref" >&2

    info "配置 CUDA 构建" >&2
    run cmake -S "$release_dir" -B "$release_dir/build" -G Ninja \
        -DGGML_CUDA=ON \
        -DGGML_NATIVE=ON \
        -DGGML_BUILD_TESTS=OFF \
        -DGGML_BUILD_EXAMPLES=ON \
        -DCMAKE_BUILD_TYPE=Release >&2

    info "编译 llama-server" >&2
    run cmake --build "$release_dir/build" --target llama-server -j "$THREADS" >&2
    [[ -x "$release_dir/build/bin/llama-server" ]] || die "编译完成但未找到 llama-server"
    "$release_dir/build/bin/llama-server" --version >&2
    printf '%s\n' "$ref" > "$release_dir/.source-ref"
    printf '%s\n' "$release_dir"
}

atomic_link() {
    local target="$1" link="$2" temp_link="${link}.new.$$"
    rm -f -- "$temp_link"
    ln -s "$target" "$temp_link"
    mv -Tf "$temp_link" "$link"
}

activate_release() {
    local new_release="$1" old_release=""
    if [[ -L "$CURRENT_LINK" ]]; then
        old_release="$(readlink -f "$CURRENT_LINK")"
    fi
    if [[ -n "$old_release" && "$old_release" != "$new_release" ]]; then
        atomic_link "$old_release" "$PREVIOUS_LINK"
    fi
    atomic_link "$new_release" "$CURRENT_LINK"
}

systemd_quote() {
    local value="$1"
    [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || die "systemd 参数不能包含换行"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//%/%%}"
    value="${value//\$/\$\$}"
    printf '"%s"' "$value"
}

write_service() {
    local temp_file exec_line arg capability_line=""
    local -a server_args=(
        --model "$MODEL_PATH"
        --host "$SERVER_HOST"
        --port "$SERVER_PORT"
        --ctx-size "$CTX_SIZE"
        --n-gpu-layers "$GPU_LAYERS"
        --threads "$THREADS"
        --parallel "$PARALLEL"
        "${PARSED_WORDS[@]}"
    )

    exec_line="ExecStart=$(systemd_quote "$CURRENT_LINK/build/bin/llama-server")"
    for arg in "${server_args[@]}"; do
        exec_line+=" $(systemd_quote "$arg")"
    done
    ((SERVER_PORT < 1024)) && capability_line=$'AmbientCapabilities=CAP_NET_BIND_SERVICE\nCapabilityBoundingSet=CAP_NET_BIND_SERVICE'

    mkdir -p "$CONFIG_DIR"
    temp_file="$(mktemp)"
    cat > "$temp_file" <<EOF
[Unit]
Description=llama.cpp CUDA server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_GROUP
WorkingDirectory=$CURRENT_LINK
$exec_line
Restart=on-failure
RestartSec=5s
TimeoutStopSec=30s
$capability_line
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
LockPersonality=true
MemoryDenyWriteExecute=false
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
    install -o root -g root -m 0644 "$temp_file" "$SERVICE_FILE"
    rm -f -- "$temp_file"
    run systemctl daemon-reload
}

save_state() {
    local temp_file key value
    temp_file="$(mktemp)"
    for key in SOURCE_REF MODEL_DIR MODEL_PATH SERVICE_USER SERVICE_GROUP SERVER_HOST \
        SERVER_PORT CTX_SIZE GPU_LAYERS THREADS PARALLEL EXTRA_ARGS_TEXT HEALTH_TIMEOUT; do
        value="${!key}"
        printf '%s=%q\n' "$key" "$value" >> "$temp_file"
    done
    install -o root -g root -m 0600 "$temp_file" "$STATE_FILE"
    rm -f -- "$temp_file"
}

load_state() {
    [[ -r "$STATE_FILE" ]] || die "尚未安装：找不到 $STATE_FILE"
    # 文件由本脚本以 root:root 0600 创建。
    # shellcheck disable=SC1090
    source "$STATE_FILE"
    parse_words "$EXTRA_ARGS_TEXT"
    validate_extra_args
}

health_check() {
    local host="$SERVER_HOST" elapsed=0
    [[ "$host" == "0.0.0.0" || "$host" == "::" ]] && host="127.0.0.1"
    info "等待模型加载，最长 ${HEALTH_TIMEOUT}s"
    while ((elapsed < HEALTH_TIMEOUT)); do
        if curl -fsS --max-time 3 "http://$host:$SERVER_PORT/health" >/dev/null 2>&1; then
            info "服务健康检查通过：http://$host:$SERVER_PORT"
            return 0
        fi
        if ! systemctl is-active --quiet "$SERVICE_NAME"; then
            systemctl status "$SERVICE_NAME" --no-pager || true
            return 1
        fi
        sleep 3
        ((elapsed += 3))
    done
    warn "健康检查超时；服务可能仍在加载大型模型"
    return 1
}

restart_and_verify() {
    run systemctl enable "$SERVICE_NAME"
    run systemctl restart "$SERVICE_NAME"
    health_check
}

rollback_links() {
    [[ -L "$PREVIOUS_LINK" ]] || return 1
    local current previous
    current="$(readlink -f "$CURRENT_LINK")"
    previous="$(readlink -f "$PREVIOUS_LINK")"
    atomic_link "$previous" "$CURRENT_LINK"
    atomic_link "$current" "$PREVIOUS_LINK"
}

prune_releases() {
    local current="" previous="" path
    [[ -L "$CURRENT_LINK" ]] && current="$(readlink -f "$CURRENT_LINK")"
    [[ -L "$PREVIOUS_LINK" ]] && previous="$(readlink -f "$PREVIOUS_LINK")"

    while IFS= read -r path; do
        [[ "$path" == "$current" || "$path" == "$previous" ]] && continue
        [[ "$path" == "$RELEASES_DIR/"* ]] || die "拒绝清理异常路径：$path"
        info "清理旧版本：$(basename "$path")"
        rm -rf -- "$path"
    done < <(find "$RELEASES_DIR" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null)
}

action_install() {
    require_root
    detect_platform
    install_dependencies
    check_cuda

    SOURCE_REF="$(ui_input "llama.cpp tag、分支或 commit" "$SOURCE_REF")" || die "已取消"
    validate_source_ref
    select_model
    collect_runtime_config
    ensure_service_user
    check_model_access

    local release_dir
    ui_confirm "部署配置\n$(config_summary)\n\n将从源码编译并写入 systemd，确认继续？" || die "已取消"

    release_dir="$(build_release "$SOURCE_REF")"
    activate_release "$release_dir"
    write_service
    if ! restart_and_verify; then
        if rollback_links; then
            warn "新版本启动失败，正在恢复上一版本"
            systemctl restart "$SERVICE_NAME" || true
        fi
        die "部署未通过健康检查，请查看 journalctl -u $SERVICE_NAME"
    fi
    save_state
    prune_releases
    ui_message "部署完成\n模型：$MODEL_PATH\n地址：http://$SERVER_HOST:$SERVER_PORT"
}

action_configure() {
    require_root
    detect_platform
    load_state
    select_model
    collect_runtime_config
    ensure_service_user
    check_model_access
    parse_words "$EXTRA_ARGS_TEXT"
    validate_extra_args

    ui_confirm "新的运行配置\n$(config_summary)\n\n确认重启服务？" || die "已取消"
    local service_backup
    service_backup="$(mktemp)"
    cp -a "$SERVICE_FILE" "$service_backup"
    write_service
    if ! restart_and_verify; then
        warn "新配置启动失败，正在恢复原 systemd 配置"
        install -o root -g root -m 0644 "$service_backup" "$SERVICE_FILE"
        systemctl daemon-reload
        systemctl restart "$SERVICE_NAME" || true
        rm -f -- "$service_backup"
        die "服务未通过健康检查，原配置已恢复"
    fi
    rm -f -- "$service_backup"
    save_state
    ui_message "运行配置已更新"
}

action_update() {
    require_root
    detect_platform
    load_state
    install_dependencies
    check_cuda
    SOURCE_REF="$(ui_input "新的 tag、分支或 commit" "$SOURCE_REF")" || die "已取消"
    validate_source_ref
    ui_confirm "将编译 $SOURCE_REF，并保留当前版本用于回滚。确认继续？" || die "已取消"

    local release_dir
    release_dir="$(build_release "$SOURCE_REF")"
    activate_release "$release_dir"
    if ! restart_and_verify; then
        rollback_links || true
        if [[ -r "$CURRENT_LINK/.source-ref" ]]; then
            SOURCE_REF="$(< "$CURRENT_LINK/.source-ref")"
        fi
        systemctl restart "$SERVICE_NAME" || true
        die "更新失败，已尝试恢复上一版本"
    fi
    save_state
    prune_releases
    ui_message "更新完成\n当前版本：$(basename "$release_dir")"
}

action_rollback() {
    require_root
    load_state
    [[ -L "$PREVIOUS_LINK" ]] || die "没有可回滚版本"
    local target
    target="$(readlink -f "$PREVIOUS_LINK")"
    ui_confirm "回滚到 $(basename "$target") 并重启服务？" || die "已取消"
    rollback_links || die "回滚链接失败"
    if ! restart_and_verify; then
        rollback_links || true
        systemctl restart "$SERVICE_NAME" || true
        die "回滚版本未通过健康检查，已尝试恢复原版本"
    fi
    if [[ -r "$CURRENT_LINK/.source-ref" ]]; then
        SOURCE_REF="$(< "$CURRENT_LINK/.source-ref")"
    fi
    save_state
    ui_message "已回滚到 $(basename "$(readlink -f "$CURRENT_LINK")")"
}

action_status() {
    require_root
    detect_platform
    if [[ -r "$STATE_FILE" ]]; then
        load_state
        ui_message "$(config_summary)\n当前构建 │ $(basename "$(readlink -f "$CURRENT_LINK")")"
    else
        ui_message "尚未安装 llama.cpp Server"
        return
    fi
    systemctl status "$SERVICE_NAME" --no-pager || true
}

action_uninstall() {
    require_root
    ui_confirm "将停止并删除：\n$SERVICE_FILE\n$CONFIG_DIR\n$INSTALL_ROOT\n\n不会删除任何 GGUF 模型。确认卸载？" || die "已取消"
    systemctl disable --now "$SERVICE_NAME" 2>/dev/null || true
    [[ "$INSTALL_ROOT" == "/opt/llama.cpp" ]] || die "安装目录安全检查失败"
    rm -f -- "$SERVICE_FILE"
    rm -rf -- "$CONFIG_DIR" "$INSTALL_ROOT"
    systemctl daemon-reload
    ui_message "卸载完成，GGUF 模型已保留"
}

self_test() {
    local quoted
    parse_words "--flash-attn on --alias 'my model' --no-webui"
    [[ "${#PARSED_WORDS[@]}" -eq 5 ]]
    [[ "${PARSED_WORDS[3]}" == "my model" ]]
    parse_words ""
    [[ "${#PARSED_WORDS[@]}" -eq 0 ]]
    quoted="$(systemd_quote '/data/A 100%/model.gguf')"
    [[ "$quoted" == *'100%%'* ]]
    SERVER_PORT=80
    CTX_SIZE=4096
    GPU_LAYERS=all
    THREADS=4
    PARALLEL=1
    PARSED_WORDS=(--flash-attn on)
    validate_extra_args
    printf 'self-test: PASS\n'
}

select_action() {
    if [[ -n "$REQUESTED_ACTION" ]]; then
        printf '%s\n' "$REQUESTED_ACTION"
        return
    fi
    ui_menu "选择操作" install \
        install "安装 / 重新部署" \
        configure "选择模型 / 修改运行参数" \
        update "更新 llama.cpp" \
        rollback "回滚上一版本" \
        status "查看服务状态" \
        uninstall "卸载（保留模型）" \
        quit "退出"
}

main() {
    parse_cli "$@"
    if [[ "$REQUESTED_ACTION" == "self-test" ]]; then
        self_test
        exit 0
    fi

    ui_init
    trap 'on_error "$LINENO" "$?"' ERR
    local action
    action="$(select_action)" || exit 0
    case "$action" in
        install) action_install ;;
        configure) action_configure ;;
        update) action_update ;;
        rollback) action_rollback ;;
        status) action_status ;;
        uninstall) action_uninstall ;;
        quit) exit 0 ;;
        *) die "未知操作：$action" ;;
    esac
}

main "$@"
