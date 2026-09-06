#!/usr/bin/env bash
# Run feature checks via LaunchServices in a real, separately identified App Sandbox.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/.build/reliability/SandboxTests.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources" .build/reliability
SOURCE="${TABLEVIEWER_SANDBOX_SOURCE:-$PWD/.build/Xcode/Build/Products/Debug/TableViewer.app/Contents}"
ditto "$SOURCE/Frameworks" "$APP/Contents/Frameworks"
cp "$SOURCE/Helpers/TableViewerShell" "$APP/Contents/Helpers/"
cp TableViewer/Resources/MongoShell.js "$APP/Contents/Resources/"
xcrun clang -target arm64-apple-macos26.0 -c Native/MongoBridge.c -I .build/include -o .build/reliability/SandboxBridge.o
xcrun swiftc -parse-as-library -swift-version 5 -target arm64-apple-macos26.0 -module-cache-path .build/reliability/ModuleCache \
  -import-objc-header Native/TableViewer-Bridging-Header.h -I .build/include/postgresql \
  -L .build/lib -Xlinker -rpath -Xlinker '@executable_path/../Frameworks' \
  -lsqlite3 -lpq -lmongoc2 -lbson2 -framework JavaScriptCore \
  TableViewer/Models/DatabaseModels.swift TableViewer/Models/ReplicaSetModels.swift TableViewer/Models/AgentModels.swift \
  TableViewer/Services/DatabaseEngine.swift TableViewer/Services/MongoShellRuntime.swift TableViewer/Services/ShellSession.swift \
  TableViewer/Services/OpenAICompatibleClient.swift Tests/FeatureIntegration.swift .build/reliability/SandboxBridge.o -o "$APP/Contents/MacOS/SandboxTests"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.yuna.TableViewer.SandboxTests</string>
<key>CFBundleName</key><string>TableViewer Sandbox Tests</string>
<key>CFBundleExecutable</key><string>SandboxTests</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSBackgroundOnly</key><true/>
</dict></plist>
PLIST
SIGNING_OPTIONS=(--force --sign "${TABLEVIEWER_SANDBOX_IDENTITY:--}")
if [[ "${TABLEVIEWER_SANDBOX_IDENTITY:--}" != - ]]; then
  SIGNING_OPTIONS+=(--options runtime)
  /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.yuna.TableViewer.SandboxSignedTests' "$APP/Contents/Info.plist"
fi
codesign "${SIGNING_OPTIONS[@]}" --entitlements TableViewer/Resources/TableViewer.entitlements "$APP"
codesign --verify --deep --strict "$APP"
LOG="$PWD/.build/reliability/sandbox-output.log"
: > "$LOG"
open -n -g -W --stdout "$LOG" --stderr "$PWD/.build/reliability/sandbox-error.log" \
  --env TABLEVIEWER_SANDBOX_TEST=1 \
  --env "TABLEVIEWER_REPLICA_PORT=$TABLEVIEWER_REPLICA_PORT" \
  --env "TABLEVIEWER_MOCK_API=$TABLEVIEWER_MOCK_API" "$APP"
cat "$LOG"
rg -q 'ALL V0.2 FEATURE CHECKS PASSED' "$LOG"
