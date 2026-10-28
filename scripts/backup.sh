#!/bin/bash
# 备份你们的数据（台词设置、待办、来源脚本、提醒状态、人设、聊天记录和她的记忆、习惯、心情、随手记、重要日子、小统计），换电脑时用 restore.sh 恢复。
# 不含日志和事件文件。用法：scripts/backup.sh [输出目录，默认桌面]
set -euo pipefail
DATA="${HEBIU_HOME:-$HOME/.hebiu}"
OUT_DIR="${1:-$HOME/Desktop}"
OUT="$OUT_DIR/hebiu-backup-$(date +%Y%m%d-%H%M).tar.gz"
[ -d "$DATA" ] || { echo "没有 ${DATA}，没东西可备份" >&2; exit 1; }
cd "$DATA"
items=()
for f in hebiu.md todo.json state.json persona.md agent sources backup stats.json dates.json dates-state.json habits.json notes.json moods.json characters; do [ -e "$f" ] && items+=("$f"); done
tar -czf "$OUT" "${items[@]}"
echo "备份好了：$OUT"
echo "包含：${items[*]}"
