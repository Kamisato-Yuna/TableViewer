#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/sql-scripts
cat > .build/sql-scripts/WorkspacePath.swift <<'SWIFT'
import Foundation
enum LocalWorkspace { static var directory: URL { FileManager.default.temporaryDirectory } }
SWIFT
xcrun swiftc -parse-as-library -swift-version 5 -target arm64-apple-macos26.0 -module-cache-path .build/sql-scripts/ModuleCache -import-objc-header Native/TableViewer-Bridging-Header.h -I .build/include/postgresql TableViewer/Models/DatabaseModels.swift TableViewer/Models/SQLScript.swift TableViewer/Models/ScriptLibrary.swift .build/sql-scripts/WorkspacePath.swift Tests/SQLScriptTests.swift -lsqlite3 -o .build/sql-scripts/tests
.build/sql-scripts/tests
