#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/agent-tests
printf '#include <sqlite3.h>\n' > .build/agent-tests/SQLite.h
xcrun swiftc -parse-as-library -swift-version 5 -target arm64-apple-macos26.0 \
  -module-cache-path .build/agent-tests/ModuleCache -import-objc-header .build/agent-tests/SQLite.h -lsqlite3 \
  TableViewer/Models/DatabaseModels.swift TableViewer/Models/SQLScript.swift TableViewer/Models/AgentModels.swift \
  TableViewer/Models/AgentSession.swift TableViewer/Models/AgentLibrary.swift TableViewer/Services/OpenAICompatibleClient.swift \
  TableViewer/Views/AgentMessageContent.swift TableViewer/Services/ConnectionVault.swift Tests/SidebarMarkdownPerformance.swift -o .build/agent-tests/SidebarMarkdownPerformance

.build/agent-tests/SidebarMarkdownPerformance
