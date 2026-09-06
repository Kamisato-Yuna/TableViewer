#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${TABLEVIEWER_CODE_SIGN_IDENTITY:?Set the same signing identity used for the source app}"
SOURCE="${TABLEVIEWER_LOCALIZATION_SOURCE:-$PWD/dist/TableViewer.app/Contents}"
APP="$PWD/.build/localization/LocalizationProbe.app"
mkdir -p "$APP/Contents/MacOS"
ditto "$SOURCE"/Helpers "$APP/Contents/Helpers"
ditto "$SOURCE"/Frameworks "$APP/Contents/Frameworks"
ditto "$SOURCE"/Resources "$APP/Contents/Resources"
xcrun swiftc -parse-as-library -module-cache-path .build/localization/ModuleCache Tests/LocalizationIntegration.swift -o "$APP/Contents/MacOS/LocalizationProbe"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>local.yuna.TableViewer.LocalizationProbe</string><key>CFBundleExecutable</key><string>LocalizationProbe</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleDevelopmentRegion</key><string>en</string><key>LSBackgroundOnly</key><true/></dict></plist>
PLIST
codesign --force --sign "$TABLEVIEWER_CODE_SIGN_IDENTITY" --options runtime --timestamp --entitlements TableViewer/Resources/TableViewer.entitlements "$APP"
: > "$PWD/.build/localization/worker-localization-output.log"
open -n -g -W --stdout "$PWD/.build/localization/worker-localization-output.log" --stderr "$PWD/.build/localization/worker-localization-error.log" "$APP"
cat .build/localization/worker-localization-output.log
python3 - <<'PYTEST'
from pathlib import Path
output = Path('.build/localization/worker-localization-output.log').read_text()
assert 'FAIL:' not in output, output
for language in ('en', 'zh-Hans'):
    assert 'PASS: signed sandbox worker language ' + language in output, output
PYTEST
