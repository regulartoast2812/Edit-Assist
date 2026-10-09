#!/bin/bash
# Installs or updates Edit Assist from the latest GitHub release:
#   curl -fsSL https://raw.githubusercontent.com/regulartoast2812/Edit-Assist/main/install.sh | bash
set -euo pipefail
REPO="regulartoast2812/Edit-Assist"
APP="Edit Assist.app"
DEST="$HOME/Applications"
URL="https://github.com/$REPO/releases/latest/download/Edit-Assist.zip"

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
