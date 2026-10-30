#!/usr/bin/env bash
# 专注核心与应用整合回归；使用隔离测试数据，不触达用户历史或偏好。
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/test-focus-core.sh
swift test --filter FocusIntegrationRegression
