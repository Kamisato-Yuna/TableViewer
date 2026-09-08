#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/editor053
python3 - <<'PY'
from pathlib import Path
source = Path('TableViewer/Views/QueryEditorView.swift').read_text()
Path('.build/editor053/CodeEditor.swift').write_text('import SwiftUI\n' + source[source.index('struct CodeEditor:'):])
PY
xcrun swiftc -parse-as-library -module-cache-path .build/editor053/ModuleCache .build/editor053/CodeEditor.swift Tests/Editor053InteractionTests.swift -o .build/editor053/Editor053InteractionTests
.build/editor053/Editor053InteractionTests
