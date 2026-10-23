#!/bin/bash
# Publishes a version of ScreenShot on GitHub with automatic updates.
#   Tools/release.sh             build, zip, sign the update, tag, push and create the GitHub release
#   Tools/release.sh --dry-run   everything up to the zip and appcast in dist/, nothing tagged or published
#
# Versions are dates, YYMMDD.N in local time: the first release on 23 Oct 2026 is 261023.1, a second one that day
# 261023.2, and the next day starts again at .1. The number comes from the existing v<version> tags.
#
# Updates: the zip is signed with the EdDSA key in ~/.screenshot-release/sparkle_ed25519.key (exported from the login
# Keychain item made by Sparkle's generate_keys, account local.screenshot.app); the app checks it against SUPublicEDKey. appcast.xml is attached to every release, and
# the app reads it from releases/latest/download/appcast.xml.
#
# Notarization (optional, needs a paid Apple Developer account):
#   DEVELOPER_ID="Developer ID Application: Name (TEAMID)" NOTARY_PROFILE=<notarytool keychain profile> Tools/release.sh
# Create the profile once with: xcrun notarytool store-credentials <profile> --apple-id <email> --team-id <TEAMID>
set -euo pipefail
cd "$(dirname "$0")/.."

DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
REPO=Domi-X-in/ScreenShot
SPARKLE_BIN=.build/artifacts/sparkle/Sparkle/bin

if [ $DRY = 0 ]; then
    [ -z "$(git status --porcelain)" ] || { echo "Commit or stash your changes first."; exit 1; }
    [ "$(git branch --show-current)" = main ] || { echo "Release from main."; exit 1; }
    git fetch -q --tags origin
fi

# Today's date and the next number for it, after the releases already tagged today.
DAY=$(date +%y%m%d)
LAST=$(git tag -l "v$DAY.*" | sed "s/^v$DAY\.//" | sort -n | tail -1)
VERSION="$DAY.$(( ${LAST:-0} + 1 ))"
TAG="v$VERSION"
PREV=$(git tag -l 'v[0-9]*.[0-9]*' --sort=-version:refname | head -1)
echo "Releasing $VERSION${PREV:+ (previous: $PREV)}"

VERSION="$VERSION" ./build.sh

mkdir -p dist
ZIP="dist/ScreenShot-$VERSION.zip"
rm -f "$ZIP"
if [ -n "${DEVELOPER_ID:-}" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
    ditto -c -k --keepParent build/ScreenShot.app "$ZIP"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple build/ScreenShot.app
    rm -f "$ZIP"
fi
ditto -c -k --sequesterRsrc --keepParent build/ScreenShot.app "$ZIP"

# Sparkle signature and length for the appcast enclosure.
# The key file avoids a Keychain prompt on every release; without it, the Keychain item is used.
KEY_FILE="${SPARKLE_KEY_FILE:-$HOME/.screenshot-release/sparkle_ed25519.key}"
if [ -f "$KEY_FILE" ]; then
    SIG=$("$SPARKLE_BIN/sign_update" --ed-key-file "$KEY_FILE" "$ZIP")
else
    SIG=$("$SPARKLE_BIN/sign_update" --account local.screenshot.app "$ZIP")
fi
[[ "$SIG" == *edSignature* ]] || { echo "Signing the update failed: $SIG"; exit 1; }

# Release notes: commit subjects since the previous release.
if [ -n "$PREV" ]; then RANGE="$PREV..HEAD"; else RANGE="HEAD"; fi
NOTES=$(git log --no-merges --format='- %s' $RANGE | head -40)
NOTES_HTML=$(printf '%s\n' "$NOTES" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's|^- \(.*\)$|<li>\1</li>|')

cat > dist/appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>ScreenShot</title>
    <link>https://github.com/$REPO</link>
    <item>
      <title>Version $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[<ul>
$NOTES_HTML
</ul>]]></description>
      <enclosure url="https://github.com/$REPO/releases/download/$TAG/ScreenShot-$VERSION.zip" type="application/octet-stream" $SIG/>
    </item>
  </channel>
</rss>
XML

echo "Built $ZIP and dist/appcast.xml"
if [ $DRY = 1 ]; then echo "Dry run: nothing tagged or published."; exit 0; fi

git tag -a "$TAG" -m "ScreenShot $VERSION"
git push origin main "$TAG"
INSTALL=$(cat <<'MD'
**Install**

1. Unzip and move **ScreenShot** to Applications, then open it.
2. The app isn't notarized by Apple yet, so macOS says *"ScreenShot.app" Not Opened*. Click **Done** (not Move to Trash).
3. Open **System Settings › Privacy & Security**, scroll to **Security** and click **Open Anyway** next to the ScreenShot message, then confirm. The button shows for about an hour after the blocked launch; if it's gone, open the app again.

Or, in Terminal: `xattr -dr com.apple.quarantine /Applications/ScreenShot.app`

Right-click › Open no longer skips this check on macOS 15 and later. You only do this once: later versions install themselves (menu bar icon › Check for Updates).
MD
)
gh release create "$TAG" "$ZIP" dist/appcast.xml --repo "$REPO" --title "ScreenShot $VERSION" \
    --notes "$(printf '%s\n\n## Changes\n%s\n' "$INSTALL" "$NOTES")"
echo "Released $TAG: https://github.com/$REPO/releases/tag/$TAG"
