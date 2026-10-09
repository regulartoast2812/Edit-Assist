#!/bin/zsh
# Builds a universal (Apple silicon + Intel) Edit Assist.app, zips it and publishes it as a GitHub
# release, which install.sh downloads. Usage: ./release.sh            build dist/Edit-Assist.zip
#                                           ./release.sh --publish  also create the GitHub release
set -euo pipefail
cd "${0:A:h}"
REPO="regulartoast2812/Edit-Assist"
APP="Edit Assist.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
STAGE=".build/release/$APP"

./test.sh > .build/test.log 2>&1 || { grep -E "FAIL|error:|Fatal" .build/test.log | head -20; echo "Tests failed; no release." >&2; exit 1; }

rm -rf .build/release dist; mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources" dist .build/module-cache
for arch in arm64 x86_64; do
  xcrun swiftc -target $arch-apple-macos14.2 -parse-as-library -O -module-cache-path .build/module-cache Helpers/CLIWorker.swift -o .build/release/CLIWorker-$arch
  xcrun swiftc -target $arch-apple-macos14.2 -swift-version 5 -parse-as-library -O -module-cache-path .build/module-cache Sources/*.swift -o .build/release/EditAssist-$arch
done
lipo -create .build/release/EditAssist-arm64 .build/release/EditAssist-x86_64 -output "$STAGE/Contents/MacOS/EditAssist"
lipo -create .build/release/CLIWorker-arm64 .build/release/CLIWorker-x86_64 -output "$STAGE/Contents/MacOS/CLIWorker"
cp Resources/Info.plist "$STAGE/Contents/Info.plist"
cp Resources/AppIcon.icns "$STAGE/Contents/Resources/AppIcon.icns"
# Ad-hoc signature: runs on any Mac without a developer account. macOS asks for Screen Recording and
# Accessibility on first launch; each new version is a new signature, so it asks again after an update.
codesign --force --sign - "$STAGE/Contents/MacOS/CLIWorker"
codesign --force --sign - --identifier com.crossian.editassist "$STAGE"
ditto -c -k --keepParent "$STAGE" dist/Edit-Assist.zip
echo "Built dist/Edit-Assist.zip (v$VERSION, $(lipo -archs "$STAGE/Contents/MacOS/EditAssist"))"

[[ "${1-}" == "--publish" ]] || exit 0
# The GitHub login git already uses, from the macOS keychain. Never printed.
TOKEN=$(printf "protocol=https\nhost=github.com\n\n" | git credential-osxkeychain get | sed -n 's/^password=//p')
[[ -n "$TOKEN" ]] || { echo "No GitHub login in the keychain; sign in with git first." >&2; exit 1; }
api() { curl -fsS -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" "$@"; }
TAG="v$VERSION"
git push origin HEAD
if api "https://api.github.com/repos/$REPO/releases/tags/$TAG" >/dev/null 2>&1; then
  echo "Release $TAG already exists; bump CFBundleShortVersionString in Resources/Info.plist first." >&2; exit 1
fi
ID=$(api -X POST "https://api.github.com/repos/$REPO/releases" \
  -d "{\"tag_name\":\"$TAG\",\"name\":\"Edit Assist $TAG\",\"target_commitish\":\"$(git rev-parse HEAD)\",\"body\":\"Install or update: curl -fsSL https://raw.githubusercontent.com/$REPO/main/install.sh | bash\"}" \
  | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
api -X POST -H "Content-Type: application/zip" --data-binary @dist/Edit-Assist.zip \
  "https://uploads.github.com/repos/$REPO/releases/$ID/assets?name=Edit-Assist.zip" >/dev/null
echo "Published $TAG: https://github.com/$REPO/releases/tag/$TAG"
