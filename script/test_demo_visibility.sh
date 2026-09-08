#!/usr/bin/env bash
set -euo pipefail
# No implicit ports: absent TV040_*_PORT skips those engines. Caller owns fixture servers.
cd "$(dirname "$0")/.."
cd "$(pwd -P)"
mkdir -p .build/workbench040/DemoRegression.app/Contents/MacOS
xcrun clang -target arm64-apple-macos26.0 -c Native/MongoBridge.c -I .build/include -o .build/workbench040/MongoBridge.o
xcrun swiftc -parse-as-library -swift-version 5 -target arm64-apple-macos26.0 -module-cache-path .build/workbench040/ModuleCache \
  -import-objc-header Native/TableViewer-Bridging-Header.h -I .build/include/postgresql \
  -L .build/lib -Xlinker -rpath -Xlinker "$PWD/.build/lib" -lsqlite3 -lpq -lmongoc2 -lbson2 -framework JavaScriptCore \
  TableViewer/Models/DatabaseModels.swift TableViewer/Models/ReplicaSetModels.swift \
  TableViewer/Models/SQLScript.swift TableViewer/Models/ScriptLibrary.swift TableViewer/Models/SchemaMetadata.swift \
  TableViewer/Models/AgentModels.swift TableViewer/Models/AgentSession.swift TableViewer/Models/AgentLibrary.swift TableViewer/Models/WorkspaceStore.swift \
  TableViewer/Services/ConnectionVault.swift TableViewer/Services/DatabaseEngine.swift TableViewer/Services/DatabaseSchema.swift TableViewer/Services/ResultExporter.swift \
  TableViewer/Services/AgentToolExecutor.swift TableViewer/Services/OpenAICompatibleClient.swift TableViewer/Services/MongoShellRuntime.swift TableViewer/Services/ShellSession.swift \
  Tests/DemoVisibilityRegression.swift .build/workbench040/MongoBridge.o -o .build/workbench040/DemoRegression.app/Contents/MacOS/DemoRegression

cat > .build/workbench040/DemoRegression.app/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>local.yuna.TableViewer.DemoRegression.$(uuidgen)</string><key>CFBundleExecutable</key><string>DemoRegression</string></dict></plist>
PLIST
.build/workbench040/DemoRegression.app/Contents/MacOS/DemoRegression "$@"
