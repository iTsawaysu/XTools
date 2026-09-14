# XTools

Developer utility app for local text, image, time, web, crypto, and conversion
workflows on macOS 13+.

## Layout

```text
XTools/
├── Package.swift              # name: XTools
│                              # product: executable XTools only
│                              # targets: XToolsCore, XTools,
│                              #          EmojiCatalogCompiler, XToolsTests
├── Sources/XTools/            # App shell, ToolPages, ToolRegistry, Shared
├── Sources/XToolsCore/        # UI-free domain logic + Resources
├── Tests/XToolsTests/
├── tools/EmojiCatalogCompiler/
├── Assets/                    # App icon for packaging
├── build.sh                   # → build/XTools.app (bundle id com.sun.xtools)
└── build/XTools.app           # packaged app (gitignored / local output)
```

| Target | Role |
|---|---|
| `XToolsCore` | Domain parsers, budgets, converters; package resources. Internal library target (not a product). |
| `XTools` | `@main` app (`XToolsApp`), AppShell, tool pages, registry. Executable product. |
| `EmojiCatalogCompiler` | Offline emoji catalog generator under `tools/`. Not shipped as an app product. |
| `XToolsTests` | Behavior and source-contract tests. |

## Build and package

```bash
./build.sh           # incremental debug build + package + open
./build.sh build     # same, do not open
./build.sh release   # release build + package
./build.sh package   # package last built product only
./build.sh clean     # move caches to the temporary archive (non-destructive)
swift test           # full test suite
```

Daily packaging compiles with `-c debug` for speed, always `strip -S -x` the
binary in `build/XTools.app`, skips test resource bundles, then ad-hoc codesigns.
Default bundle identifier: `com.sun.xtools`.

## Build Hygiene

### Toolchain

`build.sh` resolves the Swift toolchain and macOS SDK through `xcrun` against the
active Xcode (`xcode-select -p`) — it no longer hard-codes a Command Line Tools
path. Both `SWIFT_BIN` and `SDK_PATH` are overridable from the environment, so a
specific toolchain can still be pinned (e.g.
`SWIFT_BIN=/Library/Developer/CommandLineTools/usr/bin/swift`). Under the Xcode
toolchain the search-path warning documented below no longer appears; it is kept
as historical context and still applies only if you pin Command Line Tools.

### CommandLineTools search path warning

When the build is pinned to Command Line Tools (via `SWIFT_BIN`), that
installation can emit linker warnings for missing search paths under
`/Library/Developer/CommandLineTools/Developer/...`, for
example:

- `/Library/Developer/CommandLineTools/Developer/usr/lib`
- `/Library/Developer/CommandLineTools/Developer/Library/Frameworks`

This warning also reproduces with a plain `swift test`, so `build.sh` does not add those `/Library/Developer/CommandLineTools/Developer/...` search paths. The directories are absent in this local CLT layout, while the actual Swift and SDK paths live under `/Library/Developer/CommandLineTools/usr/bin/swift` and `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`.

Do not add ad-hoc `LIBRARY_PATH`, `FRAMEWORK_SEARCH_PATHS`, or fake directory workarounds just to hide the warning. Treat it as a toolchain search-path warning unless a future Xcode/CLT install changes the diagnosis.

### SwiftPM build caches

`build.sh` intentionally uses the shared `.build` directory, matching plain `swift build` and `swift test`. Reusing the same SwiftPM cache keeps the daily debug packaging path incremental instead of maintaining a second cold build tree. The legacy `.swiftpm-build` directory may still exist from older versions of the script, but it is no longer the active scratch path.

Both directories are build caches, not app bundle contents, and should not be used to explain the packaged app size. `./build.sh clean` moves the shared `.build`, legacy `.swiftpm-build`, `build`, and legacy `dist` directories into `${TRASH_DIR:-${TMPDIR:-/tmp}/XTools-build-archive}` instead of deleting them, matching the project rule against destructive cleanup. Set `TRASH_DIR` to choose a persistent archive location, for example `TRASH_DIR="$PWD/.build-archive" ./build.sh clean`; the default is portable and scoped to XTools build artifacts.

### Packaged app size

Daily packaging still compiles with `-c debug` for speed, but `package_app`
always runs `strip -S -x` on the binary copied into `XTools.app` (then ad-hoc
codesign). Measure size with `du -sh build/XTools.app` after `./build.sh` /
`./build.sh package`; do not use the unstripped product under `.build` or a
pre-strip binary as the app size. Packaging also skips SwiftPM test-target
resource bundles (`*LogicTests*` / `*Tests*`) so fixtures never ship inside the
app. Need full symbols for Instruments? Use the product under `.build`, not the
stripped payload in `build/XTools.app`.
