#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$(mktemp -d "${TMPDIR:-/tmp}/raynote-readme.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
# Render the real application views without launching the app or opening a personal library.
sed 's/@main enum RayNoteApp/enum RayNoteApp/' Sources/RayNote/RayNoteApp.swift > "$WORK/RayNoteApp.swift"
SOURCES=()
for source in Sources/RayNote/*.swift; do
    [[ "$source" == "Sources/RayNote/RayNoteApp.swift" ]] || SOURCES+=("$source")
done
swiftc -parse-as-library "${SOURCES[@]}" "$WORK/RayNoteApp.swift" scripts/readme-images.swift -o "$WORK/render"
"$WORK/render" "$PWD/docs/images"
