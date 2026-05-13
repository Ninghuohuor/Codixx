#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DEFAULT_SIGN_IDENTITY="Codixx Local Code Signing"
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-$DEFAULT_SIGN_IDENTITY}"
APP_VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"

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

if [[ -f "$ROOT_DIR/Resources/AppIcon.icns" ]]; then
  cp "$ROOT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

if [[ -f "$ROOT_DIR/Resources/MenuBarIcon.png" ]]; then
  cp "$ROOT_DIR/Resources/MenuBarIcon.png" "$RESOURCES_DIR/MenuBarIcon.png"
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
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>__APP_VERSION__</string>
  <key>CFBundleVersion</key>
  <string>103</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

/usr/bin/sed -i '' "s/__APP_VERSION__/$APP_VERSION/g" "$CONTENTS_DIR/Info.plist"

if security find-identity -v -p codesigning | grep -Fq "\"$SIGN_IDENTITY\""; then
  codesign --force --deep --timestamp=none --sign "$SIGN_IDENTITY" "$APP_DIR"
  echo "Signed $APP_DIR with $SIGN_IDENTITY"
else
  echo "Code signing identity '$SIGN_IDENTITY' not found; leaving app unsigned"
fi

echo "Created $APP_DIR"
