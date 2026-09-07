#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/reliability
xcrun clang -target arm64-apple-macos26.0 -c Native/MongoBridge.c -I .build/include -o .build/reliability/MongoBridge.o
xcrun swiftc -parse-as-library -swift-version 5 -target arm64-apple-macos26.0 -module-cache-path .build/reliability/ModuleCache \
  -import-objc-header Native/TableViewer-Bridging-Header.h -I .build/include/postgresql \
  -L .build/lib -Xlinker -rpath -Xlinker "$PWD/.build/lib" \
  -lsqlite3 -lpq -lmongoc2 -lbson2 -framework JavaScriptCore \
  TableViewer/Models/*.swift TableViewer/Services/{AgentToolExecutor,ConnectionVault,DatabaseEngine,DatabaseSchema,ResultExporter,MongoShellRuntime,OpenAICompatibleClient,ShellSession}.swift TableViewer/Views/DataGrid.swift \
  Tests/ReliabilityIntegration.swift .build/reliability/MongoBridge.o -o .build/reliability/ReliabilityIntegration
.build/reliability/ReliabilityIntegration
