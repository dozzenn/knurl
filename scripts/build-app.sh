#!/bin/bash
# Builds MacroPad.app from the Swift package. Needs the Xcode command line tools.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-release}"
APP="$ROOT/build/MacroPad.app"

echo "Building ($CONFIG)…"
swift build --package-path "$ROOT" -c "$CONFIG"
BIN="$(swift build --package-path "$ROOT" -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/MacroPadApp"           "$APP/Contents/MacOS/MacroPad"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature so macOS keeps the same identity between rebuilds; without a
# stable identity every rebuild would look like a new app to TCC.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $APP"
