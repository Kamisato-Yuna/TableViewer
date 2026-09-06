#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${TABLEVIEWER_NOTARY_PROFILE:?Set the name of an existing notarytool Keychain profile}"
APP="${1:-dist/TableViewer.app}"
codesign --verify --deep --strict "$APP"
mkdir -p dist
UPLOAD="dist/TableViewer-notary-upload.zip"
ditto -c -k --keepParent "$APP" "$UPLOAD"
xcrun notarytool submit "$UPLOAD" --keychain-profile "$TABLEVIEWER_NOTARY_PROFILE" \
  --wait --output-format json > dist/notary-result.json
python3 - <<'PY'
import json
result = json.load(open('dist/notary-result.json'))
print('Notarization:', result.get('status'), result.get('id'))
if result.get('status') != 'Accepted':
    raise SystemExit('Notarization was not accepted. Inspect the submission log before distributing.')
PY
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
ditto -c -k --keepParent "$APP" "dist/TableViewer-${VERSION}-macOS-arm64.zip"
echo "Notarized archive: dist/TableViewer-${VERSION}-macOS-arm64.zip"
