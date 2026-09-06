#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/tests
xcrun clang -target arm64-apple-macos26.0 -c Native/MongoBridge.c -I .build/include -o .build/tests/MongoBridge.o
xcrun swiftc -parse-as-library -swift-version 5 -target arm64-apple-macos26.0 -module-cache-path .build/tests/ModuleCache \
  -import-objc-header Native/TableViewer-Bridging-Header.h -I .build/include/postgresql \
  -L .build/lib -Xlinker -rpath -Xlinker "$PWD/.build/lib" \
  -lsqlite3 -lpq -lmongoc2 -lbson2 \
  TableViewer/Models/DatabaseModels.swift TableViewer/Models/ReplicaSetModels.swift TableViewer/Services/DatabaseEngine.swift \
  Tests/DatabaseIntegration.swift .build/tests/MongoBridge.o -o .build/tests/DatabaseIntegration
.build/tests/DatabaseIntegration
