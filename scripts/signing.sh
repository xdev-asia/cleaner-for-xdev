# Sourced by the build scripts. Sets $identity, $keychain and the $sign_args array.
# Uses "Developer ID Application" from the build keychain when it and its password file exist (neither is in the
# repo), ad-hoc otherwise. SIGN_IDENTITY overrides the identity ("-" forces ad-hoc).
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
