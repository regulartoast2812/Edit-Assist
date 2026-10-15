#!/bin/bash
# Installs or updates Edit Assist to the newest build, beta or stable:
#   curl -fsSL https://raw.githubusercontent.com/regulartoast2812/Edit-Assist/main/install.sh | bash
# (--beta is still accepted and does the same.)
set -euo pipefail
REPO="regulartoast2812/Edit-Assist"
APP="Edit Assist.app"
DEST="$HOME/Applications"
# Update the copy where it already is: a copy someone moved to /Applications stays the one that opens, and no
# second copy (with its own permission entries) is left behind.
if [[ -d "/Applications/Edit Assist.app" && "$(defaults read "/Applications/Edit Assist.app/Contents/Info" CFBundleIdentifier 2>/dev/null)" == "com.crossian.editassist" && -w /Applications ]]; then
  DEST="/Applications"
fi
# The newest build: updates/beta.json names it (release.sh writes it for every beta and every stable
# release). A beta is a GitHub pre-release, which "latest" skips, so "latest" is only the fallback.
URL=$(curl -fsSL "https://raw.githubusercontent.com/$REPO/main/updates/beta.json?t=$(date +%s)" 2>/dev/null | sed -n 's/.*"url": *"\([^"]*\)".*/\1/p' || true)
[[ -n "$URL" ]] || URL="https://github.com/$REPO/releases/latest/download/Edit-Assist.zip"

[[ "$(uname)" == "Darwin" ]] || { echo "Edit Assist runs on macOS only." >&2; exit 1; }
major=$(sw_vers -productVersion | cut -d. -f1); minor=$(sw_vers -productVersion | cut -d. -f2)
if (( major < 14 || (major == 14 && minor < 2) )); then echo "Edit Assist needs macOS 14.2 or later." >&2; exit 1; fi

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
echo "Downloading Edit Assist…"
curl -fL --progress-bar "$URL" -o "$tmp/Edit-Assist.zip"
ditto -x -k "$tmp/Edit-Assist.zip" "$tmp"
[[ -d "$tmp/$APP" ]] || { echo "The download did not contain $APP." >&2; exit 1; }

# Quit a running copy so the new one is what opens.
if pgrep -x EditAssist >/dev/null; then
  osascript -e 'quit app id "com.crossian.editassist"' >/dev/null 2>&1 || true
  sleep 1; pkill -x EditAssist 2>/dev/null || true
fi
mkdir -p "$DEST"
rm -rf "$DEST/$APP"
ditto "$tmp/$APP" "$DEST/$APP"
xattr -dr com.apple.quarantine "$DEST/$APP" 2>/dev/null || true
echo "Installed $DEST/$APP"
echo "On first launch, allow Screen Recording and Accessibility when macOS asks (System Settings → Privacy & Security)."
open "$DEST/$APP"
