#!/bin/bash
# 本机用 AI 生图 / 改图（mflux，Apple 芯片）。准备环境和模型见 README.md
# 用法：gen.sh <输出.png> <种子> "<提示词>" [参考图...]
#   有参考图：照着参考图改（改表情、改动作）；没有：从文字生成
# 环境变量：ART_HOME（默认 ~/hebiu-art）、MODEL（默认 $ART_HOME/model）、FAMILY（flux3 或 flux2，默认 flux3）、
#           STEPS（默认 12）、SIZE（默认 768）
set -euo pipefail
ART_HOME="${ART_HOME:-$HOME/hebiu-art}"
MODEL="${MODEL:-$ART_HOME/model}"
out=$1; seed=$2; prompt=$3; shift 3
[ -f "$out" ] && { echo "已经有了，跳过：$out（想重出就先删掉）"; exit 0; }
[ -d "$MODEL" ] || { echo "找不到模型：$MODEL（见 README.md 的「准备环境」）" >&2; exit 1; }
mkdir -p "$(dirname "$out")"
FAMILY="${FAMILY:-flux3}"
if [ $# -gt 0 ]; then
  cmd=("mflux-generate-$FAMILY-edit" --image-paths "$@")
else
  cmd=("mflux-generate-$FAMILY")
fi
echo "$(date +%T) 开始 $out"
# HF_HUB_OFFLINE：模型已经在本地，不让它去联网检查（不设会卡住）
HF_HUB_OFFLINE=1 HF_HOME="$ART_HOME/hf" "$ART_HOME/venv/bin/${cmd[0]}" "${cmd[@]:1}" \
  --model "$MODEL" --prompt "$prompt" \
  --width "${SIZE:-768}" --height "${SIZE:-768}" --steps "${STEPS:-12}" --seed "$seed" --output "$out"
echo "$(date +%T) 完成 $out"
