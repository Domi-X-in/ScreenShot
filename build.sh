#!/bin/bash
# Builds ScreenShot.app with SwiftPM (no Xcode needed) and signs it ad hoc.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=build/ScreenShot.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ScreenShot "$APP/Contents/MacOS/ScreenShot"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# An ad hoc signature's default designated requirement is the cdhash, which changes on every build and makes
# macOS forget the Screen Recording / Accessibility grants. Pinning it to the bundle id keeps them across rebuilds.
codesign --force --sign - --requirements '=designated => identifier "local.screenshot.app"' "$APP"

echo "Built $APP"
