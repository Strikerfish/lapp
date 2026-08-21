#!/bin/bash
# Builds Lapp.app.
#
# Everything is built OUTSIDE the iCloud-synced Documents tree on purpose: iCloud stamps
# com.apple.FinderInfo on anything it syncs, xattr -cr can't remove it, and codesign then
# refuses the bundle with "resource fork, Finder information, or similar detritus not
# allowed" -- producing an app macOS silently won't launch.
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
BUILD="$HOME/Lapp-build"
APP="$BUILD/dist/Lapp.app"

echo "==> Compiling"
swift build -c release --package-path "$SRC" --scratch-path "$BUILD/build"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/build/release/Lapp" "$APP/Contents/MacOS/Lapp"
cp "$SRC/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Signing"
xattr -cr "$APP"
codesign --force --deep -s - "$APP"
codesign --verify --verbose=1 "$APP"

if [[ "${1:-}" == "--install" ]]; then
    echo "==> Installing to /Applications"
    osascript -e 'quit app "Lapp"' 2>/dev/null || true
    sleep 1
    rm -rf "/Applications/Lapp.app"
    cp -R "$APP" "/Applications/Lapp.app"
    open "/Applications/Lapp.app"
    echo "Running from /Applications/Lapp.app"
else
    echo "Built. Run with: open $APP    (or ./make.sh --install)"
fi
