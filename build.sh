#!/bin/bash
# Builds ScreenShot.app with SwiftPM (no Xcode needed) and signs it ad hoc.
#   ./build.sh          → build/ScreenShot.app (release; the app to use)
#   ./build.sh debug    → build/debug/ScreenShot.app (includes the in-app self-tests and UI snapshots)
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
swift build -c "$CONFIG"

if [ "$CONFIG" = "release" ]; then APP=build/ScreenShot.app; else APP=build/$CONFIG/ScreenShot.app; fi
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/ScreenShot" "$APP/Contents/MacOS/ScreenShot"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# An ad hoc signature's default designated requirement is the cdhash, which changes on every build and makes
# macOS forget the Screen Recording / Accessibility grants. Pinning it to the bundle id keeps them across rebuilds
# (and lets the debug build reuse the grants for the live capture test).
codesign --force --sign - --requirements '=designated => identifier "local.screenshot.app"' "$APP"

echo "Built $APP"
