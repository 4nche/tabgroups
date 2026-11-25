#!/bin/bash
# Builds a release of Tab Groups: archive, sign with Developer ID, notarize, staple, zip.
#
#   scripts/release.sh                  full release
#   scripts/release.sh --skip-notarize  signed build only, for your own Mac
#
# Notarization reads its credentials from a keychain profile. Create it once with:
#   xcrun notarytool store-credentials tabgroups-notary --apple-id <apple id> --team-id <team id>
# Use another profile name by setting NOTARY_PROFILE.
set -euo pipefail

readonly SCHEME="TabGroups"
readonly PROJECT="TabGroups.xcodeproj"
readonly APP_NAME="TabGroups.app"
readonly NOTARY_PROFILE="${NOTARY_PROFILE:-tabgroups-notary}"

skip_notarize=false
for argument in "$@"; do
  case "$argument" in
    --skip-notarize) skip_notarize=true ;;
    *) echo "Unknown option: $argument" >&2; exit 2 ;;
  esac
done

cd "$(dirname "$0")/.."
readonly BUILD_DIR="$PWD/build"
readonly ARCHIVE="$BUILD_DIR/TabGroups.xcarchive"
readonly EXPORT_DIR="$BUILD_DIR/export"
readonly EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"

setting() {
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -showBuildSettings 2>/dev/null \
    | awk -v key="$1" '$1 == key { print $3; exit }'
}

version="$(setting MARKETING_VERSION)"
team="$(setting DEVELOPMENT_TEAM)"
if [[ -z "$version" || -z "$team" ]]; then
  echo "Could not read MARKETING_VERSION or DEVELOPMENT_TEAM from the project." >&2
  exit 1
fi
readonly ZIP="$BUILD_DIR/TabGroups-$version.zip"

if [[ "$skip_notarize" == false ]] && ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "No usable notarization profile named '$NOTARY_PROFILE'." >&2
  echo "Create it with: xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <apple id> --team-id $team" >&2
  echo "Or run with --skip-notarize for a build that is only signed." >&2
  exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Archiving Tab Groups $version"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" archive -quiet

cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$team</string>
  <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST

echo "==> Signing with Developer ID"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS" -quiet

readonly APP="$EXPORT_DIR/$APP_NAME"
codesign --verify --deep --strict "$APP"

ditto -c -k --keepParent "$APP" "$ZIP"

if [[ "$skip_notarize" == true ]]; then
  echo "==> Skipped notarization. Signed build: $ZIP"
  exit 0
fi

echo "==> Notarizing (this usually takes a few minutes)"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling"
xcrun stapler staple "$APP"
rm "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
spctl --assess --type execute --verbose "$APP"

echo "==> Done: $ZIP"
