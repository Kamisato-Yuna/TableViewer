#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/tableviewer-viewport.XXXXXX")
python3 - "$test_directory" <<'PY'
from pathlib import Path
import sys
source = Path('TableViewer/Views/QueryEditorView.swift').read_text()
directory = Path(sys.argv[1])
container = source[source.index('private final class QueryDividerlessSplitView'):source.index('struct ScriptLibraryView:')].replace('private ', '')
directory.joinpath('CodeEditor.swift').write_text('import SwiftUI\n' + container + source[source.index('struct CodeEditor:'):])
editor = source[source.index('    private var editor:'):source.index('    private var results:')]
directory.joinpath('EditorHost.swift').write_text('import SwiftUI\nstruct QueryEditorHost: View { @State private var showRunHint = false; @Bindable var store: WorkspaceStore\nvar body: some View { QueryPaneSplit(vertical: true) { editor } second: { Color.clear } }\n' + editor + '}\n')
PY
xcrun swiftc -module-cache-path "$test_directory/ModuleCache" "$test_directory/CodeEditor.swift" Tests/EditorViewportTests.swift -o "$test_directory/viewport"
"$test_directory/viewport"
xcrun swiftc -module-cache-path "$test_directory/ModuleCache" TableViewer/Models/DatabaseModels.swift "$test_directory/CodeEditor.swift" "$test_directory/EditorHost.swift" Tests/EditorUndoLifecycleTests.swift -o "$test_directory/lifecycle"
"$test_directory/lifecycle"
echo "Test artifacts: $test_directory"
