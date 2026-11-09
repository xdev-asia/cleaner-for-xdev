#!/usr/bin/env bash
# Builds "Cleaner for xDev.app" and a DMG into build/.
# Signs ad-hoc by default (no keychain prompt). macOS ties Full Disk Access to the signature, so an ad-hoc
# build has to be granted again after each rebuild. SIGN_IDENTITY="Apple Development" (or a full identity name)
# signs with a certificate instead; codesign then asks for the login keychain password, which is the Mac login
# password. Not for public release: see scripts/release.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="Cleaner for xDev"
command -v xcodegen >/dev/null || { echo "XcodeGen is required: brew install xcodegen" >&2; exit 1; }
xcodegen generate --quiet
xcodebuild -project Cleaner.xcodeproj -scheme Cleaner -configuration Release -derivedDataPath build/dd \
  CODE_SIGNING_ALLOWED=NO build -quiet

identity="${SIGN_IDENTITY:--}"
rm -rf "build/$NAME.app"
ditto "build/dd/Build/Products/Release/$NAME.app" "build/$NAME.app"
if ! codesign --force --options runtime --timestamp=none --sign "$identity" "build/$NAME.app"; then
  echo "Could not sign with \"$identity\" (keychain locked? run: security unlock-keychain). Signing ad-hoc." >&2
  identity="-"
  codesign --force --options runtime --timestamp=none --sign - "build/$NAME.app"
fi
codesign --verify --strict "build/$NAME.app"

version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "build/$NAME.app/Contents/Info.plist")
stage=build/dmg
rm -rf "$stage" && mkdir -p "$stage"
ditto "build/$NAME.app" "$stage/$NAME.app"
ln -s /Applications "$stage/Applications"
dmg="build/CleanerForXDev-$version.dmg"
rm -f "$dmg"
hdiutil create -quiet -volname "$NAME" -srcfolder "$stage" -ov -format UDZO "$dmg"
if [ "$identity" != "-" ]; then codesign --force --timestamp=none --sign "$identity" "$dmg"; fi
rm -rf "$stage"
echo "App: build/$NAME.app"
echo "DMG: $dmg (signed with: ${identity%% (*})"
