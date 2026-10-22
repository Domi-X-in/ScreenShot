#!/bin/bash
# Runs the live capture self-test: real screen captures of test windows the app draws.
# It is launched through Launch Services (open) so the app's own Screen Recording permission applies.
# Usage: Tools/live-capture-test.sh            → prints PASS/FAIL/SKIP lines, exits non-zero on failure.
set -u
cd "$(dirname "$0")/.."
OUT="$(mktemp -d)"
./build.sh > /dev/null || exit 1
open -n -W "$PWD/build/ScreenShot.app" --env SCREENSHOT_SELFTEST_LIVE="$OUT/result.txt" --args -saveFolder "$OUT" &
for _ in $(seq 1 120); do
    sleep 1
    grep -q "LIVE SELFTEST" "$OUT/result.txt" 2>/dev/null && break
done
cat "$OUT/result.txt" 2>/dev/null || { echo "No result: is Screen Recording allowed for ScreenShot?"; exit 1; }
echo "Captured images: $OUT"
grep -q "LIVE SELFTEST OK" "$OUT/result.txt"
