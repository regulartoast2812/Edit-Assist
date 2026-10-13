#!/bin/zsh
# Builds a universal (Apple silicon + Intel) Edit Assist.app, zips it and publishes it as a GitHub
# release, which install.sh and the app's updater download.
# Usage: ./release.sh                    build dist/Edit-Assist.zip
#        ./release.sh --publish          publish a stable release (updates/stable.json)
#        ./release.sh --publish --beta   publish a beta for testers (a pre-release; updates/beta.json)
# Every release needs a new CFBundleVersion (build number) in Resources/Info.plist: the updater compares it.
set -euo pipefail
cd "${0:A:h}"
REPO="regulartoast2812/Edit-Assist"
APP="Edit Assist.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" Resources/Info.plist)
STAGE=".build/release/$APP"
publish=0; channel=stable
for arg in "$@"; do
  case "$arg" in --publish) publish=1 ;; --beta) channel=beta ;; *) echo "Unknown option $arg" >&2; exit 1 ;; esac
done
TAG="v$VERSION"; [[ $channel == beta ]] && TAG="v$VERSION-beta.$BUILD"

# Safeguards: what testers get is exactly what is committed and passed every check and recorded decision.
if (( publish )); then
  [[ -z "$(git status --porcelain --untracked-files=no)" ]] || { echo "Commit your changes first: a release is built only from committed code." >&2; exit 1; }
fi
./test.sh > .build/test.log 2>&1 || { grep -E "FAIL|error:|Fatal" .build/test.log | head -20; echo "Tests failed; no release." >&2; exit 1; }
echo "$(grep -E 'checks passed' .build/test.log | tail -1) · $(grep -E 'recorded decisions' .build/test.log | tail -1)"

rm -rf .build/release dist; mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources" dist .build/module-cache
for arch in arm64 x86_64; do
  xcrun swiftc -target $arch-apple-macos14.2 -parse-as-library -O -module-cache-path .build/module-cache Helpers/CLIWorker.swift -o .build/release/CLIWorker-$arch
  xcrun swiftc -target $arch-apple-macos14.2 -swift-version 5 -parse-as-library -O -module-cache-path .build/module-cache Sources/*.swift -o .build/release/EditAssist-$arch
done
lipo -create .build/release/EditAssist-arm64 .build/release/EditAssist-x86_64 -output "$STAGE/Contents/MacOS/EditAssist"
lipo -create .build/release/CLIWorker-arm64 .build/release/CLIWorker-x86_64 -output "$STAGE/Contents/MacOS/CLIWorker"
cp Resources/Info.plist "$STAGE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :EditAssistChannel $channel" "$STAGE/Contents/Info.plist"
cp Resources/AppIcon.icns "$STAGE/Contents/Resources/AppIcon.icns"
# The whole-body pose model (Resources/Models/NOTICE.md), compiled for Core ML.
xcrun coremlcompiler compile Resources/Models/WholeBodyPose.mlpackage "$STAGE/Contents/Resources" >/dev/null
# Its licence travels with it (Apache-2.0 asks for the licence and the notice of changes).
cp Resources/Models/NOTICE.md "$STAGE/Contents/Resources/WholeBodyPose-NOTICE.md"
cp Resources/Models/LICENSE-Apache-2.0.txt "$STAGE/Contents/Resources/WholeBodyPose-LICENSE.txt"
# Ad-hoc signature: runs on any Mac without a developer account. macOS asks for Screen Recording and
# Accessibility on first launch; each new version is a new signature, so it asks again after an update.
codesign --force --sign - "$STAGE/Contents/MacOS/CLIWorker"
codesign --force --sign - --identifier com.crossian.editassist "$STAGE"
ditto -c -k --keepParent "$STAGE" dist/Edit-Assist.zip
echo "Built dist/Edit-Assist.zip ($TAG, build $BUILD, $channel, $(lipo -archs "$STAGE/Contents/MacOS/EditAssist"))"

(( publish )) || exit 0
# The GitHub login git already uses, from the macOS keychain. Never printed.
TOKEN=$(printf "protocol=https\nhost=github.com\n\n" | git credential-osxkeychain get | sed -n 's/^password=//p')
[[ -n "$TOKEN" ]] || { echo "No GitHub login in the keychain; sign in with git first." >&2; exit 1; }
api() { curl -fsS -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" "$@"; }
git push origin HEAD
if api "https://api.github.com/repos/$REPO/releases/tags/$TAG" >/dev/null 2>&1; then
  echo "Release $TAG already exists; bump CFBundleVersion (and the version if it changed) in Resources/Info.plist first." >&2; exit 1
fi
FLAG=""; [[ $channel == beta ]] && FLAG=" -s -- --beta"
TITLE="Edit Assist $VERSION"; [[ $channel == beta ]] && TITLE="Edit Assist $VERSION beta (build $BUILD)"
ID=$(api -X POST "https://api.github.com/repos/$REPO/releases" \
  -d "{\"tag_name\":\"$TAG\",\"name\":\"$TITLE\",\"prerelease\":$([[ $channel == beta ]] && echo true || echo false),\"target_commitish\":\"$(git rev-parse HEAD)\",\"body\":\"Install or update: curl -fsSL https://raw.githubusercontent.com/$REPO/main/install.sh | bash$FLAG\"}" \
  | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
api -X POST -H "Content-Type: application/zip" --data-binary @dist/Edit-Assist.zip \
  "https://uploads.github.com/repos/$REPO/releases/$ID/assets?name=Edit-Assist.zip" >/dev/null
# The channel file the app's updater and install.sh read. A stable release also serves beta testers.
mkdir -p updates
manifest="{\"version\": \"$VERSION\", \"build\": $BUILD, \"channel\": \"$channel\", \"tag\": \"$TAG\", \"url\": \"https://github.com/$REPO/releases/download/$TAG/Edit-Assist.zip\"}"
echo "$manifest" > "updates/$channel.json"
[[ $channel == stable ]] && echo "$manifest" > updates/beta.json
git add updates && git commit -q -m "Release $TAG" && git push -q origin HEAD
echo "Published $TAG: https://github.com/$REPO/releases/tag/$TAG"
