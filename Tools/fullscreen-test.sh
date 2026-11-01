#!/bin/bash
# Puts a small helper app in full screen, then checks ScreenShot's windows over it, with and without the Dock icon.
# Run it by hand: the screen changes Space for about half a minute. Needs a built debug app (./build.sh debug).
set -uo pipefail
cd "$(dirname "$0")/.."
BIN="$PWD/build/debug/ScreenShot.app/Contents/MacOS/ScreenShot"
WORK="$(mktemp -d)"

cat > "$WORK/probe.swift" <<'EOF'
import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let win = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 600, height: 400), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
win.collectionBehavior = [.fullScreenPrimary]
win.makeKeyAndOrderFront(nil)
app.activate()
DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { win.toggleFullScreen(nil) }
app.run()
EOF
swiftc "$WORK/probe.swift" -o "$WORK/FullScreenProbe" || exit 1

"$WORK/FullScreenProbe" &
PROBE=$!
trap 'kill $PROBE 2>/dev/null' EXIT
sleep 3
for dock in YES NO; do
    echo "== showInDock $dock"
    SCREENSHOT_SELFTEST_SPACES=1 "$BIN" -showInDock "$dock" -saveFolder "$WORK" 2>&1 | grep -E '^(PASS|FAIL|INFO|SPACES)'
    # Back to the helper's full-screen Space for the next run.
    osascript -e 'tell application "System Events" to set frontmost of (first process whose unix id is '"$PROBE"') to true' 2>/dev/null
    sleep 2
done
