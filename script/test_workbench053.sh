#!/usr/bin/env bash
set -euo pipefail
# No implicit ports: absent TV053_*_PORT skips those engines. Caller owns fixture servers.
cd "$(dirname "$0")/.."
cd "$(pwd -P)"
mkdir -p .build/extensions053
xcrun clang -target arm64-apple-macos26.0 -c Native/MongoBridge.c -I .build/include -o .build/extensions053/MongoBridge.o
xcrun swiftc -parse-as-library -swift-version 5 -target arm64-apple-macos26.0 -module-cache-path .build/extensions053/ModuleCache \
  -import-objc-header Native/TableViewer-Bridging-Header.h -I .build/include/postgresql \
  -L .build/lib -Xlinker -rpath -Xlinker "$PWD/.build/lib" -lsqlite3 -lpq -lmongoc2 -lbson2 -framework JavaScriptCore \
  TableViewer/Models/DatabaseModels.swift TableViewer/Models/ReplicaSetModels.swift \
  TableViewer/Models/SQLScript.swift TableViewer/Models/ScriptLibrary.swift TableViewer/Models/SchemaMetadata.swift \
  TableViewer/Models/AgentModels.swift TableViewer/Models/AgentSession.swift TableViewer/Models/AgentLibrary.swift TableViewer/Models/WorkspaceStore.swift \
  TableViewer/Services/ConnectionVault.swift TableViewer/Services/DatabaseEngine.swift TableViewer/Services/DatabaseSchema.swift TableViewer/Services/ResultExporter.swift \
  TableViewer/Services/AgentToolExecutor.swift TableViewer/Services/OpenAICompatibleClient.swift TableViewer/Services/MongoShellRuntime.swift TableViewer/Services/ShellSession.swift \
  Tests/Workbench053Extensions.swift .build/extensions053/MongoBridge.o -o .build/extensions053/Workbench053Extensions
if [[ $# -eq 0 ]]; then
  fixture_dir=$(mktemp -d "${TMPDIR:-/tmp}/tableviewer-extensions053.XXXXXX")
  set -- "$fixture_dir"
  echo "Test artifacts: $fixture_dir"
fi
.build/extensions053/Workbench053Extensions "$@"
