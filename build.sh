#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"

APP="Edit Assist.app"
ID="com.crossian.editassist"
STAGE=".build/stage/$APP"
TARGET="$HOME/Applications/$APP"
IDENTITY="Edit Assist Local Signing"
KC="edit-assist-signing.keychain"
reveal=0
[[ "${1-}" == "--reveal" ]] && reveal=1

# Safeguard: nothing is installed unless every check passes and every recorded decision replays
# unchanged. --skip-tests exists for emergencies only; say so if you use it.
if [[ "${1-}" != "--skip-tests" && "${2-}" != "--skip-tests" ]]; then
  if ! ./test.sh > .build/test.log 2>&1; then
    grep -E "FAIL|error:|Fatal" .build/test.log | head -20 >&2
    echo "Tests failed; not installing. Full output: .build/test.log" >&2
    exit 1
  fi
  echo "$(grep -E 'checks passed' .build/test.log | tail -1) · $(grep -E 'recorded decisions' .build/test.log | tail -1)"
fi

./setup-signing.sh

rm -rf "$STAGE"
mkdir -p .build/module-cache "$STAGE/Contents/MacOS"
xcrun swiftc -parse-as-library -O -module-cache-path .build/module-cache Helpers/CLIWorker.swift -o "$STAGE/Contents/MacOS/CLIWorker"
xcrun swiftc -swift-version 5 -parse-as-library -O -module-cache-path .build/module-cache Sources/*.swift -o "$STAGE/Contents/MacOS/EditAssist"
cp Resources/Info.plist "$STAGE/Contents/Info.plist"
# The app icon, drawn by Tools/MakeIcon.swift (rerun it, then iconutil, to change the design).
mkdir -p "$STAGE/Contents/Resources"
cp Resources/AppIcon.icns "$STAGE/Contents/Resources/AppIcon.icns"

# A fixed identity keeps the designated requirement stable, so macOS permissions survive rebuilds.
if security find-certificate -c "$IDENTITY" "$KC" >/dev/null 2>&1 &&
   codesign --force --sign "$IDENTITY" --keychain "$KC" "$STAGE/Contents/MacOS/CLIWorker" 2>/dev/null &&
   codesign --force --sign "$IDENTITY" --keychain "$KC" --identifier "$ID" "$STAGE" 2>/dev/null; then
  :
else
  echo "WARNING: stable signing failed; falling back to ad-hoc. macOS permissions will reset on every build." >&2
  codesign --force --sign - "$STAGE/Contents/MacOS/CLIWorker"
  codesign --force --sign - --identifier "$ID" "$STAGE"
fi

# Quit the old copy first, so what relaunches is the build we just made.
if pgrep -x EditAssist >/dev/null; then
  osascript -e "quit app id \"$ID\"" 2>/dev/null || true
  for _ in {1..24}; do pgrep -x EditAssist >/dev/null || break; sleep 0.25; done
  pkill -x EditAssist 2>/dev/null || true
  sleep 0.3
fi

# Install where Finder, Spotlight and Launchpad can see it. Replace only our own bundle.
mkdir -p "$HOME/Applications"
if [[ -e "$TARGET" ]]; then
  installed=$(defaults read "$TARGET/Contents/Info" CFBundleIdentifier 2>/dev/null || echo "")
  [[ "$installed" == "$ID" ]] || { echo "Refusing to replace $TARGET: it is not Edit Assist." >&2; exit 1; }
  rm -rf "$TARGET"
fi
cp -R "$STAGE" "$TARGET"

# A second bundle would show up as a duplicate "Edit Assist" row in System Settings.
rm -rf "dist/$APP"
rmdir dist 2>/dev/null || true

open "$TARGET"
(( reveal )) && open -R "$TARGET"
echo "Installed and relaunched: $TARGET"
echo "Signature: $(codesign -dvvv "$TARGET" 2>&1 | grep -E '^Authority=' || echo 'ad-hoc')"
