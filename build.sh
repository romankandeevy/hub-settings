#!/bin/bash
# Сборка Hub Settings.app. Нужны только Command Line Tools (xcode-select --install).
#
#   ./build.sh          собрать build/Hub Settings.app
#   ./build.sh run      собрать и запустить отсюда (для разработки)
#   ./build.sh install  собрать, положить в ~/Applications и запустить
set -euo pipefail
cd "$(dirname "$0")"
APP="build/Hub Settings.app"

echo "==> swift build"
swift build -c release --product HubSettings
BIN="$(swift build -c release --show-bin-path)/HubSettings"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/HubSettings"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "==> готово: $APP"

case "${1:-}" in
run)
    pkill -x HubSettings 2>/dev/null && sleep 0.5 || true
    open "$APP"
    ;;
install)
    DEST="$HOME/Applications"
    mkdir -p "$DEST"
    pkill -x HubSettings 2>/dev/null && sleep 0.5 || true
    rm -rf "$DEST/Hub Settings.app"
    cp -R "$APP" "$DEST/"
    echo "==> установлено: $DEST/Hub Settings.app"
    open "$DEST/Hub Settings.app"
    ;;
esac
