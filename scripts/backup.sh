#!/bin/bash
# 备份用户数据、专注历史与快照、字体设置；换电脑用 restore.sh 恢复。
# 建议退出 Hebiu 后备份，保证数据库与计时快照一致。不含日志和事件文件。
# 用法：scripts/backup.sh [输出目录，默认桌面]
set -euo pipefail
DATA="${HEBIU_HOME:-$HOME/.hebiu}"
OUT_DIR="${1:-$HOME/Desktop}"
OUT="$OUT_DIR/hebiu-backup-$(date +%Y%m%d-%H%M).tar.gz"
[ -d "$DATA" ] || { echo "没有 ${DATA}，没东西可备份" >&2; exit 1; }
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
for f in hebiu.md todo.json state.json persona.md agent sources backup stats.json dates.json dates-state.json habits.json notes.json moods.json characters focus typography.json; do
  if [ -e "$DATA/$f" ]; then
    cp -R "$DATA/$f" "$STAGING/$f"
  fi
done
# 与 FocusModel.defaultDefaults 的隔离域命名一致，不改动用户原偏好。
DOMAIN=io.github.hebiu.focus
if [ -n "${HEBIU_HOME:-}" ]; then
  DATA_PATH=$(cd "$DATA" && pwd -L)
  DOMAIN="$DOMAIN.$(printf %s "$DATA_PATH" | base64 | tr '/+' '_-' | tr -d '\n')"
fi
rm -f "$STAGING/focus/preferences.plist"
if /usr/bin/defaults read "$DOMAIN" >/dev/null 2>&1; then
  mkdir -p "$STAGING/focus"
  /usr/bin/defaults export "$DOMAIN" "$STAGING/focus/preferences.plist" >/dev/null
fi
tar -czf "$OUT" -C "$STAGING" .
echo "备份好了：$OUT"
echo "包含：用户数据、专注数据与偏好、字体设置（如存在）"
