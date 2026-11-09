#!/usr/bin/env bash
# Builds the Mac App Store edition (target CleanerAppStore) into build/appstore/CleanerForXDev-<version>.pkg:
# signed with Apple Distribution, provisioning profile embedded, wrapped in an installer package signed with
# Mac Installer Distribution. With UPLOAD=1 it also uploads the package to App Store Connect.
#
# Nothing secret is in the repo. It needs:
#   - the build keychain (scripts/signing.sh) holding "Apple Distribution" and "3rd Party Mac Developer Installer"
#   - APPSTORE_PROFILE: the MAC_APP_STORE provisioning profile (default ~/cleaner-secrets/appstore/appstore.provisionprofile)
#   - for UPLOAD=1: ASC_KEY_ID and ASC_ISSUER_ID, with AuthKey_<ASC_KEY_ID>.p8 in ~/.appstoreconnect/private_keys
# BUILD_NUMBER overrides CURRENT_PROJECT_VERSION; every upload needs a higher one.
set -euo pipefail
cd "$(dirname "$0")/.."
NAME="Cleaner for xDev"
OUT=build/appstore
APP="$OUT/$NAME.app"
profile="${APPSTORE_PROFILE:-$HOME/cleaner-secrets/appstore/appstore.provisionprofile}"
[ -f "$profile" ] || { echo "Provisioning profile not found: $profile" >&2; exit 1; }

SIGN_IDENTITY="Apple Distribution" source scripts/signing.sh
[ "$identity" != "-" ] || { echo "The build keychain is missing." >&2; exit 1; }
installer_identity="3rd Party Mac Developer Installer"

command -v xcodegen >/dev/null || { echo "XcodeGen is required: brew install xcodegen" >&2; exit 1; }
xcodegen generate --quiet
build_args=()
[ -n "${BUILD_NUMBER:-}" ] && build_args+=("CURRENT_PROJECT_VERSION=$BUILD_NUMBER")
xcodebuild -project Cleaner.xcodeproj -scheme CleanerAppStore -configuration Release -derivedDataPath build/dd-store \
  CODE_SIGNING_ALLOWED=NO ${build_args[@]+"${build_args[@]}"} build -quiet

rm -rf "$OUT" && mkdir -p "$OUT"
ditto "build/dd-store/Build/Products/Release/$NAME.app" "$APP"
cp "$profile" "$APP/Contents/embedded.provisionprofile"

# The signature must carry the app and team identifiers from the profile, on top of the sandbox entitlements.
profile_plist="$OUT/profile.plist"
entitlements="$OUT/entitlements.plist"
security cms -D -i "$profile" > "$profile_plist"
cp AppStore/AppStore.entitlements "$entitlements"
for key in com.apple.application-identifier com.apple.developer.team-identifier; do
  value=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:$key" "$profile_plist")
  /usr/libexec/PlistBuddy -c "Add :$key string $value" "$entitlements"
done
rm "$profile_plist"

codesign --force --options runtime "${sign_args[@]}" --entitlements "$entitlements" --sign "$identity" "$APP"
codesign --verify --strict --deep "$APP"
codesign -d --entitlements - "$APP" 2>/dev/null | grep -q app-sandbox || { echo "The app is not sandboxed." >&2; exit 1; }
rm "$entitlements"

version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
build=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")
pkg="$OUT/CleanerForXDev-$version-$build.pkg"
productbuild --component "$APP" /Applications --sign "$installer_identity" --keychain "$keychain" "$pkg"
pkgutil --check-signature "$pkg" | head -3
echo "Package: $pkg ($version, build $build)"

if [ "${UPLOAD:-0}" = "1" ]; then
  : "${ASC_KEY_ID:?Set ASC_KEY_ID}" "${ASC_ISSUER_ID:?Set ASC_ISSUER_ID}"
  xcrun altool --validate-app -f "$pkg" -t macos --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
  xcrun altool --upload-app -f "$pkg" -t macos --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
fi
