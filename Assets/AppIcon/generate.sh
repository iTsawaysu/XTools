#!/usr/bin/env bash
# Regenerate the README image and every macOS icon size from the vector source.
# Requires librsvg (brew install librsvg) and macOS iconutil.
set -euo pipefail

ICON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v rsvg-convert >/dev/null || { echo "Missing rsvg-convert (brew install librsvg)." >&2; exit 1; }
command -v iconutil >/dev/null || { echo "Missing macOS iconutil." >&2; exit 1; }

mkdir -p "$ICON_DIR/XTools.iconset"
rsvg-convert -w 1024 -h 1024 "$ICON_DIR/XToolsIcon.svg" -o "$ICON_DIR/XToolsIcon.png"
for size in 16 32 128 256 512; do
  rsvg-convert -w "$size" -h "$size" "$ICON_DIR/XToolsIcon.svg" \
    -o "$ICON_DIR/XTools.iconset/icon_${size}x${size}.png"
  rsvg-convert -w "$((size * 2))" -h "$((size * 2))" "$ICON_DIR/XToolsIcon.svg" \
    -o "$ICON_DIR/XTools.iconset/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$ICON_DIR/XTools.iconset" -o "$ICON_DIR/XTools.icns"
