#!/usr/bin/env bash
# Builds a notarized release: app signed with Developer ID, notarized and stapled, packed into a DMG that is
# notarized and stapled too. Needs the build keychain (see scripts/signing.sh) and a notarytool profile in it:
#   xcrun notarytool store-credentials cleaner-notary --apple-id <id> --team-id <team> --keychain <build keychain>
# NOTARY_PROFILE overrides the profile name.
set -euo pipefail
cd "$(dirname "$0")/.."
NAME="Cleaner for xDev"
APP="build/$NAME.app"
profile="${NOTARY_PROFILE:-cleaner-notary}"

source scripts/signing.sh
[ "$identity" != "-" ] || { echo "No Developer ID: the build keychain is missing." >&2; exit 1; }

notarize() {
  local file="$1" out
  echo "Notarizing ${file}..."
  out=$(xcrun notarytool submit "$file" --keychain-profile "$profile" --keychain "$keychain" --wait --output-format json)
  local id status
  id=$(plutil -extract id raw - <<<"$out")
  status=$(plutil -extract status raw - <<<"$out")
  if [ "$status" != "Accepted" ]; then
    echo "Notarization $status ($id):" >&2
    xcrun notarytool log "$id" --keychain-profile "$profile" --keychain "$keychain" >&2 || true
    exit 1
  fi
  echo "Accepted ($id)"
}

BUILD_DMG=0 scripts/build-app.sh
signature=$(codesign -dvv "$APP" 2>&1)
[[ "$signature" == *"Authority=Developer ID Application"* ]] \
  || { echo "$APP is not signed with Developer ID." >&2; exit 1; }

zip="build/notarize.zip"
rm -f "$zip"
ditto -c -k --keepParent "$APP" "$zip"
notarize "$zip"
rm -f "$zip"
xcrun stapler staple "$APP"

dmg=$(scripts/make-dmg.sh "$APP")
notarize "$dmg"
xcrun stapler staple "$dmg"

spctl -a -t exec -vv "$APP"
spctl -a -t open --context context:primary-signature -vv "$dmg"
shasum -a 256 "$dmg"
echo "Release: $dmg"
