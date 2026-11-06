#!/usr/bin/env bash
# Signs and exports an installable iPad/iPhone IPA from the Flutter iOS build.
#
# All four inputs are required. A partial configuration fails with the missing
# variable names instead of publishing something that looks installable and is
# not.
set -Eeuo pipefail

: "${IOS_CERTIFICATE_BASE64:?IOS_CERTIFICATE_BASE64 is required to sign an IPA}"
: "${IOS_CERTIFICATE_PASSWORD:?IOS_CERTIFICATE_PASSWORD is required to sign an IPA}"
: "${IOS_PROVISIONING_PROFILE_BASE64:?IOS_PROVISIONING_PROFILE_BASE64 is required to sign an IPA}"
: "${IOS_EXPORT_OPTIONS_PLIST_BASE64:?IOS_EXPORT_OPTIONS_PLIST_BASE64 is required to sign an IPA}"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work="$(mktemp -d)"
keychain="$work/mindpocket-signing.keychain-db"
keychain_password="$(openssl rand -hex 24)"
profile_dir="$HOME/Library/MobileDevice/Provisioning Profiles"

cleanup() {
  security delete-keychain "$keychain" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT

echo "Importing signing identity"
printf '%s' "$IOS_CERTIFICATE_BASE64" | base64 --decode > "$work/certificate.p12"
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 3600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$work/certificate.p12" -k "$keychain" -P "$IOS_CERTIFICATE_PASSWORD" \
  -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
  -k "$keychain_password" "$keychain" >/dev/null
security list-keychains -d user -s "$keychain" "$(security default-keychain -d user | tr -d ' "')"

echo "Installing provisioning profile"
mkdir -p "$profile_dir"
printf '%s' "$IOS_PROVISIONING_PROFILE_BASE64" | base64 --decode > "$work/profile.mobileprovision"
cp "$work/profile.mobileprovision" "$profile_dir/mindpocket.mobileprovision"

echo "Exporting signed IPA"
printf '%s' "$IOS_EXPORT_OPTIONS_PLIST_BASE64" | base64 --decode > "$work/ExportOptions.plist"
version="$(sed -nE 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+)(\+([0-9]+))?[[:space:]]*$/\1/p' "$root/pubspec.yaml" | head -1)"
build="$(sed -nE 's/^version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\+([0-9]+)[[:space:]]*$/\1/p' "$root/pubspec.yaml" | head -1)"
build="${build:-0}"

xcodebuild -workspace "$root/ios/Runner.xcworkspace" \
  -scheme Runner -configuration Release \
  -archivePath "$work/MindPocket.xcarchive" \
  -destination 'generic/platform=iOS' \
  archive

xcodebuild -exportArchive \
  -archivePath "$work/MindPocket.xcarchive" \
  -exportOptionsPlist "$work/ExportOptions.plist" \
  -exportPath "$work/export"

ipa="$(find "$work/export" -maxdepth 1 -name '*.ipa' -print -quit)"
if [[ -z "$ipa" ]]; then
  echo "Xcode did not export an IPA; check the export options and provisioning profile." >&2
  exit 1
fi

mkdir -p "$root/dist"
output="$root/dist/MindPocket-${version}+${build}-ios-signed.ipa"
cp "$ipa" "$output"
printf '%s\t%s\t%s\n' "$(basename "$output")" "$(wc -c < "$output" | tr -d ' ')" \
  "$(shasum -a 256 "$output" | cut -d' ' -f1)"
