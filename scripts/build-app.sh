#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"
SCRATCH="$HOME/Library/Caches/KoeType/build"
APP="$HOME/Applications/KoeType.app"
IDENTITY="${KOETYPE_SIGN_IDENTITY:-Apple Development}"

swift build --package-path "$ROOT" --scratch-path "$SCRATCH" -c "$CONFIG" --product KoeType
BIN="$(swift build --package-path "$ROOT" --scratch-path "$SCRATCH" -c "$CONFIG" --show-bin-path)"

pkill -x KoeType 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/KoeType" "$APP/Contents/MacOS/KoeType"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
find "$BIN" -maxdepth 1 -name "*.bundle" -exec cp -R {} "$APP/Contents/Resources/" \;

codesign --force --sign "$IDENTITY" --identifier jp.caruvistar.koetype "$APP"
codesign --verify --strict "$APP"
echo "built: $APP"
