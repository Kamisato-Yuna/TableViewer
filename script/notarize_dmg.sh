#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${TABLEVIEWER_NOTARY_PROFILE:?Set the name of an existing notarytool Keychain profile}"
: "${TABLEVIEWER_CODE_SIGN_IDENTITY:?Set your Developer ID Application signing identity}"
APP="${1:-dist/TableViewer.app}"
./script/package_dmg.sh "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
DMG="dist/TableViewer-${VERSION}-macOS-arm64.dmg"
xcrun notarytool submit "$DMG" --keychain-profile "$TABLEVIEWER_NOTARY_PROFILE" \
  --wait --output-format json > dist/notary-dmg-result.json
python3 - <<'PY'
import json
result = json.load(open('dist/notary-dmg-result.json'))
print('DMG notarization:', result.get('status'), result.get('id'))
if result.get('status') != 'Accepted':
    raise SystemExit('DMG notarization was not accepted. Inspect the submission log before distributing.')
PY
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
echo "Notarized disk image: $DMG"
