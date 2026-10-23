#!/usr/bin/env bash
set -euo pipefail
umask 077

: "${GARAGE_DISTRIBUTION_CERTIFICATE_P12_BASE64:?required}"
: "${GARAGE_DISTRIBUTION_CERTIFICATE_PASSWORD:?required}"
: "${GARAGE_APPSTORE_PROFILE_BASE64:?required}"
: "${GARAGE_KEYCHAIN_PASSWORD:?required}"

keychain="$RUNNER_TEMP/garage-release.keychain-db"
certificate="$RUNNER_TEMP/garage-distribution.p12"
profile="$RUNNER_TEMP/garage.mobileprovision"
printf '%s' "$GARAGE_DISTRIBUTION_CERTIFICATE_P12_BASE64" | base64 --decode > "$certificate"
printf '%s' "$GARAGE_APPSTORE_PROFILE_BASE64" | base64 --decode > "$profile"
security create-keychain -p "$GARAGE_KEYCHAIN_PASSWORD" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$GARAGE_KEYCHAIN_PASSWORD" "$keychain"
security import "$certificate" -P "$GARAGE_DISTRIBUTION_CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -k "$keychain"
security list-keychain -d user -s "$keychain"
security set-key-partition-list -S apple-tool:,apple: -s -k "$GARAGE_KEYCHAIN_PASSWORD" "$keychain"

profile_plist="$RUNNER_TEMP/garage-profile.plist"
security cms -D -i "$profile" > "$profile_plist"
certificate_der="$RUNNER_TEMP/garage-certificate.der"
openssl pkcs12 -legacy -in "$certificate" -clcerts -nokeys -passin env:GARAGE_DISTRIBUTION_CERTIFICATE_PASSWORD |
  openssl x509 -outform DER > "$certificate_der"
python3 - "$profile_plist" "$certificate_der" <<'PY'
import plistlib
import sys

with open(sys.argv[1], 'rb') as source:
    profile = plistlib.load(source)
with open(sys.argv[2], 'rb') as source:
    certificate = source.read()
if certificate not in profile.get('DeveloperCertificates', []):
    raise SystemExit('The provisioning profile does not contain the supplied distribution certificate.')
PY
uuid=$(/usr/libexec/PlistBuddy -c 'Print UUID' "$profile_plist")
team=$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "$profile_plist")
app_id=$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$profile_plist")
cloudkit=$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.icloud-container-environment:0' "$profile_plist" 2>/dev/null || true)
[[ "$team" == 3SRDN9365G && "$app_id" == 3SRDN9365G.com.schoren.garage ]] || {
  echo 'The App Store profile does not belong to Garage and team 3SRDN9365G.' >&2
  exit 1
}
[[ "$cloudkit" == Production ]] || {
  echo 'The App Store profile does not enable CloudKit Production.' >&2
  exit 1
}
mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"
cp "$profile" "$HOME/Library/MobileDevice/Provisioning Profiles/$uuid.mobileprovision"
echo "GARAGE_PROFILE_UUID=$uuid" >> "$GITHUB_ENV"
