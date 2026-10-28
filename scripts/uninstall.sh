#!/bin/bash
# 卸载 hebiu：退出程序、删掉 Claude Code、Codex 里带 #hebiu 标记的钩子（其他钩子不动）、取消开机自启。
# 加 --purge 会同时删除 ~/.hebiu（台词配置、日志、备份）
set -euo pipefail
BUNDLE_ID=${BUNDLE_ID:-io.github.hebiu}
launchctl bootout "gui/$(id -u)/$BUNDLE_ID" 2>/dev/null || true   # 先停启动项，否则结束进程后会被拉起
pkill -f "Hebiu.app/Contents/MacOS/Hebiu" 2>/dev/null || true
rm -rf "$HOME/Applications/Hebiu.app"
rm -f "$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
LINK="$HOME/.local/bin/hebiu"
[ -L "$LINK" ] && [[ "$(readlink "$LINK")" == */bin/hebiu ]] && rm -f "$LINK"
python3 - <<'PY'
import json, os, shutil, stat, time
os.makedirs(os.path.expanduser("~/.hebiu/backup"), exist_ok=True)
for tool, path in (("claude", "~/.claude/settings.json"), ("codex", "~/.codex/hooks.json")):
    path = os.path.expanduser(path)
    if not os.path.exists(path):
        continue
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    mode = stat.S_IMODE(os.stat(path).st_mode)
    shutil.copy2(path, os.path.expanduser(f"~/.hebiu/backup/{tool}-{os.path.basename(path)}.before-uninstall.{time.strftime('%Y%m%d-%H%M%S')}"))
    removed = 0
    hooks = data.get("hooks", {})
    for event in list(hooks):
        kept = []
        for entry in hooks[event]:
            inner = [h for h in entry.get("hooks", []) if "#hebiu" not in h.get("command", "")]
            removed += len(entry.get("hooks", [])) - len(inner)
            if inner:
                entry["hooks"] = inner
                kept.append(entry)
        if kept:
            hooks[event] = kept
        else:
            del hooks[event]
    tmp = path + ".hebiu-tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    json.load(open(tmp, encoding="utf-8"))
    os.chmod(tmp, mode)
    os.replace(tmp, path)
    print(f"{tool}: removed hebiu hooks: {removed}")
PY
if [ "${1:-}" = "--purge" ]; then rm -rf "$HOME/.hebiu"; echo "removed ~/.hebiu"; fi
echo "done. 程序文件夹（这个仓库）没有删，需要的话手动删除。"
