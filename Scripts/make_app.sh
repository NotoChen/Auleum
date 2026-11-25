#!/bin/bash
# 组 Auleum.app：release 构建 + Info.plist + 签名。
#
# 默认 ad-hoc 签名，不依赖任何证书。代价：每次重新编译后，系统设置里的
# TCC 授权（设备控制和数据访问 / 录屏与系统录音）需要把 Auleum.app 取消再勾一次
# ——ad-hoc 的代码身份就是 cdhash，代码变了就匹配不上。
#
# 想避免反复授权，可以指定固定签名身份（可选）：
#   SIGN_ID="某张代码签名证书的 CN" INSTALL=1 ./Scripts/make_app.sh
set -euo pipefail

cd "$(dirname "$0")/.."
APP="build/Auleum.app"

SIGN_ID="${SIGN_ID:--}"

echo "==> swift build -c release"
swift build -c release --product auleumd
swift build -c release --product auleumctl

BIN_DIR="$(swift build -c release --show-bin-path)"

echo "==> assemble $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/auleumd" "$APP/Contents/MacOS/auleumd"
cp "$BIN_DIR/auleumctl" "$APP/Contents/MacOS/auleumctl"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/MenuBarIcon.png "$APP/Contents/Resources/MenuBarIcon.png"
cp Resources/MenuBarIcon@2x.png "$APP/Contents/Resources/MenuBarIcon@2x.png"
cp Resources/MenuBarIcon@3x.png "$APP/Contents/Resources/MenuBarIcon@3x.png"
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"

echo "==> codesign (identity: $SIGN_ID)"
if [ "$SIGN_ID" = "-" ]; then
    echo "    ad-hoc 签名：重装后需要在系统设置里把 Auleum.app 取消再勾一次。"
    codesign --force --sign - "$APP/Contents/MacOS/auleumctl"
    codesign --force --sign - "$APP"
else
    codesign --force --timestamp=none --sign "$SIGN_ID" "$APP/Contents/MacOS/auleumctl"
    codesign --force --timestamp=none --sign "$SIGN_ID" "$APP"
fi

echo "==> 签名信息"
codesign -dv "$APP" 2>&1 | grep -E "Identifier|Authority|Signature|TeamIdentifier" || true

echo "==> done: $APP"
file "$APP/Contents/MacOS/auleumd"
echo "启动：open $APP"
echo "CLI： $APP/Contents/MacOS/auleumctl status"

if [ "${INSTALL:-0}" = "1" ]; then
    echo "==> install to /Applications/Auleum.app"
    pkill -f "Auleum.app/Contents/MacOS/auleumd" 2>/dev/null || true
    sleep 1
    rm -rf /Applications/Auleum.app
    cp -R "$APP" /Applications/Auleum.app
    echo "已安装：/Applications/Auleum.app"
fi
