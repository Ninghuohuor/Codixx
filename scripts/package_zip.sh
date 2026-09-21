#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
ARCH="$(uname -m)"
OUT_DIR="$ROOT_DIR/dist"
ARCHIVE="$OUT_DIR/Codixx-${VERSION}-macos-${ARCH}.zip"

"$ROOT_DIR/scripts/package_app.sh"
mkdir -p "$OUT_DIR"
rm -f "$ARCHIVE"
ditto -c -k --sequesterRsrc --keepParent "$ROOT_DIR/build/Codixx.app" "$ARCHIVE"
echo "Created $ARCHIVE"
