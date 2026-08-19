#!/usr/bin/env bash
set -Eeuo pipefail

readonly TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/core/common.sh
source "$TEST_ROOT/lib/core/common.sh"
# shellcheck source=lib/core/config.sh
source "$TEST_ROOT/lib/core/config.sh"

config_defaults
MODEL_PATH=/models/test.gguf
validate_config

if (MODEL_PATH=/models/test.bin; validate_config >/dev/null 2>&1); then
    printf 'test-config: FAIL（接受了非 GGUF 文件）\n' >&2
    exit 1
fi

if (SERVER_PORT=70000; validate_config >/dev/null 2>&1); then
    printf 'test-config: FAIL（接受了无效端口）\n' >&2
    exit 1
fi

if (MODEL_PATH=relative/model.gguf; validate_config >/dev/null 2>&1); then
    printf 'test-config: FAIL（接受了相对模型路径）\n' >&2
    exit 1
fi

printf 'test-config: PASS\n'
