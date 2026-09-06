#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:-dist/TableViewer.app}"
codesign --verify --deep --strict "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
mkdir -p dist
DMG="$PWD/dist/TableViewer-${VERSION}-macOS-arm64.dmg"
STAGING=$(mktemp -d "$PWD/dist/.dmg.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/TableViewer.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname TableViewer -srcfolder "$STAGING" -format UDZO -fs HFS+ -ov "$DMG"
# CI can validate packaging without access to a developer's signing credentials.
if [[ -n "${TABLEVIEWER_CODE_SIGN_IDENTITY:-}" && "$TABLEVIEWER_CODE_SIGN_IDENTITY" != - ]]; then
  codesign --force --sign "$TABLEVIEWER_CODE_SIGN_IDENTITY" --timestamp "$DMG"
fi
hdiutil verify "$DMG"
echo "Disk image: $DMG"
