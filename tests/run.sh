#!/usr/bin/env bash
set -Eeuo pipefail

readonly TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly BASH_BIN="${BASH:-bash}"
"$BASH_BIN" "$TEST_DIR/test-detection.sh"
"$BASH_BIN" "$TEST_DIR/test-config.sh"
"$BASH_BIN" "$TEST_DIR/test-ui.sh"
