#!/usr/bin/env bash

# build.sh - build and package XTools.app
#
# Usage:
#   ./build.sh          release build + package + open  (daily default)
#   ./build.sh dev      debug build + package + open    (fast iteration fallback)
#   ./build.sh build    release build + package, do not open (CI / scripts)
#   ./build.sh release  same as `build`: release build + package (no open)
#   ./build.sh rebuild  archive build caches, then build and package
#   ./build.sh clean    archive owned build caches and app output
#   ./build.sh package  package last built product only

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$PROJECT_DIR"

PRODUCT_NAME="XTools"
APP_DISPLAY_NAME="XTools"
APP_NAME="$APP_DISPLAY_NAME.app"
BUNDLE_ID="${BUNDLE_ID:-com.sun.xtools}"
MIN_SYSTEM_VERSION="14.0"

# Share the selected SwiftPM cache with `swift build` / `swift test`.
DEFAULT_BUILD_DIR="$PROJECT_DIR/.build"
BUILD_DIR="${SWIFTPM_BUILD_DIR:-$DEFAULT_BUILD_DIR}"
case "$BUILD_DIR" in /*) ;; *) BUILD_DIR="$PROJECT_DIR/$BUILD_DIR" ;; esac
while [[ "$BUILD_DIR" != / && ( "$BUILD_DIR" == */ || "$BUILD_DIR" == */. ) ]]; do
  BUILD_DIR="${BUILD_DIR%/.}"
  BUILD_DIR="${BUILD_DIR%/}"
done
BUILD_DIR="${BUILD_DIR:-/}"
BUILD_OWNER_FILE="$BUILD_DIR/.xtools-cache-owner"
LEGACY_SCRATCH_DIR="$PROJECT_DIR/.swiftpm-build"
# Send verification packages to an independent OUTPUT_DIR.
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_DIR/build}"
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

SWIFT_OVERRIDE="${SWIFT_BIN:-}"
SWIFT_BIN="${SWIFT_OVERRIDE:-$(xcrun --find swift)}"
ARCH="${ARCH:-$(uname -m)}"
# Resource-only builds may leave the executable mtime unchanged.
BUILD_STATE_FILE="$BUILD_DIR/.last-build-configuration-$ARCH"
LSREGISTER="${LSREGISTER:-/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister}"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

info() { printf "%b\n" "${GREEN}OK${NC} $1"; }
step() { printf "%b\n" "${BLUE}..${NC} $1"; }
error() { printf "%b\n" "${RED}ERR${NC} $1" >&2; }

usage() {
  cat <<'EOF'
Usage:
  ./build.sh              release build + package + open (daily default)
  ./build.sh dev          debug build + package + open (fast iteration)
  ./build.sh build-dev    debug build + package, do not open
  ./build.sh build        release build + package, do not open (CI / scripts)
  ./build.sh release      same as build
  ./build.sh rebuild      clean caches, then release build + package
  ./build.sh clean        archive build caches and packaged output
  ./build.sh package [debug|release]  package last build.sh output for this architecture (fallback: newest binary)
  ./build.sh help         show this help
EOF
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
  local target
  shift 2

  if [[ ! -e "$path" ]]; then
    return 0
  fi

  target="$(archive_destination "$label" "$path" "$@")" || return 1
  mv "$path" "$target" || return 1
  info "Moved $path to $target"
}

archive_destination() {
  local label="$1"
  shift
  assert_archive_location "$@" || return 1
  mkdir -p "$TRASH_DIR" || return 1
  printf '%s/%s.%s.%s\n' "$TRASH_DIR" "$label" "$(timestamp)" "$$"
}

archive_packaging_scratch() {
  local target="$1" scratch="$2"
  if ! archive_path "$scratch" "xtools-package" "$target" >&2; then
    printf 'WARN Kept packaging work at %s\n' "$scratch" >&2
  fi
}

path_is_outside() {
  python3 -B - "$@" <<'PY'
import os
import sys
import unicodedata

mode = sys.argv[1]
candidate, *sources = (
    unicodedata.normalize("NFD", os.path.realpath(path)).casefold()
    for path in sys.argv[2:]
)
for source in sources:
    common = os.path.commonpath((candidate, source))
    if common == source or (mode == "disjoint" and common == candidate):
        sys.exit(1)
PY
}

assert_archive_location() {
  if ! path_is_outside descendants "$TRASH_DIR" "$@"; then
    error "Archive must be outside the paths being packaged or moved: $TRASH_DIR"
    return 1
  fi
}

assert_cache_archive_location() {
  if ! path_is_outside disjoint "$APP_PATH" "$@"; then
    error "App destination must be outside and separate from SwiftPM caches: $APP_PATH"
    return 1
  fi
  assert_archive_location "$APP_PATH" "$@"
}

assert_owned_app_path() {
  if [[ -L "$APP_PATH" || ( -e "$APP_PATH" && ! -d "$APP_PATH" ) ]]; then
    error "Invalid app destination: $APP_PATH"
    return 1
  fi
  if [[ -d "$APP_PATH" ]]; then
    local identity
    if ! identity="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' -c 'Print :CFBundleIdentifier' "$INFO_PLIST" 2>/dev/null)" ||
       [[ "$identity" != "$PRODUCT_NAME"$'\n'"$BUNDLE_ID" ]]; then
      error "Not an XTools package for bundle identifier $BUNDLE_ID: $APP_PATH"
      return 1
    fi
  fi
}

app_path_command() {
  osascript -l JavaScript "$PROJECT_DIR/tools/packaging-app.js" "$@"
}

claim_custom_build_cache() {
  if [[ -L "$BUILD_OWNER_FILE" ]] ||
     { [[ -f "$BUILD_OWNER_FILE" ]] && [[ "$(< "$BUILD_OWNER_FILE")" != "$PROJECT_DIR" ]]; }; then
    error "SwiftPM cache belongs to a different project: $BUILD_DIR"
    return 1
  fi
  if [[ -L "$BUILD_DIR" || "$BUILD_DIR" == "$DEFAULT_BUILD_DIR" || "$BUILD_DIR" -ef "$DEFAULT_BUILD_DIR" ]]; then
    return
  fi
  if [[ ! -e "$BUILD_DIR" ]] || [[ -d "$BUILD_DIR" && -z "$(ls -A "$BUILD_DIR")" ]]; then
    mkdir -p "$BUILD_DIR"
    (set -o noclobber; printf '%s\n' "$PROJECT_DIR" >"$BUILD_OWNER_FILE")
  fi
}

clean_build_caches() {
  if [[ -L "$BUILD_DIR" ]]; then
    error "Build cache is a symbolic link; use its owned path directly: $BUILD_DIR"
    return 1
  fi
  if [[ "$BUILD_DIR" == "$DEFAULT_BUILD_DIR" || "$BUILD_DIR" -ef "$DEFAULT_BUILD_DIR" ]]; then
    assert_cache_archive_location "$DEFAULT_BUILD_DIR" "$LEGACY_SCRATCH_DIR"
    archive_path "$DEFAULT_BUILD_DIR" ".build"
    archive_path "$LEGACY_SCRATCH_DIR" ".swiftpm-build"
  else
    if [[ -e "$BUILD_DIR" ]] &&
       [[ -L "$BUILD_OWNER_FILE" || ! -f "$BUILD_OWNER_FILE" || "$(< "$BUILD_OWNER_FILE")" != "$PROJECT_DIR" ]]; then
      error "Kept unowned SwiftPM cache: $BUILD_DIR"
      return 1
    fi
    assert_cache_archive_location "$BUILD_DIR"
    archive_path "$BUILD_DIR" "xtools-swiftpm-cache"
  fi
}

clean() {
  local identity destination
  identity="$(stat -f '%d:%i' "$APP_PATH" 2>/dev/null || printf 'missing')"
  assert_owned_app_path
  if [[ "$identity" != "missing" ]]; then
    app_path_command check "$APP_PATH" "" no "$identity" "$BUNDLE_ID"
  fi
  clean_build_caches
  if [[ "$identity" != "missing" || -e "$APP_PATH" || -L "$APP_PATH" ]]; then
    if [[ "$identity" == "missing" ]]; then
      error "Destination changed while cleaning: $APP_PATH"
      return 1
    fi
    destination="$(archive_destination "$APP_NAME" "$APP_PATH")"
    app_path_command archive "$APP_PATH" "$destination" no "$identity" "$BUNDLE_ID"
    info "Moved $APP_PATH to $destination"
  fi
  info "Clean complete"
}

swift_product() {
  local configuration="$1"
  shift
  local args=(build --configuration "$configuration" --product "$PRODUCT_NAME")
  if [[ "$ARCH" != "$(uname -m)" ]]; then
    args+=(--arch "$ARCH")
  fi
  "$SWIFT_BIN" "${args[@]}" "$@"
}

swift_build() {
  local configuration="$1" t0
  step "ui-lint: checking shared-control boundaries"
  python3 "$PROJECT_DIR/tools/ui-lint.py" --root "$PROJECT_DIR"
  claim_custom_build_cache
  t0="$(now_ms)"
  step "swift build -c $configuration --product $PRODUCT_NAME ($ARCH)"
  swift_product "$configuration"
  mkdir -p "$(dirname "$BUILD_STATE_FILE")"
  printf '%s\n' "$configuration" >"$BUILD_STATE_FILE"
  info "Compile done ($(elapsed "$t0")ms)"
}

verify_package() {
  codesign --verify --strict -R="identifier \"$BUNDLE_ID\"" "$1"
}

bin_path_for() {
  local configuration="$1" product descriptor expected="" cached_key="" cached_product=""
  descriptor="$BUILD_DIR/.xtools-product-$configuration-$ARCH"
  # Only cache the selected Apple toolchain. A custom wrapper or scratch
  # setting can change its output without changing the executable.
  if [[ -z "$SWIFT_OVERRIDE" && -z "${SWIFTPM_BUILD_DIR:-}" ]]; then
    expected="$SWIFT_BIN:$(stat -Lf '%d:%i:%m:%z' "$(dirname "$SWIFT_BIN")/swift-build"):${SDKROOT:-}"
    if [[ -f "$descriptor" ]]; then
      {
        IFS= read -r cached_key
        IFS= read -r cached_product
      } <"$descriptor" || true
      if [[ "$cached_key" == "$expected" && -x "$cached_product/$PRODUCT_NAME" ]]; then
        printf '%s\n' "$cached_product"
        return
      fi
    fi
  fi
  product="$(swift_product "$configuration" --show-bin-path)" || return 1
  if [[ -n "$expected" && -x "$product/$PRODUCT_NAME" && -d "$BUILD_DIR" ]]; then
    printf '%s\n' "$expected" "$product" >"$descriptor"
  fi
  printf '%s\n' "$product"
}

package_input_digest() {
  local products="$1" bundle
  {
    printf '%s\n' "$BUNDLE_ID" "$ARCH" "$configuration"
    {
      printf '%s\0' "$build_binary" "$ICON_SOURCE" "$PROJECT_DIR/build.sh" \
        "$PROJECT_DIR/ThirdPartyNotices.txt" "$PROJECT_DIR/LICENSE" \
        "$PROJECT_DIR/Sources/XTools/Resources/Localizable.xcstrings"
      for bundle in "$products/XTools_XToolsCore.bundle" "$products/XTools_XTools.bundle"; do
        if [[ -d "$bundle" ]]; then
          find "$bundle" -type f -print0 || return 1
        fi
      done
    } | xargs -0 shasum -a 256 | LC_ALL=C sort || return 1
  } | shasum -a 256 | awk '{print $1}'
}

localization_matches() {
  local source="$1" destination="$2" table relative_path
  diff -rq -x '*.strings' -x '*.stringsdict' "$source" "$destination" >/dev/null 2>&1 || return 1

  while IFS= read -r -d '' table; do
    relative_path="${table#"$source"/}"
    plutil -convert binary1 -o - "$table" | cmp -s - "$destination/$relative_path" || return 1
  done < <(find "$source" -type f \( -name '*.strings' -o -name '*.stringsdict' \) -print0)

  while IFS= read -r -d '' table; do
    relative_path="${table#"$destination"/}"
    [[ -f "$source/$relative_path" ]] || return 1
  done < <(find "$destination" -type f \( -name '*.strings' -o -name '*.stringsdict' \) -print0)
}

resource_directory() {
  if [[ -d "$1/Contents/Resources" ]]; then
    printf '%s\n' "$1/Contents/Resources"
  else
    printf '%s\n' "$1"
  fi
}

copy_app_resources() {
  local products="$1" previous_resources="$2" scratch="$3"
  local core app localized lproj destination previous resource table
  core="$(resource_directory "$products/XTools_XToolsCore.bundle")"
  for resource in Readability-0.6.0.js emoji-catalog-v1.plist; do
    if [[ ! -s "$core/$resource" ]]; then
      error "Missing XToolsCore resource: $core/$resource"
      return 1
    fi
  done
  mkdir -p "$APP_RESOURCES/XToolsCore"
  /usr/bin/ditto "$core" "$APP_RESOURCES/XToolsCore"

  app="$products/XTools_XTools.bundle"
  localized="$(resource_directory "$app")"
  if [[ -d "$app" ]]; then
    /usr/bin/rsync -a --exclude='*.lproj' --exclude='*.xcstrings' \
      "$app/" "$APP_RESOURCES/XTools_XTools.bundle/"
  fi
  if [[ ! -f "$localized/zh-Hans.lproj/Localizable.strings" ]]; then
    localized="$scratch/localized"
    mkdir -p "$localized"
    xcrun xcstringstool compile --output-directory "$localized" \
      "$PROJECT_DIR/Sources/XTools/Resources/Localizable.xcstrings"
  fi
  if [[ ! -s "$localized/zh-Hans.lproj/Localizable.strings" ]]; then
    error "Missing compiled zh-Hans localization"
    return 1
  fi

  for lproj in "$localized/"*.lproj; do
    destination="$APP_RESOURCES/$(basename "$lproj")"
    previous="$previous_resources/$(basename "$lproj")"
    if [[ -d "$previous" ]] && localization_matches "$lproj" "$previous"; then
      /usr/bin/ditto "$previous" "$destination"
      continue
    fi
    /usr/bin/ditto "$lproj" "$destination"
    while IFS= read -r -d '' table; do
      plutil -convert binary1 "$table" || return 1
    done < <(find "$destination" -type f \( -name '*.strings' -o -name '*.stringsdict' \) -print0)
  done
  cp -p "$PROJECT_DIR/ThirdPartyNotices.txt" "$PROJECT_DIR/LICENSE" "$APP_RESOURCES/"
}

# 体积预算断言：打包二进制必须明显小于构建产物（strip 被绕过时该比例会失控），
# 且不得超过配置的绝对上限（debug 30MB / release 20MB）。
# 实测基线：debug 约 51%、release 约 50%，60% 预算留有余量。
assert_binary_size_budget() {
  local configuration="$1"
  local build_binary="$2"

  local packaged_bytes build_bytes
  packaged_bytes="$(stat -f%z "$APP_BINARY")"
  build_bytes="$(stat -f%z "$build_binary")"

  local max_ratio_bytes=$(( build_bytes * 60 / 100 ))
  if (( packaged_bytes > max_ratio_bytes )); then
    error "Packaged binary is $packaged_bytes bytes, over the 60% budget of build product $build_bytes ($max_ratio_bytes bytes); strip likely did not run"
    exit 1
  fi

  local absolute_cap_bytes
  case "$configuration" in
    release) absolute_cap_bytes=$((20 * 1024 * 1024)) ;;
    *) absolute_cap_bytes=$((30 * 1024 * 1024)) ;;
  esac
  if (( packaged_bytes > absolute_cap_bytes )); then
    error "Packaged binary is $packaged_bytes bytes, over the $configuration cap ($absolute_cap_bytes bytes)"
    exit 1
  fi
}

write_info_plist() {
  local previous="$1"
  # ATS allows user-supplied HTTP Git endpoints and public HTTP article URLs.
  local expected
  expected="$(cat <<PLIST
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
  <key>CFBundleDevelopmentRegion</key>
  <string>zh-Hans</string>
  <key>CFBundleIconFile</key>
  <string>$ICON_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>XToolsPackageInputDigest</key>
  <string>$input_digest</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.developer-tools</string>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
  </dict>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSSupportsAutomaticTermination</key>
  <false/>
</dict>
</plist>
PLIST
)"
  if [[ -f "$previous" && "$(< "$previous")" == "$expected" ]]; then
    cp -p "$previous" "$INFO_PLIST"
  else
    printf '%s\n' "$expected" >"$INFO_PLIST"
  fi
  plutil -lint "$INFO_PLIST" >/dev/null
}

package_app() (
  configuration="$1"
  products="$2"
  may_stop="${3:-no}"
  t0="$(now_ms)"
  build_binary="$products/$PRODUCT_NAME"
  target="$APP_PATH"

  if [[ ! -x "$build_binary" ]]; then
    error "Missing build product: $build_binary"
    exit 1
  fi
  if ! lipo "$build_binary" -verify_arch "$ARCH" 2>/dev/null; then
    error "Build product at $build_binary does not contain $ARCH"
    exit 1
  fi
  if [[ ! -f "$ICON_SOURCE" ]]; then
    error "Missing app icon: $ICON_SOURCE"
    exit 1
  fi
  if [[ ! "$BUNDLE_ID" =~ ^[A-Za-z0-9.-]+$ ]]; then
    error "Invalid bundle identifier: $BUNDLE_ID"
    exit 1
  fi
  assert_owned_app_path
  target_identity="$(stat -f '%d:%i' "$target" 2>/dev/null || printf 'missing')"
  input_digest="$(package_input_digest "$products")"
  if [[ -f "$INFO_PLIST" &&
        "$(plutil -extract XToolsPackageInputDigest raw -o - "$INFO_PLIST" 2>/dev/null || true)" == "$input_digest" ]] &&
      verify_package "$target" >/dev/null 2>&1; then
    if [[ "${LSREGISTER_EVERY_BUILD:-0}" == "1" && -x "$LSREGISTER" ]]; then
      "$LSREGISTER" -f "$target" >/dev/null 2>&1 || true
    fi
    info "Up to date $target ($configuration, $(elapsed "$t0")ms)"
    exit 0
  fi

  step "Packaging $target ($configuration)..."
  assert_archive_location "$target"
  mkdir -p "$OUTPUT_DIR"
  scratch="$(mktemp -d "$OUTPUT_DIR/.xtools-package.XXXXXXXX")"
  # Keep an unpublished candidate or the displaced app recoverable.
  trap 'archive_packaging_scratch "$target" "$scratch"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  APP_PATH="$scratch/$APP_NAME"
  APP_CONTENTS="$APP_PATH/Contents"
  APP_MACOS="$APP_CONTENTS/MacOS"
  APP_RESOURCES="$APP_CONTENTS/Resources"
  APP_BINARY="$APP_MACOS/$PRODUCT_NAME"
  INFO_PLIST="$APP_CONTENTS/Info.plist"
  mkdir -p "$APP_MACOS" "$APP_RESOURCES"

  /bin/cp -c "$build_binary" "$APP_BINARY"
  previous_resources="$target/Contents/Resources"
  previous_icon="$previous_resources/$ICON_NAME.icns"
  icon_changed=0
  if cmp -s "$ICON_SOURCE" "$previous_icon"; then
    cp -p "$previous_icon" "$APP_RESOURCES/$ICON_NAME.icns"
  else
    cp -p "$ICON_SOURCE" "$APP_RESOURCES/$ICON_NAME.icns"
    icon_changed=1
  fi
  write_info_plist "$target/Contents/Info.plist"
  copy_app_resources "$products" "$previous_resources" "$scratch"

  if ! strip -S -x "$APP_BINARY"; then
    error "strip -S -x failed for $APP_BINARY"
    exit 1
  fi
  assert_binary_size_budget "$configuration" "$build_binary"
  codesign --force --sign - "$APP_PATH" >/dev/null
  verify_package "$APP_PATH"

  app_path_command publish "$target" "$APP_PATH" "$may_stop" "$target_identity" "$BUNDLE_ID"
  if [[ "$icon_changed" == "1" || "${LSREGISTER_EVERY_BUILD:-0}" == "1" ]] && [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -f "$target" >/dev/null 2>&1 || true
  fi
  app_size="$(du -sh "$target" | awk '{print $1}')"
  info "Packaged $target (app: $app_size, configuration: $configuration, $(elapsed "$t0")ms)"
)

build_and_package() {
  local configuration="$1" products
  swift_build "$configuration"
  products="$(bin_path_for "$configuration")"
  package_app "$configuration" "$products"
}

build_and_launch() {
  local configuration="$1" products may_stop=no
  if [[ -z "${KEEP_RUNNING_APP:-}" ]]; then
    may_stop=yes
  fi
  swift_build "$configuration"
  products="$(bin_path_for "$configuration")"
  package_app "$configuration" "$products" "$may_stop"
  step "Opening $APP_PATH..."
  app_path_command launch "$APP_PATH" "" "$may_stop"
  info "Opened $APP_DISPLAY_NAME"
}

package_last_built() {
  local requested="${1:-}" last_config="" products debug_product release_product
  case "$requested" in
    debug|release)
      products="$(bin_path_for "$requested")"
      package_app "$requested" "$products"
      return
      ;;
    "")
      ;;
    *)
      error "Unknown package configuration: $requested"
      usage
      exit 1
      ;;
  esac

  if [[ -f "$BUILD_STATE_FILE" ]]; then
    IFS= read -r last_config <"$BUILD_STATE_FILE" || true
  fi
  if [[ "$last_config" == debug || "$last_config" == release ]]; then
    products="$(bin_path_for "$last_config")"
    if built_for_requested_arch "$products/$PRODUCT_NAME"; then
      package_app "$last_config" "$products"
      return
    fi
  fi

  debug_product="$(bin_path_for debug)"
  release_product="$(bin_path_for release)"
  if built_for_requested_arch "$debug_product/$PRODUCT_NAME" &&
      { [[ "$debug_product/$PRODUCT_NAME" -nt "$release_product/$PRODUCT_NAME" ]] ||
        ! built_for_requested_arch "$release_product/$PRODUCT_NAME"; }; then
    package_app debug "$debug_product"
  elif built_for_requested_arch "$release_product/$PRODUCT_NAME"; then
    package_app release "$release_product"
  else
    error "No built product found; run ./build.sh build-dev or ./build.sh build first"
    exit 1
  fi
}

built_for_requested_arch() {
  [[ -x "$1" ]] && lipo "$1" -verify_arch "$ARCH" 2>/dev/null
}

rebuild_and_package() {
  clean_build_caches
  build_and_package release
}

case "${1:-}" in
  "")
    # Daily default: release + open（体积小、-O 运行时性能，见头部注释）
    build_and_launch release
    ;;
  dev)
    # 快速迭代兜底：debug 编译更快，完整符号留在 .build 产物里
    build_and_launch debug
    ;;
  build-dev)
    # Debug package without open (verification / CI)
    build_and_package debug
    ;;
  build)
    # Release package without open (CI / scripts)
    build_and_package release
    ;;
  release)
    build_and_package release
    ;;
  rebuild)
    rebuild_and_package
    ;;
  package)
    package_last_built "${2:-}"
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
