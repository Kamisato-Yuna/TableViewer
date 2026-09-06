#!/usr/bin/env bash
# Run after the final DMG has been signed, notarized and stapled.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:-dist/TableViewer.app}"
TOOLS="${TABLEVIEWER_SPARKLE_TOOLS:-$PWD/.build/Xcode/SourcePackages/artifacts/sparkle/Sparkle/bin}"
ACCOUNT="${TABLEVIEWER_SPARKLE_ACCOUNT:-local.yuna.TableViewer.updates}"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
PUBLIC_KEY=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist")
SIGNING_KEY=$("$TOOLS/generate_keys" --account "$ACCOUNT" -p)
if [[ "$PUBLIC_KEY" != "$SIGNING_KEY" ]]; then
  echo "Sparkle public key does not match this app's update signing account." >&2
  exit 1
fi
DMG="dist/TableViewer-${VERSION}-macOS-arm64.dmg"
STAGING=$(mktemp -d "$PWD/dist/.appcast.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
cp "$DMG" "$STAGING/"
"$TOOLS/generate_appcast" --account "$ACCOUNT" --maximum-deltas 0 \
  --download-url-prefix "https://github.com/Kamisato-Yuna/TableViewer/releases/download/v${VERSION}/" \
  --link "https://github.com/Kamisato-Yuna/TableViewer/releases/tag/v${VERSION}" \
  --full-release-notes-url "https://github.com/Kamisato-Yuna/TableViewer/releases/tag/v${VERSION}" \
  "$STAGING"
cp "$STAGING/appcast.xml" dist/appcast.xml
echo "Generated: dist/appcast.xml (upload alongside the final DMG)"
