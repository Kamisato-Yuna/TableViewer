#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/tableviewer-result-picker.XXXXXX")
python3 - "$test_directory" <<'PY'
from pathlib import Path
import sys
source = Path('TableViewer/Views/QueryEditorView.swift').read_text()
start = source.index('                if store.statementResults.count > 1 {')
end = source.index('                Spacer()', start)
Path(sys.argv[1], 'ResultPickerHost.swift').write_text('import SwiftUI\nstruct ResultPickerHost: View { @Bindable var store: WorkspaceStore\nvar body: some View { HStack {\n' + source[start:end] + '\n} } }\n')
PY
xcrun swiftc -module-cache-path "$test_directory/ModuleCache" "$test_directory/ResultPickerHost.swift" Tests/QueryResultPickerLifecycleTests.swift -o "$test_directory/picker"
"$test_directory/picker"
echo "Test artifacts: $test_directory"
