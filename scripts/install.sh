#!/bin/bash
# 编译并安装到 ~/Applications，打开开机自启，然后启动
set -euo pipefail
BUNDLE_ID=${BUNDLE_ID:-io.github.hebiu}
cd "$(dirname "$0")/.."
scripts/build.sh
launchctl bootout "gui/$(id -u)/$BUNDLE_ID" 2>/dev/null || true   # 先停启动项，否则结束进程后会被拉起
pkill -f "Hebiu.app/Contents/MacOS/Hebiu" 2>/dev/null || true
sleep 0.5
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/Hebiu.app"
cp -R build/Hebiu.app "$HOME/Applications/Hebiu.app"
# 开机自启：启动项指向 ~/Applications 里的这份
cat > "$HOME/Library/LaunchAgents/$BUNDLE_ID.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$BUNDLE_ID</string>
  <key>ProgramArguments</key><array><string>$HOME/Applications/Hebiu.app/Contents/MacOS/Hebiu</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
PLIST
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
# 数据来源脚本：没有才放进去，不覆盖改过的（example.sh 只是模板，不装）
mkdir -p "$HOME/.hebiu/sources"
for f in datasources/*.sh; do
  name=$(basename "$f")
  [ "$name" = "example.sh" ] && continue
  [ -e "$HOME/.hebiu/sources/$name" ] || install -m 755 "$f" "$HOME/.hebiu/sources/$name"
done

# 命令行：~/.local/bin/hebiu 指向项目里的 bin/hebiu（那里已有别的同名文件就不动）
LINK="$HOME/.local/bin/hebiu"
if [ -d "$HOME/.local/bin" ] && { [ ! -e "$LINK" ] || [ -L "$LINK" ]; }; then
  ln -sf "$PWD/bin/hebiu" "$LINK"
  echo "command: $LINK"
fi
echo "installed: ~/Applications/Hebiu.app（开机自启已打开）"
