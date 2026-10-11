#!/bin/bash
# Builds Rebar.app into ./build. Usage: scripts/build-app.sh [debug|release] [--dmg] [--install]
# --dmg also makes build/Rebar.dmg with the usual drag-to-Applications layout.
# --install also copies it to /Applications, a stable place for the login item to point at.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=release
INSTALL=false
DMG=false
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=true ;;
        --dmg) DMG=true ;;
        *) CONFIG="$arg" ;;
    esac
done
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Rebar"

APP="build/Rebar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Rebar"
cp Support/Info.plist "$APP/Contents/Info.plist"
# Compiles the Icon Composer document into Assets.car (Liquid Glass, light/dark/tinted) plus AppIcon.icns for older readers.
xcrun actool Support/AppIcon.icon --compile "$APP/Contents/Resources" --platform macosx \
    --minimum-deployment-target 26.0 --app-icon AppIcon --output-partial-info-plist build/icon-partial.plist >/dev/null
# A stable identity keeps the keychain's "Always Allow" valid across rebuilds; ad-hoc signing changes every build.
IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')"
codesign --force --sign "${IDENTITY:--}" "$APP" >/dev/null

echo "Built $APP"

if $DMG; then
    STAGE="$(mktemp -d)"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    rm -f build/Rebar.dmg
    hdiutil create -volname Rebar -srcfolder "$STAGE" -format UDZO -quiet build/Rebar.dmg
    rm -rf "$STAGE"
    codesign --force --sign "${IDENTITY:--}" build/Rebar.dmg >/dev/null
    echo "Built build/Rebar.dmg"
fi

if $INSTALL; then
    DEST="/Applications/Rebar.app"
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    echo "Installed $DEST"
fi
