#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
MODE="${1:-run}"
case "$MODE" in run|--verify|--debug|--logs|--telemetry|--build) ;; *) echo "usage: $0 [--build|--verify|--debug|--logs|--telemetry]" >&2; exit 2 ;; esac
if [[ ! -f .build/lib/libmongoc2.2.dylib ]]; then python3 script/bootstrap_drivers.py; fi
if [[ "$MODE" != --build ]]; then pkill -x TableViewer >/dev/null 2>&1 || true; fi
SIGNING_OPTIONS=("CODE_SIGN_IDENTITY=${TABLEVIEWER_CODE_SIGN_IDENTITY:--}")
if [[ -n "${TABLEVIEWER_DEVELOPMENT_TEAM:-}" ]]; then SIGNING_OPTIONS+=("DEVELOPMENT_TEAM=$TABLEVIEWER_DEVELOPMENT_TEAM"); fi
xcodebuild -project TableViewer.xcodeproj -scheme TableViewer -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/Xcode -quiet "${SIGNING_OPTIONS[@]}" build
APP_BUNDLE="$ROOT_DIR/.build/Xcode/Build/Products/Debug/TableViewer.app"
case "$MODE" in
  --build) echo "Built: $APP_BUNDLE" ;;
  --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/TableViewer" ;;
  --logs|--telemetry) open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'process == "TableViewer"' ;;
  --verify) open -n "$APP_BUNDLE"; sleep 1; pgrep -x TableViewer >/dev/null; echo "TableViewer is running." ;;
  run) open -n "$APP_BUNDLE" ;;
esac
