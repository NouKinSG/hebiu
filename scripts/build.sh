#!/bin/bash
# 编译并打包成 build/Hebiu.app。默认同时编 Apple 芯片和 Intel 两份再合成一个通用程序；
# ARCH=native 只编本机架构（更快，开发时用）
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/Hebiu.app
VERSION=$(cat VERSION)
BUNDLE_ID=${BUNDLE_ID:-io.github.hebiu}

if [ "${ARCH:-universal}" = "native" ]; then
  swift build -c release --product Hebiu
  BIN=$(swift build -c release --product Hebiu --show-bin-path)/Hebiu
else
  for triple in arm64-apple-macosx13.0 x86_64-apple-macosx13.0; do
    swift build -c release --product Hebiu --triple "$triple"
  done
  mkdir -p build
  BIN=build/Hebiu-universal
  lipo -create -output "$BIN" \
    "$(swift build -c release --triple arm64-apple-macosx13.0 --show-bin-path)/Hebiu" \
    "$(swift build -c release --triple x86_64-apple-macosx13.0 --show-bin-path)/Hebiu"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Hebiu"
cp -R Resources/characters "$APP/Contents/Resources/characters"
cp icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>Hebiu</string>
  <key>CFBundleDisplayName</key><string>Hebiu</string>
  <key>CFBundleExecutable</key><string>Hebiu</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>HebiuSourceDir</key><string>$PWD</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSCalendarsUsageDescription</key><string>把今天的会议放进待办，开始前提醒你（只读，打开「日历」来源时才会用）</string>
  <key>NSCalendarsFullAccessUsageDescription</key><string>把今天的会议放进待办，开始前提醒你（只读，打开「日历」来源时才会用）</string>
  <key>NSRemindersUsageDescription</key><string>把没完成的提醒事项放进待办（只读，打开「提醒事项」来源时才会用）</string>
  <key>NSMicrophoneUsageDescription</key><string>点麦克风跟她说话时听你说（只在你点的时候）</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>把你说的话转成文字发给她；支持时只在本机识别</string>
  <key>NSRemindersFullAccessUsageDescription</key><string>把没完成的提醒事项放进待办（只读，打开「提醒事项」来源时才会用）</string>
</dict>
</plist>
PLIST
# 本机自签名，避免系统每次启动都弹「无法验证开发者」
codesign --force --deep --sign - "$APP" >/dev/null
echo "built $APP ($VERSION, $(lipo -archs "$APP/Contents/MacOS/Hebiu"))"
