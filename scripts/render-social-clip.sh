#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$(mktemp -d "${TMPDIR:-/tmp}/raynote-video.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
OUTPUT="${1:-$PWD/.build/social/RayNote-X.mp4}"
mkdir -p "$(dirname "$OUTPUT")" "$WORK/frames"
sed 's/@main enum RayNoteApp/enum RayNoteApp/' Sources/RayNote/RayNoteApp.swift > "$WORK/RayNoteApp.swift"
SOURCES=()
for source in Sources/RayNote/*.swift; do
    [[ "$source" == "Sources/RayNote/RayNoteApp.swift" ]] || SOURCES+=("$source")
done
swiftc -parse-as-library "${SOURCES[@]}" "$WORK/RayNoteApp.swift" scripts/social-clip.swift -o "$WORK/render"
"$WORK/render" "$WORK/frames"
ffmpeg -hide_banner -loglevel warning -y -framerate 30 -i "$WORK/frames/%04d.png" \
    -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=48000 \
    -t 21 -c:v libx264 -preset medium -crf 18 -maxrate 6M -bufsize 12M \
    -pix_fmt yuv420p -r 30 -c:a aac -b:a 64k -movflags +faststart "$OUTPUT"
printf 'Created %s\n' "$OUTPUT"
