#!/usr/bin/env bash

# build.sh - build and package XTools.app
#
# Why it used to feel slow even after "incremental":
#   1) Default was *release* (LTO/opt) — much slower than debug.
#   2) build.sh used a private .swiftpm-build cache, while `swift test`
#      warms the normal .build cache. Two caches → almost always cold.
#   3) Packaging rewrote Info.plist, strip, codesign --deep, lsregister
#      every run even when only the binary changed.
#   Packaged binaries are always strip -S -x (dev and release) so daily
#   XTools.app size tracks code+resources, not a 19MB symbol table.
#
# This script follows the XFetch hot path: one `swift build` into .build,
# then copy the binary into the .app. Daily default is *debug*.
#
# Usage:
#   ./build.sh          incremental debug build + package + open  (fast daily)
#   ./build.sh build    same as default, but do not open the app
#   ./build.sh release  incremental release build + package (no open)
#   ./build.sh rebuild  clean caches, then release build + package
#   ./build.sh clean    clean build caches only
#   ./build.sh package  package last built product only (debug if present)

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

PRODUCT_NAME="XTools"
APP_DISPLAY_NAME="XTools"
APP_NAME="$APP_DISPLAY_NAME.app"
BUNDLE_ID="${BUNDLE_ID:-com.sun.xtools}"
MIN_SYSTEM_VERSION="13.0"

# Share the default SwiftPM cache with `swift build` / `swift test`.
BUILD_DIR="$PROJECT_DIR/.build"
LEGACY_SCRATCH_DIR="$PROJECT_DIR/.swiftpm-build"
OUTPUT_DIR="$PROJECT_DIR/build"
LEGACY_DIST_DIR="$PROJECT_DIR/dist"
APP_PATH="$OUTPUT_DIR/$APP_NAME"
APP_CONTENTS="$APP_PATH/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$PRODUCT_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_NAME="XTools"
ICON_SOURCE="$PROJECT_DIR/Assets/AppIcon/$ICON_NAME.icns"
# Keep clean recoverable while remaining portable across developers and CI.
# Set TRASH_DIR explicitly when a persistent archive location is preferred.
TRASH_DIR="${TRASH_DIR:-${TMPDIR:-/tmp}/XTools-build-archive}"

SWIFT_BIN="${SWIFT_BIN:-$(xcrun --find swift)}"
ARCH="${ARCH:-$(uname -m)}"
LSREGISTER="${LSREGISTER:-/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister}"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() { printf "%b\n" "${GREEN}OK${NC} $1"; }
step() { printf "%b\n" "${BLUE}..${NC} $1"; }
warn() { printf "%b\n" "${YELLOW}WARN${NC} $1"; }
error() { printf "%b\n" "${RED}ERR${NC} $1"; }

usage() {
  sed -n '3,20p' "$0"
}

timestamp() {
  date +%Y%m%d-%H%M%S
}

now_ms() {
  python3 -c 'import time; print(int(time.time() * 1000))'
}

elapsed() {
  local start_ms="$1"
  local end_ms
  end_ms="$(now_ms)"
  printf "%s" "$((end_ms - start_ms))"
}

archive_path() {
  local path="$1"
  local label="$2"

  if [[ ! -e "$path" ]]; then
    return 0
  fi

  mkdir -p "$TRASH_DIR"
  local target="$TRASH_DIR/$label.$(timestamp).$$"
  mv "$path" "$target"
  info "Moved $path to $target"
}

clean() {
  step "Cleaning build caches..."
  archive_path "$BUILD_DIR" ".build"
  archive_path "$LEGACY_SCRATCH_DIR" ".swiftpm-build"
  archive_path "$OUTPUT_DIR" "build"
  archive_path "$LEGACY_DIST_DIR" "dist"
  info "Clean complete"
}

# Match XFetch: one plain SwiftPM invocation into the shared .build tree.
swift_build() {
  local configuration="${1:-debug}"
  local t0
  t0="$(now_ms)"
  step "swift build -c $configuration --product $PRODUCT_NAME"
  "$SWIFT_BIN" build \
    --configuration "$configuration" \
    --product "$PRODUCT_NAME" \
    --arch "$ARCH"
  info "Compile done ($(elapsed "$t0")ms)"
}

bin_path_for() {
  local configuration="${1:-debug}"
  local configuration_directory

  case "$configuration" in
    debug) configuration_directory="Debug" ;;
    release) configuration_directory="Release" ;;
    *) configuration_directory="$configuration" ;;
  esac

  # Prefer already-built product paths (no second swift process).
  local candidate
  for candidate in \
    "$BUILD_DIR/out/Products/$configuration_directory" \
    "$BUILD_DIR/$configuration" \
    "$BUILD_DIR/${ARCH}-apple-macosx/$configuration" \
    "$BUILD_DIR/arm64-apple-macosx/$configuration" \
    "$LEGACY_SCRATCH_DIR/$configuration" \
    "$LEGACY_SCRATCH_DIR/arm64-apple-macosx/$configuration"
  do
    if [[ -x "$candidate/$PRODUCT_NAME" ]]; then
      printf "%s\n" "$candidate"
      return 0
    fi
  done

  # Cold layout only.
  "$SWIFT_BIN" build \
    --configuration "$configuration" \
    --product "$PRODUCT_NAME" \
    --arch "$ARCH" \
    --show-bin-path
}

copy_swiftpm_resource_bundles() {
  local build_product_dir="$1"
  local resource_bundle destination legacy_destination bundle_name
  local copied_bundle=0

  # The current SwiftPM accessor searches Bundle.main.resourceURL for packaged apps.
  # Resource bundles at the .app root are invalid macOS bundle contents and break signing.
  # Never ship test-target bundles (e.g. XTools_XToolsTests.bundle).
  while IFS= read -r -d '' resource_bundle; do
    bundle_name="$(basename "$resource_bundle")"
    case "$bundle_name" in
      *LogicTests*.bundle|*Tests*.bundle)
        continue
        ;;
    esac
    legacy_destination="$APP_PATH/$bundle_name"
    archive_path "$legacy_destination" "$bundle_name.root-bundle"
    destination="$APP_RESOURCES/$bundle_name"
    /usr/bin/ditto "$resource_bundle" "$destination"
    copied_bundle=1
  done < <(find "$build_product_dir" -maxdepth 1 -type d -name '*.bundle' -print0)

  # Promote the app target's localization tables (compiled from
  # Sources/XTools/Resources/Localizable.xcstrings) to the .app Resources root
  # so SwiftUI Text(LocalizedStringKey) lookups through Bundle.main find them
  # without reaching into the nested SwiftPM bundle.
  local promoted_lproj
  for promoted_lproj in "$APP_RESOURCES/XTools_XTools.bundle/Contents/Resources/"*.lproj; do
    [[ -e "$promoted_lproj" ]] || continue
    /usr/bin/ditto "$promoted_lproj" "$APP_RESOURCES/$(basename "$promoted_lproj")"
  done

  # Remove any stale test resource bundles left by older packaging runs.
  local stale_test_bundle
  while IFS= read -r -d '' stale_test_bundle; do
    archive_path "$stale_test_bundle" "$(basename "$stale_test_bundle").stale-test-bundle"
  done < <(find "$APP_RESOURCES" -maxdepth 1 -type d \( -name '*LogicTests*.bundle' -o -name '*Tests*.bundle' \) -print0 2>/dev/null)

  # Remove pre-rename product resource bundles (DevToolsMac* → XTools*).
  local stale_legacy_bundle
  while IFS= read -r -d '' stale_legacy_bundle; do
    archive_path "$stale_legacy_bundle" "$(basename "$stale_legacy_bundle").stale-legacy-bundle"
  done < <(find "$APP_RESOURCES" -maxdepth 1 -type d -name 'DevToolsMac*.bundle' -print0 2>/dev/null)

  if [[ "$copied_bundle" == "0" ]]; then
    error "No SwiftPM resource bundles found beside $build_product_dir/$PRODUCT_NAME"
    exit 1
  fi

  if [[ -z "$(find "$APP_RESOURCES/XTools_XToolsCore.bundle" -type f -name 'Readability-0.6.0.js' -print -quit 2>/dev/null)" ]]; then
    error "Missing Readability-0.6.0.js in packaged XToolsCore resources"
    exit 1
  fi
}

stop_existing_app() {
  pkill -x "$PRODUCT_NAME" >/dev/null 2>&1 || true
  pkill -x "$APP_DISPLAY_NAME" >/dev/null 2>&1 || true
}

write_info_plist_if_needed() {
  if [[ -f "$INFO_PLIST" ]]; then
    local current_bundle_id
    if current_bundle_id="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$INFO_PLIST" 2>/dev/null)"; then
      # Keep the hot path byte-for-byte stable when the requested identity is unchanged.
      if [[ "$current_bundle_id" == "$BUNDLE_ID" ]]; then
        return 0
      fi
      /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$INFO_PLIST"
    else
      /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $BUNDLE_ID" "$INFO_PLIST"
    fi
    return 0
  fi

  cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$PRODUCT_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleIconFile</key>
  <string>$ICON_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST
}

package_app() {
  local configuration="${1:-debug}"
  local t0 build_product_dir build_binary icon_changed=0
  t0="$(now_ms)"
  build_product_dir="$(bin_path_for "$configuration")"
  build_binary="$build_product_dir/$PRODUCT_NAME"

  if [[ ! -x "$build_binary" ]]; then
    error "Missing build product: $build_binary"
    exit 1
  fi

  if [[ ! -f "$ICON_SOURCE" ]]; then
    error "Missing app icon: $ICON_SOURCE"
    exit 1
  fi

  step "Packaging $APP_PATH ($configuration)..."
  stop_existing_app
  mkdir -p "$OUTPUT_DIR" "$APP_MACOS" "$APP_RESOURCES"

  cp "$build_binary" "$APP_BINARY"
  chmod +x "$APP_BINARY"

  # Compare content: an existing app still needs newly generated icon resources.
  if ! cmp -s "$ICON_SOURCE" "$APP_RESOURCES/$ICON_NAME.icns"; then
    cp "$ICON_SOURCE" "$APP_RESOURCES/$ICON_NAME.icns"
    icon_changed=1
  fi

  # Drop stale pre-rename product icon if an older packaging run left it behind.
  # Keep XTools.icns (CFBundleIconFile); never remove the active icon.
  if [[ -f "$APP_RESOURCES/Tools.icns" ]]; then
    archive_path "$APP_RESOURCES/Tools.icns" "Tools.icns.stale-icon"
  fi

  write_info_plist_if_needed
  copy_swiftpm_resource_bundles "$build_product_dir"

  # Strip local symbols from the packaged binary for every configuration.
  # Debug *compilation* stays fast; only the .app payload loses LINKEDIT mass.
  # Use .build/.../XTools when you need full symbols for Instruments.
  if ! strip -S -x "$APP_BINARY"; then
    warn "strip -S -x failed for $APP_BINARY; packaging continues with unstripped binary"
  fi

  # Ad-hoc sign the app only (no --deep). Nested tools are not in this bundle.
  # Must run after strip — strip invalidates any prior code signature.
  codesign --force --sign - "$APP_PATH" >/dev/null

  # Refresh Finder/Dock icon metadata when artwork changes, keeping the normal
  # incremental path fast. Do this after signing so registration sees the final app.
  if [[ "$icon_changed" == "1" ]]; then
    touch "$APP_PATH"
  fi
  if [[ ( "$icon_changed" == "1" || "${LSREGISTER_EVERY_BUILD:-0}" == "1" ) && -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -f "$APP_PATH" >/dev/null 2>&1 || true
  fi

  local app_size binary_size
  app_size="$(du -sh "$APP_PATH" | awk '{print $1}')"
  binary_size="$(du -h "$APP_BINARY" | awk '{print $1}')"
  info "Packaged $APP_PATH (app: $app_size, binary: $binary_size, configuration: $configuration, stripped: -S -x, $(elapsed "$t0")ms)"
}

dev_build_and_launch() {
  local open_app="${1:-1}"
  local t0
  t0="$(now_ms)"
  swift_build debug
  package_app debug
  if [[ "$open_app" == "1" ]]; then
    step "Opening $APP_PATH..."
    open "$APP_PATH"
    info "Opened $APP_DISPLAY_NAME"
  fi
  info "Total $(elapsed "$t0")ms"
}

release_build_and_package() {
  local t0
  t0="$(now_ms)"
  swift_build release
  package_app release
  info "Total $(elapsed "$t0")ms"
}

rebuild_and_package() {
  clean
  release_build_and_package
}

case "${1:-}" in
  ""|dev)
    # Daily hot path: debug + open
    dev_build_and_launch 1
    ;;
  build)
    # Debug package without open (CI / scripts)
    dev_build_and_launch 0
    ;;
  release)
    release_build_and_package
    ;;
  rebuild)
    rebuild_and_package
    ;;
  package)
    # Prefer the most recently touched product.
    if [[ -x "$BUILD_DIR/out/Products/Debug/$PRODUCT_NAME" || -x "$BUILD_DIR/debug/$PRODUCT_NAME" || -x "$BUILD_DIR/arm64-apple-macosx/debug/$PRODUCT_NAME" ]]; then
      package_app debug
    else
      package_app release
    fi
    ;;
  clean)
    clean
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    error "Unknown command: $1"
    usage
    exit 1
    ;;
esac
