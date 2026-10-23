#!/bin/bash
# Runs the in-app self-tests (real windows, mouse and keyboard events) against the debug build.
#   Tools/integration-tests.sh          → editor, selection, text, callouts, info panels, appearance, defaults, auto-save
#   Tools/integration-tests.sh --live   → also real screen captures (needs Screen Recording allowed for ScreenShot)
set -uo pipefail
cd "$(dirname "$0")/.."
./build.sh debug > /dev/null || exit 1
APP="$PWD/build/debug/ScreenShot.app"
BIN="$APP/Contents/MacOS/ScreenShot"
WORK="$(mktemp -d)"
IMG="$WORK/sample.png"
# A sample screenshot to edit: the app icon is a handy 1024×1024 PNG.
cp Resources/AppIcon.png "$IMG"
FAILED=0

run_suite() { # name, env var
    local dir="$WORK/$1"; mkdir -p "$dir"
    env "$2=$IMG" "$BIN" -saveFolder "$dir" > "$dir/out.log" 2>&1 &
    local pid=$!
    for _ in $(seq 1 40); do sleep 0.5; kill -0 $pid 2>/dev/null || break; done
    kill $pid 2>/dev/null
    local pass fail
    pass=$(grep -c '^PASS' "$dir/out.log"); fail=$(grep -c '^FAIL' "$dir/out.log")
    printf "%-12s %3d passed  %d failed\n" "$1" "$pass" "$fail"
    grep '^FAIL' "$dir/out.log"
    if [ "$fail" -gt 0 ] || [ "$pass" -eq 0 ]; then FAILED=1; fi
}

for s in SELECT TEXT TEXTSTYLE CALLOUT INFO APPEARANCE DEFAULTS PHASE3 ONBOARDING SHAPES; do run_suite "$s" "SCREENSHOT_SELFTEST_$s"; done

# Auto-save and same-window switching work on two files in the save folder.
mkdir -p "$WORK/AUTOSAVE"; cp "$IMG" "$WORK/AUTOSAVE/a.png"; sleep 1; cp "$IMG" "$WORK/AUTOSAVE/b.png"
SCREENSHOT_SELFTEST_DIR="$WORK/AUTOSAVE" "$BIN" -saveFolder "$WORK/AUTOSAVE" > "$WORK/AUTOSAVE/out.log" 2>&1 &
pid=$!; for _ in $(seq 1 40); do sleep 0.5; kill -0 $pid 2>/dev/null || break; done; kill $pid 2>/dev/null
printf "%-12s %3d passed  %d failed\n" AUTOSAVE "$(grep -c '^PASS' "$WORK/AUTOSAVE/out.log")" "$(grep -c '^FAIL' "$WORK/AUTOSAVE/out.log")"
grep -q "SELFTEST OK" "$WORK/AUTOSAVE/out.log" || FAILED=1

if [ "${1:-}" = "--live" ]; then
    # Launched through Launch Services so the app's own Screen Recording permission applies.
    open -n -W "$APP" --env SCREENSHOT_SELFTEST_LIVE="$WORK/live.txt" --args -saveFolder "$WORK" &
    for _ in $(seq 1 120); do sleep 1; grep -q "LIVE SELFTEST" "$WORK/live.txt" 2>/dev/null && break; done
    printf "%-12s %3d passed  %d failed  %d skipped\n" LIVE "$(grep -c '^PASS' "$WORK/live.txt")" "$(grep -c '^FAIL' "$WORK/live.txt")" "$(grep -c '^SKIP' "$WORK/live.txt")"
    grep -E '^(FAIL|SKIP)' "$WORK/live.txt"
    grep -qE "LIVE SELFTEST (OK|SKIPPED)" "$WORK/live.txt" || FAILED=1
fi

echo "Logs: $WORK"
exit $FAILED
