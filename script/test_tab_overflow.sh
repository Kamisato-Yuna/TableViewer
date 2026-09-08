#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/tableviewer-tabs.XXXXXX")
python3 - "$test_directory" <<'PY'
from pathlib import Path
import sys
s=Path('TableViewer/Views/QueryEditorView.swift').read_text()
helpers=s[s.index('private struct ScriptTabClipContainer'):s.index('// Own the split view')].replace('private ', '')
a=s.index('                GeometryReader { tabGeometry')
b=s.index('}.frame(height: 44)',a)+len('}.frame(height: 44)')
body=s[a:b].replace("tabOverflow = edges", "tabOverflow = edges; store.edges = edges")
Path(sys.argv[1],'TabHost.swift').write_text('import SwiftUI\n'+helpers+'\nstruct TabHost: View { @Bindable var store: TabStore; @State private var tabOverflow = TabOverflowEdges(); var body: some View { '+body+' } }')
PY
xcrun swiftc -module-cache-path "$test_directory/ModuleCache" "$test_directory/TabHost.swift" Tests/TabOverflowTests.swift -o "$test_directory/tabs"
"$test_directory/tabs"
echo "Test artifacts: $test_directory"
