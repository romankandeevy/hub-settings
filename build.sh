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
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Подпись постоянным локальным сертификатом, если он есть: с ad-hoc подписью macOS после каждой
# пересборки забывает выданные доступы (Рабочий стол, камера, микрофон) и молча их не даёт.
SIGN_ID="-"
security find-identity -v -p codesigning 2>/dev/null | grep -q "Local Dev Signing" && SIGN_ID="Local Dev Signing"
codesign --force --sign "$SIGN_ID" "$APP"
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
