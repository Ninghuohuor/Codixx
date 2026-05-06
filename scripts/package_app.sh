#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
APP_DIR="$ROOT_DIR/build/Codixx.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_DIR/Codixx" "$MACOS_DIR/Codixx"
chmod +x "$MACOS_DIR/Codixx"

if [[ -f "$ROOT_DIR/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png" ]]; then
  cp "$ROOT_DIR/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png" "$RESOURCES_DIR/AppIcon.png"
fi

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>Codixx</string>
  <key>CFBundleIdentifier</key>
  <string>local.codixx.app</string>
  <key>CFBundleName</key>
  <string>Codixx</string>
  <key>CFBundleDisplayName</key>
  <string>Codixx</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

echo "Created $APP_DIR"
