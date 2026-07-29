#!/bin/sh
# Builds the app bundle, replaces the copy in /Applications, and relaunches it.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILT_APP="$ROOT_DIR/.build/RotateApps.app"
INSTALL_DIR="${ROTATEAPPS_INSTALL_DIR:-/Applications}"
INSTALLED_APP="$INSTALL_DIR/RotateApps.app"

"$ROOT_DIR/Scripts/build-app.sh" >/dev/null

# Quitting through AppleScript lets the app restore the native Command + Tab shortcut,
# which a plain kill would leave disabled.
if pgrep -x RotateApps >/dev/null 2>&1; then
    echo "Quitting the running RotateApps..."
    osascript -e 'quit app "RotateApps"' >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -x RotateApps >/dev/null 2>&1 || break
        sleep 0.3
    done
    if pgrep -x RotateApps >/dev/null 2>&1; then
        echo "RotateApps did not quit; not replacing $INSTALLED_APP." >&2
        exit 1
    fi
fi

echo "Installing to $INSTALLED_APP..."
rm -rf "$INSTALLED_APP"
cp -R "$BUILT_APP" "$INSTALLED_APP"

open "$INSTALLED_APP"
echo "Installed and launched $INSTALLED_APP"
