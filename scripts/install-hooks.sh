#!/bin/bash
# 给 Claude Code 和 Codex 追加钩子，让 hebiu 知道它们在干什么；已经装过的、内容旧了的就地更新。
# 装了哪个接哪个（Claude 看 ~/.claude，Codex 看 ~/.codex）。
# 只动带 #hebiu 标记的条目；env、statusLine、其他钩子一概不动；改之前先备份。
set -euo pipefail
python3 - <<'PY'
import json, os, shutil, stat, time

backup_dir = os.path.expanduser("~/.hebiu/backup")
os.makedirs(backup_dir, exist_ok=True)
MARK = "#hebiu"

# 各家的事件 → hebiu 事件
TOOLS = {
    "claude": {
        "file": "~/.claude/settings.json",
        "home": "~/.claude",
        "events": {
            "SessionStart": "hello",
            "UserPromptSubmit": "working",
            "Notification": "wait",
            "Stop": "done",
            "PostToolUseFailure": "error",
            "StopFailure": "error",
        },
    },
    "codex": {
        "file": "~/.codex/hooks.json",
        "home": "~/.codex",
        "events": {
            "SessionStart": "hello",
            "UserPromptSubmit": "working",
            "PermissionRequest": "wait",
            "Stop": "done",
        },
    },
}

def command(tool, event):
    # 从交来的 JSON 里只取会话 ID（前 8 位）和项目文件夹名，好分清是哪个会话；不读对话内容。
    # 只往本地文件追加一行、什么都不输出，最后 true 保证永远返回成功
    read = ("j=$(cat); s=$(printf '%s' \"$j\" | sed -n 's/.*\"session_id\" *: *\"\\([^\"]*\\)\".*/\\1/p' | cut -c1-8); "
            "d=$(printf '%s' \"$j\" | sed -n 's/.*\"cwd\" *: *\"\\([^\"]*\\)\".*/\\1/p'); d=$(basename \"$d\" 2>/dev/null | tr ' ' '_'); ")
    write = f"printf '%s %s sid=%s proj=%s src={tool}\\n' \"$(date +%s)\" \"$e\" \"$s\" \"$d\" >> \"$HOME/.hebiu/events\"; "
    if tool == "claude" and event == "wait":
        # Claude 的 Notification 有两种：要你批准（permission）→ wait 喊你；只是闲了 60 秒等你回话 → nudge，不说话
        pick = "e=nudge; printf '%s' \"$j\" | grep -qi permission && e=wait; "
    else:
        pick = f"e={event}; "
    return "{ " + read + pick + write + "}" + f" 2>/dev/null; true {MARK}"

def install(tool, spec):
    path = os.path.expanduser(spec["file"])
    if not os.path.isdir(os.path.expanduser(spec["home"])):
        print(f"{tool}: 没装，跳过")
        return
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        mode = stat.S_IMODE(os.stat(path).st_mode)
        backup = os.path.join(backup_dir, f"{tool}-{os.path.basename(path)}.{time.strftime('%Y%m%d-%H%M%S')}")
        shutil.copy2(path, backup)
    else:
        data, mode, backup = {}, 0o644, None

    hooks = data.setdefault("hooks", {})
    added = []
    for their_event, pet_event in spec["events"].items():
        entries = hooks.setdefault(their_event, [])
        mine = [h for e in entries for h in e.get("hooks", []) if MARK in h.get("command", "")]
        if mine:
            for h in mine:
                if h.get("command") != command(tool, pet_event):
                    h["command"] = command(tool, pet_event)
                    added.append(their_event + "（更新）")
            continue
        entries.append({"hooks": [{"type": "command", "command": command(tool, pet_event)}]})
        added.append(their_event)

    tmp = path + ".hebiu-tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    json.load(open(tmp, encoding="utf-8"))          # 写出来的必须还是合法 JSON
    os.chmod(tmp, mode)
    os.replace(tmp, path)
    print(f"{tool}: {path}" + (f"（备份 {backup}）" if backup else "（新建）"))
    print(f"  added hooks: {added or 'none (already installed)'}")

for tool, spec in TOOLS.items():
    install(tool, spec)
PY
if [ -d "$HOME/.codex" ]; then
  echo "Codex：下次打开时会问要不要信任新钩子，选信任才生效"
fi
