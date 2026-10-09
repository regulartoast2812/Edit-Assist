#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
TARGET="$HOME/Applications/Edit Assist.app"
if [[ -x "$TARGET/Contents/MacOS/EditAssist" ]]; then open "$TARGET"; else ./build.sh; fi
