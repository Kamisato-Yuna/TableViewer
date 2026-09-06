#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -f .build/lib/libmongoc2.2.dylib ]]; then python3 script/bootstrap_drivers.py; fi
IDENTITY="${TABLEVIEWER_CODE_SIGN_IDENTITY:-Apple Development}"
SIGNING_OPTIONS=("CODE_SIGN_IDENTITY=$IDENTITY")
if [[ "$IDENTITY" != - ]]; then SIGNING_OPTIONS+=("OTHER_CODE_SIGN_FLAGS=--timestamp"); fi
if [[ -n "${TABLEVIEWER_DEVELOPMENT_TEAM:-}" ]]; then SIGNING_OPTIONS+=("DEVELOPMENT_TEAM=$TABLEVIEWER_DEVELOPMENT_TEAM"); fi
xcodebuild -project TableViewer.xcodeproj -scheme TableViewer -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/Xcode -quiet \
  "${SIGNING_OPTIONS[@]}" build
mkdir -p dist
STAGING=$(mktemp -d "$PWD/dist/.package.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
ditto .build/Xcode/Build/Products/Release/TableViewer.app "$STAGING/TableViewer.app"
# Verify before replacing the generated output; never merge an old notarization ticket.
codesign --verify --deep --strict "$STAGING/TableViewer.app"
rm -rf "$PWD/dist/TableViewer.app"
mv "$STAGING/TableViewer.app" "$PWD/dist/TableViewer.app"
echo "Packaged: $PWD/dist/TableViewer.app"
