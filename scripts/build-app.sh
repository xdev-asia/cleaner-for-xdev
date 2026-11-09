#!/usr/bin/env bash
# Builds "Cleaner for xDev.app" and a DMG into build/.
# Signing is set up by scripts/signing.sh: Developer ID from the build keychain when present, ad-hoc otherwise.
# macOS ties Full Disk Access to the signature, so an ad-hoc build has to be granted again after each rebuild.
# BUILD_DMG=0 skips the DMG. Notarized release builds: scripts/release.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="Cleaner for xDev"
command -v xcodegen >/dev/null || { echo "XcodeGen is required: brew install xcodegen" >&2; exit 1; }
xcodegen generate --quiet
xcodebuild -project Cleaner.xcodeproj -scheme Cleaner -configuration Release -derivedDataPath build/dd \
  CODE_SIGNING_ALLOWED=NO build -quiet

source scripts/signing.sh

rm -rf "build/$NAME.app"
ditto "build/dd/Build/Products/Release/$NAME.app" "build/$NAME.app"
if ! codesign --force --options runtime "${sign_args[@]}" --sign "$identity" "build/$NAME.app"; then
  echo "Could not sign with \"$identity\". Signing ad-hoc." >&2
  identity="-"; sign_args=(--timestamp=none)
  codesign --force --options runtime --timestamp=none --sign - "build/$NAME.app"
fi
codesign --verify --strict "build/$NAME.app"

echo "App: build/$NAME.app (signed with: ${identity%% (*})"
if [ "${BUILD_DMG:-1}" != "0" ]; then echo "DMG: $(SIGN_IDENTITY="$identity" scripts/make-dmg.sh "build/$NAME.app")"; fi
