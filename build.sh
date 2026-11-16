#!/bin/bash
# Builds MathPad.app. Usage: ./build.sh [--install]
#   --install  also copies the finished app to /Applications
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="MathPad"
BUILD_DIR=".build/bundle"
APP="$BUILD_DIR/$APP_NAME.app"

echo "▸ Kompilieren (release) …"
# Note: do not add --arch flags here. They switch SwiftPM to the Xcode build
# system, which happily reports "Build succeeded" while shipping a stale binary.
swift build -c release

BIN=$(swift build -c release --show-bin-path)

echo "▸ App-Bundle zusammenbauen …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources-Info.plist "$APP/Contents/Info.plist"

# The web editor and MathLive go where an app bundle normally keeps resources.
cp -R Sources/MathPad/Resources/web "$APP/Contents/Resources/web"
cp -R Sources/MathPad/Resources/vendor "$APP/Contents/Resources/vendor"

echo "▸ Icon erzeugen …"
ICONSET="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
swift Tools/make_icon.swift "$BUILD_DIR/icon.png" >/dev/null
for size in 16 32 128 256 512; do
  sips -z $size $size "$BUILD_DIR/icon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double "$BUILD_DIR/icon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "▸ Signieren (ad-hoc) …"
# Extended attributes (quarantine, provenance) make codesign refuse the bundle,
# and an unsigned bundle stops WebKit from starting its content process.
xattr -cr "$APP"
codesign --force --sign - --timestamp=none "$APP"

echo "✓ Fertig: $APP"

if [[ "${1:-}" == "--install" ]]; then
  echo "▸ Nach /Applications kopieren …"
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" /Applications/
  echo "✓ /Applications/$APP_NAME.app"
fi
