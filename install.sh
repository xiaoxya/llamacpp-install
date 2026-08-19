#!/usr/bin/env bash
set -Eeuo pipefail

readonly PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/core/common.sh
source "$PROJECT_ROOT/lib/core/common.sh"
# shellcheck source=lib/core/log.sh
source "$PROJECT_ROOT/lib/core/log.sh"
# shellcheck source=lib/core/ui.sh
source "$PROJECT_ROOT/lib/core/ui.sh"
# shellcheck source=lib/core/config.sh
source "$PROJECT_ROOT/lib/core/config.sh"
# shellcheck source=lib/core/state.sh
source "$PROJECT_ROOT/lib/core/state.sh"
# shellcheck source=lib/platform/detect.sh
source "$PROJECT_ROOT/lib/platform/detect.sh"
# shellcheck source=lib/backend/detect.sh
source "$PROJECT_ROOT/lib/backend/detect.sh"
# shellcheck source=lib/actions/preflight.sh
source "$PROJECT_ROOT/lib/actions/preflight.sh"
# shellcheck source=lib/actions/install.sh
source "$PROJECT_ROOT/lib/actions/install.sh"
# shellcheck source=lib/actions/update.sh
source "$PROJECT_ROOT/lib/actions/update.sh"
# shellcheck source=lib/actions/rollback.sh
source "$PROJECT_ROOT/lib/actions/rollback.sh"
# shellcheck source=lib/actions/status.sh
source "$PROJECT_ROOT/lib/actions/status.sh"
# shellcheck source=lib/actions/uninstall.sh
source "$PROJECT_ROOT/lib/actions/uninstall.sh"

usage() {
    cat <<'EOF'
llama.cpp Server 部署工具（框架预览版）

用法：
  sudo ./install.sh [选项]

选项：
  --dry-run        仅显示计划，不执行系统修改
  --ui MODE        指定界面：auto、whiptail、dialog、text
  --action ACTION  指定动作：install、update、rollback、status、uninstall
  -h, --help       显示帮助
EOF
}

parse_args() {
    while (($#)); do
        case "$1" in
            --dry-run) DRY_RUN=1 ;;
            --ui)
                (($# >= 2)) || die "--ui 缺少参数"
                UI_MODE="$2"
                shift
                ;;
            --action)
                (($# >= 2)) || die "--action 缺少参数"
                REQUESTED_ACTION="$2"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *) die "未知参数：$1" ;;
        esac
        shift
    done
}

select_action() {
    if [[ -n "${REQUESTED_ACTION:-}" ]]; then
        printf '%s\n' "$REQUESTED_ACTION"
        return
    fi

    ui_menu "选择操作" "install" \
        install "安装 / 重新配置" \
        update "更新到新版本" \
        rollback "回滚上一版本" \
        status "查看部署状态" \
        uninstall "卸载（保留模型）" \
        quit "退出"
}

main() {
    config_defaults
    parse_args "$@"
    ui_init "$UI_MODE"
    log_init
    trap 'on_error "$LINENO" "$?"' ERR

    detect_platform
    detect_hardware

    local action
    action="$(select_action)"
    case "$action" in
        install) action_install ;;
        update) action_update ;;
        rollback) action_rollback ;;
        status) action_status ;;
        uninstall) action_uninstall ;;
        quit) exit 0 ;;
        *) die "不支持的操作：$action" ;;
    esac
}

main "$@"
