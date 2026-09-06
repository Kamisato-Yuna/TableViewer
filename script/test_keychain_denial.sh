#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/keychain-tests
xcrun clang -target arm64-apple-macos26.0 -c Native/MongoBridge.c -I .build/include -o .build/keychain-tests/MongoBridge.o
xcrun swiftc -parse-as-library -swift-version 5 -target arm64-apple-macos26.0 -module-cache-path .build/keychain-tests/ModuleCache \
 -import-objc-header Native/TableViewer-Bridging-Header.h -I .build/include/postgresql \
 -L .build/lib -Xlinker -rpath -Xlinker "$PWD/.build/lib" -lsqlite3 -lpq -lmongoc2 -lbson2 -framework JavaScriptCore \
 TableViewer/Models/DatabaseModels.swift TableViewer/Models/ReplicaSetModels.swift \
 TableViewer/Models/AgentModels.swift TableViewer/Models/AgentSession.swift TableViewer/Models/AgentLibrary.swift TableViewer/Models/WorkspaceStore.swift \
 TableViewer/Services/DatabaseEngine.swift TableViewer/Services/MongoShellRuntime.swift TableViewer/Services/ShellSession.swift \
 TableViewer/Services/ConnectionVault.swift TableViewer/Services/OpenAICompatibleClient.swift TableViewer/Services/AgentToolExecutor.swift \
 Tests/KeychainDenialTests.swift .build/keychain-tests/MongoBridge.o -o .build/keychain-tests/KeychainDenialTests
.build/keychain-tests/KeychainDenialTests
