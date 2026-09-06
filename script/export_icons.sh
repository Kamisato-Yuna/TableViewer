#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
ICON_TOOL="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
mkdir -p Design/Previews
for appearance in Default Dark Mono; do
    "$ICON_TOOL" "$PWD/TableViewer/Resources/AppIcon.icon" --export-image \
        --output-file "$PWD/Design/Previews/TableViewer-$appearance.png" \
        --platform macOS --rendition "$appearance" --width 512 --height 512 --scale 1 --design-generation 27
done
# Small native renditions reveal whether the grid survives Finder / Dock sizes.
for size in 16 32 128; do
    "$ICON_TOOL" "$PWD/TableViewer/Resources/AppIcon.icon" --export-image \
        --output-file "$PWD/Design/Previews/TableViewer-Default-$size.png" \
        --platform macOS --rendition Default --width "$size" --height "$size" --scale 1 --design-generation 27
done
"$ICON_TOOL" "$PWD/TableViewer/Resources/AppIcon.icon" --export-image \
    --output-file "$PWD/Design/Previews/TableViewer-Default-26.png" \
    --platform macOS --rendition Default --width 512 --height 512 --scale 1 --design-generation 26
