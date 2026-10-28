#!/bin/bash
# 从 backup.sh 打的包恢复到 ~/.hebiu。恢复前会把现有的整个 ~/.hebiu 挪到一边，不会直接覆盖
# 用法：scripts/restore.sh <hebiu-backup-xxx.tar.gz>
set -euo pipefail
FILE="${1:?用法：scripts/restore.sh <备份文件>}"
DATA="${HEBIU_HOME:-$HOME/.hebiu}"
[ -f "$FILE" ] || { echo "找不到 $FILE" >&2; exit 1; }
tar -tzf "$FILE" >/dev/null || { echo "$FILE 不是有效的备份包" >&2; exit 1; }
if [ -d "$DATA" ]; then
  OLD="$DATA.before-restore-$(date +%Y%m%d-%H%M%S)"
  mv "$DATA" "$OLD"
  echo "原来的数据挪到了：$OLD"
fi
mkdir -p "$DATA"
tar -xzf "$FILE" -C "$DATA"
touch "$DATA/events"
echo "恢复好了：${DATA}（hebiu 会自动读到新的待办和设置；没反应就从菜单退出再打开）"
