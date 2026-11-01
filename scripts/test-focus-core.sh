#!/usr/bin/env bash
#
# 编译并运行 FocusCore 的核心测试（无 XCTest 依赖）。
#
# 用法：bash scripts/test-focus-core.sh
#       或直接在任意目录执行：bash scripts/test-focus-core.sh
#
# 说明：本机沙箱禁止写 /var/folders 下的默认 clang module cache，
#       因此必须显式传入项目内的 -module-cache-path。
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

BUILD_DIR="$PROJECT_DIR/build"
MODULE_CACHE="$BUILD_DIR/ModuleCache"
TEST_BUILD_DIR="$BUILD_DIR/tests"
BINARY="$TEST_BUILD_DIR/TimerEngineTests"

if ! command -v swiftc >/dev/null 2>&1; then
    echo "error: 未找到 swiftc，请先安装 Xcode Command Line Tools。" >&2
    exit 1
fi

mkdir -p "$MODULE_CACHE" "$TEST_BUILD_DIR"

# 沙箱环境里 SDKROOT 可能未设置，显式解析 SDK 以免标准库加载失败。
# 若当前 xcode-select 指向的 Xcode 未接受许可，回退到 Command Line Tools。
SDK_PATH=""
if ! SDK_PATH="$(xcrun --show-sdk-path 2>/dev/null)"; then
    CLT="/Library/Developer/CommandLineTools"
    if [[ -x "$CLT/usr/bin/swiftc" ]]; then
        export DEVELOPER_DIR="$CLT"
        SDK_PATH="$(xcrun --show-sdk-path 2>/dev/null || true)"
    fi
fi

SWIFTC_FLAGS=(
    -swift-version 5
    -parse-as-library
    -module-cache-path "$MODULE_CACHE"
)
if [[ -n "$SDK_PATH" ]]; then
    SWIFTC_FLAGS+=(-sdk "$SDK_PATH")
fi

shopt -s nullglob
CORE_SOURCES=("$PROJECT_DIR"/Packages/FocusCore/Sources/FocusCore/*.swift)
TEST_SOURCES=("$PROJECT_DIR"/Checks/FocusCore/*.swift)
shopt -u nullglob

if (( ${#CORE_SOURCES[@]} == 0 )); then
    echo "error: Packages/FocusCore/Sources/FocusCore 下没有 .swift 源文件。" >&2
    exit 1
fi
if (( ${#TEST_SOURCES[@]} == 0 )); then
    echo "error: Checks/FocusCore 下没有 .swift 测试文件。" >&2
    exit 1
fi

echo "==> 编译核心与测试 (swiftc ${SWIFTC_FLAGS[*]})"
swiftc "${SWIFTC_FLAGS[@]}" \
    -o "$BINARY" \
    "${CORE_SOURCES[@]}" "${TEST_SOURCES[@]}"

echo "==> 运行测试：$BINARY"
"$BINARY"
