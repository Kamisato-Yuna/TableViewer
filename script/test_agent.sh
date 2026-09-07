#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/agent-tests
printf '#include <sqlite3.h>\n' > .build/agent-tests/SQLite.h
xcrun swiftc -parse-as-library -swift-version 5 -target arm64-apple-macos26.0 \
  -module-cache-path .build/agent-tests/ModuleCache -import-objc-header .build/agent-tests/SQLite.h -lsqlite3 \
  TableViewer/Models/DatabaseModels.swift TableViewer/Models/SQLScript.swift TableViewer/Models/AgentModels.swift \
  TableViewer/Models/AgentSession.swift TableViewer/Models/AgentLibrary.swift TableViewer/Services/OpenAICompatibleClient.swift \
  TableViewer/Views/AgentMessageContent.swift TableViewer/Services/ConnectionVault.swift Tests/AgentExperienceTests.swift -o .build/agent-tests/AgentExperienceTests
PORT_FILE="$(mktemp "$PWD/.build/agent-tests/port.XXXXXX")"
python3 Tests/agent_http_fixture.py "$PORT_FILE" &
FIXTURE_PID=$!
trap 'kill "$FIXTURE_PID" 2>/dev/null || true; wait "$FIXTURE_PID" 2>/dev/null || true; rm -f "$PORT_FILE"' EXIT
for _ in {1..100}; do [[ -s "$PORT_FILE" ]] && break; sleep 0.05; done
export TABLEVIEWER_AGENT_FIXTURE="http://127.0.0.1:$(cat "$PORT_FILE")/v1"
.build/agent-tests/AgentExperienceTests
