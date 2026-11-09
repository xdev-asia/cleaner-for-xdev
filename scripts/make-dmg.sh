#!/usr/bin/env bash
# Usage: scripts/make-dmg.sh "build/Cleaner for xDev.app"
# Packs the app with an Applications link into build/CleanerForXDev-<version>.dmg and signs the DMG.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/signing.sh

app="$1"
name=$(basename "$app" .app)
version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$app/Contents/Info.plist")
stage=build/dmg
rm -rf "$stage" && mkdir -p "$stage"
ditto "$app" "$stage/$name.app"
ln -s /Applications "$stage/Applications"
dmg="build/CleanerForXDev-$version.dmg"
rm -f "$dmg"
hdiutil create -quiet -volname "$name" -srcfolder "$stage" -ov -format UDZO "$dmg"
if [ "$identity" != "-" ]; then codesign --force "${sign_args[@]}" --sign "$identity" "$dmg"; fi
rm -rf "$stage"
echo "$dmg"
