#!/bin/sh
# Electron's stock app is named "Electron" with bundle ID com.github.Electron. Running from source inside a clone of it
# renamed to "Unteams Debug" gives the debug run its own name, icon and bundle ID. Rebuilt when Electron changes.
set -e
cd "$(dirname "$0")/.."

ELECTRON_APP="$(dirname "$(node -p 'require.resolve("electron/package.json")')")/dist/Electron.app"
APP="build/Unteams Debug.app"
STAMP="build/debug-app-version"
VERSION="$(node -p 'require("electron/package.json").version')"

if [ -d "$APP" ] && [ "$(cat "$STAMP" 2>/dev/null)" = "$VERSION" ]; then exit 0; fi

rm -rf "$APP" "$STAMP"
mkdir -p build
cp -cR "$ELECTRON_APP" "$APP"

ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size ../../assets/AppIcon-Debug.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) ../../assets/AppIcon-Debug.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/electron.icns"

/usr/libexec/PlistBuddy \
  -c "Set :CFBundleName Unteams Debug" \
  -c "Set :CFBundleDisplayName Unteams Debug" \
  -c "Set :CFBundleIdentifier app.unteams.debug.mac" \
  "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"
echo "$VERSION" >"$STAMP"
