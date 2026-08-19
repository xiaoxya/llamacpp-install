#!/usr/bin/env bash
set -Eeuo pipefail

readonly TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/core/common.sh
source "$TEST_ROOT/lib/core/common.sh"
# shellcheck source=lib/platform/detect.sh
source "$TEST_ROOT/lib/platform/detect.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT

printf '%s\n' 'ID=ubuntu' 'ID_LIKE=debian' 'PRETTY_NAME="Ubuntu Test"' > "$tmp_dir/ubuntu"
detect_os_from_file "$tmp_dir/ubuntu"
[[ "$DISTRO_ID" == ubuntu ]]
[[ "$PACKAGE_FAMILY" == apt ]]

printf '%s\n' 'ID=arch' 'PRETTY_NAME="Arch Linux"' > "$tmp_dir/arch"
detect_os_from_file "$tmp_dir/arch"
[[ "$DISTRO_ID" == arch ]]
[[ "$PACKAGE_FAMILY" == pacman ]]

printf '%s\n' 'ID=fedora' 'PRETTY_NAME="Fedora Test"' > "$tmp_dir/fedora"
detect_os_from_file "$tmp_dir/fedora"
[[ "$PACKAGE_FAMILY" == unsupported ]]

printf 'test-detection: PASS\n'
