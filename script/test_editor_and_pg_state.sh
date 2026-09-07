#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${TABLEVIEWER_TEST_PG_PORT:?Set the dedicated synthetic PostgreSQL port; database acceptance040 must exist with local trust authentication.}"
if [[ ! "$TABLEVIEWER_TEST_PG_PORT" =~ ^[0-9]+$ ]] || (( TABLEVIEWER_TEST_PG_PORT < 1 || TABLEVIEWER_TEST_PG_PORT > 65535 )); then
  echo "Invalid synthetic PostgreSQL port" >&2
  exit 2
fi
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/tableviewer-editor-state.XXXXXX")
trap 'rm -rf "$test_directory"' EXIT
libpq_directory=$(brew --prefix libpq)
# The focused native editor test needs no WorkspaceStore, MarkdownUI, app window,
# user defaults, clipboard or Keychain. Compile the actual editor implementation.
python3 - "$test_directory/CodeEditor.swift" <<'PY'
import pathlib
import sys
source = pathlib.Path('TableViewer/Views/QueryEditorView.swift').read_text()
pathlib.Path(sys.argv[1]).write_text('import SwiftUI\n' + source[source.index('struct CodeEditor:'):])
PY
xcrun swiftc -module-cache-path "$test_directory/ModuleCache" \
  "$test_directory/CodeEditor.swift" Tests/EditorUndoIsolationTests.swift \
  -o "$test_directory/EditorUndoIsolationTests"
"$test_directory/EditorUndoIsolationTests"
# Uses an independent named pasteboard, never the user's general clipboard.
xcrun swiftc -module-cache-path "$test_directory/ModuleCache" \
  "$test_directory/CodeEditor.swift" Tests/EditorUndoRoutingTests.swift \
  -o "$test_directory/EditorUndoRoutingTests"
"$test_directory/EditorUndoRoutingTests"
cat > "$test_directory/Bridge.h" <<'HEADER'
#include <sqlite3.h>
#include <libpq-fe.h>
HEADER
xcrun swiftc -module-cache-path "$test_directory/ModuleCache" \
  -import-objc-header "$test_directory/Bridge.h" -I "$libpq_directory/include" \
  -L "$libpq_directory/lib" -lpq \
  TableViewer/Models/DatabaseModels.swift TableViewer/Models/SQLScript.swift \
  Tests/PostgreSQLScriptStateTests.swift -o "$test_directory/PostgreSQLScriptStateTests"
"$test_directory/PostgreSQLScriptStateTests"
