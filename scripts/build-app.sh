#!/bin/sh
# Builds a universal (Apple Silicon + Intel) CoreGlance.app into ./build.
# Usage: scripts/build-app.sh [--install]   (--install copies it to /Applications)
set -eu
cd "$(dirname "$0")/.."

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/CoreGlance"

APP=build/CoreGlance.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/CoreGlance"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

# Ad-hoc signature: enough to run locally and to use "Launch at login".
codesign --force --sign - "$APP"
echo "Built $APP"

if [ "${1:-}" = "--install" ]; then
    rm -rf /Applications/CoreGlance.app
    cp -R "$APP" /Applications/
    echo "Installed to /Applications/CoreGlance.app"
fi
