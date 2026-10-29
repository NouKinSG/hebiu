#!/usr/bin/env bash
# Standalone focus regression checks; all history/preferences use isolated test data.
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/test-focus-core.sh
swift build --product Hebiu
FOCUS_CHECK_BIN="$(swift build --show-bin-path)/Hebiu"
HEBIU_FOCUS_SELF_TEST=1 "$FOCUS_CHECK_BIN"
