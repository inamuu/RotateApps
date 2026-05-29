#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP_DIR="$ROOT_DIR/.build/RotateApps.app"
ZIP_PATH="$ROOT_DIR/.build/RotateApps.zip"

"$ROOT_DIR/Scripts/build-app.sh" >/dev/null
rm -f "$ZIP_PATH"
(cd "$ROOT_DIR/.build" && COPYFILE_DISABLE=1 zip -r -X "RotateApps.zip" "RotateApps.app" >/dev/null)

echo "$ZIP_PATH"
