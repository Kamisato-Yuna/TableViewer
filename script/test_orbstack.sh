#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/orbstack-e2e
xcrun clang -target arm64-apple-macos26.0 -c Native/MongoBridge.c -I .build/include -o .build/orbstack-e2e/MongoBridge.o
xcrun swiftc -parse-as-library -swift-version 5 -target arm64-apple-macos26.0 -module-cache-path .build/orbstack-e2e/ModuleCache \
  -profile-generate -profile-coverage-mapping \
  -import-objc-header Native/TableViewer-Bridging-Header.h -I .build/include/postgresql \
  -L .build/lib -Xlinker -rpath -Xlinker "$PWD/.build/lib" -lsqlite3 -lpq -lmongoc2 -lbson2 \
  TableViewer/Models/DatabaseModels.swift TableViewer/Models/ReplicaSetModels.swift TableViewer/Services/DatabaseEngine.swift \
  Tests/OrbStackE2E.swift .build/orbstack-e2e/MongoBridge.o -o .build/orbstack-e2e/OrbStackE2E
python3 - <<'PY'
import json, os, pathlib, subprocess
import sys
sys.path.insert(0, 'script')
from seed_orbstack import verify
out=pathlib.Path('.build/orbstack-e2e').resolve()
s=json.loads((out/'connections.json').read_text())
env=os.environ|{'TABLEVIEWER_TEST_PG_PORT':s['pg_port'],'TABLEVIEWER_TEST_MONGO_PORT':s['mongo_port'],
'TABLEVIEWER_TEST_PG_PASSWORD':s['pg_password'],'TABLEVIEWER_TEST_MONGO_PASSWORD':s['mongo_password'],
'TABLEVIEWER_E2E_RESULTS':str(out/'scenarios.json'),'LLVM_PROFILE_FILE':str(out/'database.profraw')}
r=subprocess.run([str(out/'OrbStackE2E')],env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
(out/'test-output.log').write_text(r.stdout)
print(r.stdout,end='')
subprocess.run(['xcrun','llvm-profdata','merge','-sparse',str(out/'database.profraw'),'-o',str(out/'database.profdata')],check=True)
cov=['xcrun','llvm-cov','report',str(out/'OrbStackE2E'),'-instr-profile='+str(out/'database.profdata')]
report=subprocess.check_output(cov,text=True)
(out/'line-coverage.txt').write_text(report)
print(report)
verify(s)
raise SystemExit(r.returncode)
PY
