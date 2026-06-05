#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP_DIR="$ROOT_DIR/.build/RotateApps.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

cd "$ROOT_DIR"
swift build -c release
python3 "$ROOT_DIR/Scripts/generate-icon.py"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$CONTENTS_DIR/Resources"
cp "$ROOT_DIR/.build/release/RotateApps" "$MACOS_DIR/RotateApps"
cp "$ROOT_DIR/Support/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Support/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"
codesign --force --deep --sign "${ROTATEAPPS_CODESIGN_IDENTITY:--}" "$APP_DIR" >/dev/null

echo "$APP_DIR"
