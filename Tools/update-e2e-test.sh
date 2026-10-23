#!/bin/bash
# End-to-end test of automatic updates: an "old" copy of the app (test bundle id, so the real app's settings and
# permissions are untouched) reads an appcast from a local server, downloads a newer signed build, verifies its
# EdDSA signature, and installs it when it quits. Passes if the copy on disk is the new version afterwards.
#   --tampered   the appcast carries a signature for different bytes: the update must be refused.
set -euo pipefail
cd "$(dirname "$0")/.."
PORT=8765
ID=local.screenshot.updatetest
W=$(mktemp -d)
SP=.build/artifacts/sparkle/Sparkle/bin
TAMPERED=0; [ "${1:-}" = "--tampered" ] && TAMPERED=1
KEY="${SPARKLE_KEY_FILE:-$HOME/.screenshot-release/sparkle_ed25519.key}"
trap 'kill $SERVER 2>/dev/null || true; defaults delete $ID >/dev/null 2>&1 || true; rm -rf "$W"' EXIT

./build.sh >/dev/null
make_copy() { # dest, version, build
    ditto build/ScreenShot.app "$1"
    local plist="$1/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $ID" -c "Set :CFBundleShortVersionString $2" -c "Set :CFBundleVersion $3" \
        -c "Set :SUFeedURL http://127.0.0.1:$PORT/appcast.xml" "$plist"
    /usr/libexec/PlistBuddy -c "Add :SUAutomaticallyUpdate bool true" "$plist"
    codesign --force --sign - --requirements "=designated => identifier \"$ID\"" "$1"
}
mkdir -p "$W/old" "$W/new" "$W/srv"
make_copy "$W/old/ScreenShot.app" 261023.9 261023.9 >/dev/null 2>&1
make_copy "$W/new/ScreenShot.app" 261023.10 261023.10 >/dev/null 2>&1
ditto -c -k --sequesterRsrc --keepParent "$W/new/ScreenShot.app" "$W/srv/new.zip"
SIG=$("$SP/sign_update" --ed-key-file "$KEY" "$W/srv/new.zip")
if [ $TAMPERED = 1 ]; then
    # A valid signature, but of other bytes (as if the zip had been swapped on the server).
    ditto -c -k --keepParent "$W/old/ScreenShot.app" "$W/other.zip"
    OTHER=$("$SP/sign_update" --ed-key-file "$KEY" "$W/other.zip" | grep -o 'sparkle:edSignature="[^"]*"')
    SIG="$OTHER $(echo "$SIG" | grep -o 'length="[0-9]*"')"
fi
cat > "$W/srv/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel><title>test</title>
    <item><title>261023.10</title><sparkle:version>261023.10</sparkle:version><sparkle:shortVersionString>261023.10</sparkle:shortVersionString>
      <enclosure url="http://127.0.0.1:$PORT/new.zip" type="application/octet-stream" $SIG/></item>
  </channel>
</rss>
XML
(cd "$W/srv" && exec python3 -m http.server $PORT --bind 127.0.0.1 >"$W/server.log" 2>&1) &
SERVER=$!

# Not a first launch (so Sparkle checks right away), checks allowed, no Screen Recording prompt for the test id.
defaults write $ID SUHasLaunchedBefore -bool true
defaults write $ID SUEnableAutomaticChecks -bool true
defaults write $ID SUAutomaticallyUpdate -bool true
defaults write $ID askedScreenRecording -bool true
sleep 1
open -n "$W/old/ScreenShot.app"
echo "Old app (261023.9) running; waiting for it to download the update…"
for _ in $(seq 1 60); do grep -q "GET /new.zip" "$W/server.log" 2>/dev/null && break; sleep 1; done
grep -q "GET /appcast.xml" "$W/server.log" && echo "PASS the app read the appcast" || echo "FAIL the app never read the appcast"
grep -q "GET /new.zip" "$W/server.log" && echo "PASS the app downloaded the update" || echo "FAIL the app never downloaded the update"
sleep 6 # let Sparkle verify and stage it
osascript -e "tell application id \"$ID\" to quit" >/dev/null 2>&1 || true
for _ in $(seq 1 $([ $TAMPERED = 1 ] && echo 15 || echo 40)); do
    v=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$W/old/ScreenShot.app/Contents/Info.plist" 2>/dev/null || echo "?")
    [ "$v" = 261023.10 ] && break
    sleep 1
done
pkill -f "$W/old/ScreenShot.app" 2>/dev/null || true
if [ $TAMPERED = 1 ]; then
    if [ "$v" = 261023.9 ]; then echo "PASS an update whose signature doesn't match was refused (still $v)"; exit 0; fi
    echo "FAIL a tampered update was installed ($v)"; exit 1
fi
if [ "$v" = 261023.10 ]; then
    echo "PASS the update was verified and installed: the app on disk is now $v"
    codesign --verify "$W/old/ScreenShot.app" && echo "PASS the installed app's signature is valid"
else
    echo "FAIL the app on disk is still $v"; exit 1
fi
