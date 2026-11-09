#!/usr/bin/env bash
# Builds "Cleaner for xDev.app" and a DMG into build/.
# Signing:
# - If the build keychain exists (CLEANER_KEYCHAIN, default ~/Library/Keychains/cleaner-build.keychain-db) and its
#   password file (CLEANER_KEYCHAIN_PASSWORD_FILE, default ~/cleaner-secrets/keychain-password), the app is signed
#   with "Developer ID Application" from that keychain, without any prompt. Neither file is in the repo.
# - Otherwise it is signed ad-hoc. macOS ties Full Disk Access to the signature, so an ad-hoc build has to be
#   granted again after each rebuild.
# - SIGN_IDENTITY overrides the identity ("-" forces ad-hoc).
# Notarizing for public release is scripts/release.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="Cleaner for xDev"
command -v xcodegen >/dev/null || { echo "XcodeGen is required: brew install xcodegen" >&2; exit 1; }
xcodegen generate --quiet
xcodebuild -project Cleaner.xcodeproj -scheme Cleaner -configuration Release -derivedDataPath build/dd \
  CODE_SIGNING_ALLOWED=NO build -quiet

keychain="${CLEANER_KEYCHAIN:-$HOME/Library/Keychains/cleaner-build.keychain-db}"
password_file="${CLEANER_KEYCHAIN_PASSWORD_FILE:-$HOME/cleaner-secrets/keychain-password}"
sign_args=(--timestamp=none)
if [ -f "$keychain" ] && [ -f "$password_file" ]; then
  security unlock-keychain -p "$(cat "$password_file")" "$keychain"
  identity="${SIGN_IDENTITY:-Developer ID Application}"
  if [ "$identity" != "-" ]; then sign_args=(--keychain "$keychain" --timestamp); fi
else
  identity="${SIGN_IDENTITY:--}"
fi

rm -rf "build/$NAME.app"
ditto "build/dd/Build/Products/Release/$NAME.app" "build/$NAME.app"
if ! codesign --force --options runtime "${sign_args[@]}" --sign "$identity" "build/$NAME.app"; then
  echo "Could not sign with \"$identity\". Signing ad-hoc." >&2
  identity="-"; sign_args=(--timestamp=none)
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
if [ "$identity" != "-" ]; then codesign --force "${sign_args[@]}" --sign "$identity" "$dmg"; fi
rm -rf "$stage"
echo "App: build/$NAME.app"
echo "DMG: $dmg (signed with: ${identity%% (*})"
