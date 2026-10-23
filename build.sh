#!/bin/bash
# Builds ScreenShot.app with SwiftPM (no Xcode needed) and signs it.
#   ./build.sh          → build/ScreenShot.app (release; the app to use)
#   ./build.sh debug    → build/debug/ScreenShot.app (includes the in-app self-tests and UI snapshots)
# The version comes from the VERSION file; the build number is the commit count, which Sparkle compares.
# With DEVELOPER_ID set (e.g. "Developer ID Application: Name (TEAMID)") the app is signed for notarization;
# otherwise it is signed ad hoc.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
swift build -c "$CONFIG"

if [ "$CONFIG" = "release" ]; then APP=build/ScreenShot.app; else APP=build/$CONFIG/ScreenShot.app; fi
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp ".build/$CONFIG/ScreenShot" "$APP/Contents/MacOS/ScreenShot"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Sparkle (automatic updates) ships as a framework next to the executable.
ditto ".build/$CONFIG/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/ScreenShot" 2>/dev/null || true

VERSION=$(tr -d '[:space:]' < VERSION)
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 1)
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"

if [ -n "${DEVELOPER_ID:-}" ]; then
    # Developer ID: sign Sparkle's helpers inside out, then the app, all with the hardened runtime (needed to notarize).
    SP="$APP/Contents/Frameworks/Sparkle.framework"
    sign() { codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$@"; }
    sign "$SP/Versions/B/XPCServices/Installer.xpc"
    sign --preserve-metadata=entitlements "$SP/Versions/B/XPCServices/Downloader.xpc"
    sign "$SP/Versions/B/Autoupdate"
    sign "$SP/Versions/B/Updater.app"
    sign "$SP"
    sign "$APP"
else
    # An ad hoc signature's default designated requirement is the cdhash, which changes on every build and makes
    # macOS forget the Screen Recording / Accessibility grants. Pinning it to the bundle id keeps them across rebuilds
    # (and lets the debug build reuse the grants for the live capture test).
    codesign --force --sign - --requirements '=designated => identifier "local.screenshot.app"' "$APP"
fi

echo "Built $APP ($VERSION, build $BUILD)"
