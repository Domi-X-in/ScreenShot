#!/bin/bash
# Runs the unit tests (swift test). With only the Command Line Tools installed (no Xcode), the Swift Testing
# macro plugin sits in a subfolder the compiler doesn't search, so point it there.
set -euo pipefail
cd "$(dirname "$0")/.."
EXTRA=()
PLUGINS=/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
if [ -d "$PLUGINS" ] && ! xcode-select -p 2>/dev/null | grep -q Xcode.app; then
    EXTRA=(-Xswiftc -plugin-path -Xswiftc "$PLUGINS")
fi
swift test ${EXTRA[@]+"${EXTRA[@]}"} "$@"
