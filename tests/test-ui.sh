#!/usr/bin/env bash
set -Eeuo pipefail

readonly TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/core/common.sh
source "$TEST_ROOT/lib/core/common.sh"
# shellcheck source=lib/core/ui.sh
source "$TEST_ROOT/lib/core/ui.sh"

tmp_file="$(mktemp)"
trap 'rm -f -- "$tmp_file"' EXIT

UI_MODE=text
selected="$(ui_menu "选择操作" install \
    install "安装 / 重新配置" \
    status "查看部署状态" 2>"$tmp_file")"

[[ "$selected" == install ]]
grep -q '^┌─ llama.cpp 部署 · 选择操作$' "$tmp_file"
grep -q '^│ 1  安装 / 重新配置$' "$tmp_file"

printf 'test-ui: PASS\n'
