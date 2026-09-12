#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh
QA_APP="$PWD/.build/RayNoteQA.app"
ditto dist/RayNote.app "$QA_APP"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.codestrongestx.raynote.qa" "$QA_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName RayNote QA" "$QA_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :RayNoteLibraryDirectory string $PWD/.build/qa-library" "$QA_APP/Contents/Info.plist"
codesign --force --sign - "$QA_APP"
printf 'Built isolated QA app: %s\n' "$QA_APP"
