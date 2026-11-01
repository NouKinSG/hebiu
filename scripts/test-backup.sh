#!/bin/bash
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
TEST_DIR=$(mktemp -d /private/tmp/hebiu-backup-roundtrip.XXXXXX)
SOURCE_DATA="$TEST_DIR/source"
TARGET_DATA="$TEST_DIR/target"
mkdir -p "$SOURCE_DATA/focus" "$TARGET_DATA" "$TEST_DIR/out"
SOURCE_DOMAIN="io.github.hebiu.focus.$(printf %s "$SOURCE_DATA" | base64 | tr '/+' '_-' | tr -d '\n')"
TARGET_DOMAIN="io.github.hebiu.focus.$(printf %s "$TARGET_DATA" | base64 | tr '/+' '_-' | tr -d '\n')"
cleanup() {
  defaults delete "$SOURCE_DOMAIN" >/dev/null 2>&1 || true
  defaults delete "$TARGET_DOMAIN" >/dev/null 2>&1 || true
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT
printf 'history-fixture' > "$SOURCE_DATA/focus/FocusOnYourself.store"
printf '{"scale":1.15}' > "$SOURCE_DATA/typography.json"
defaults write "$SOURCE_DOMAIN" foy.focusTitle -string 'backup-test'
defaults write "$SOURCE_DOMAIN" foy.countdownSeconds -int 2700
HEBIU_HOME="$SOURCE_DATA" bash "$REPO/scripts/backup.sh" "$TEST_DIR/out"
HEBIU_HOME="$TARGET_DATA" bash "$REPO/scripts/restore.sh" "$TEST_DIR"/out/*.tar.gz
cmp "$SOURCE_DATA/focus/FocusOnYourself.store" "$TARGET_DATA/focus/FocusOnYourself.store"
cmp "$SOURCE_DATA/typography.json" "$TARGET_DATA/typography.json"
[ "$(defaults read "$TARGET_DOMAIN" foy.focusTitle)" = backup-test ]
[ "$(defaults read "$TARGET_DOMAIN" foy.countdownSeconds)" = 2700 ]
echo 'PASS: focus database, font settings and isolated preferences round trip'
