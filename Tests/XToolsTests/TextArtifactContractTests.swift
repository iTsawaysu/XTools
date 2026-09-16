import Foundation
import Testing

/// Contract tests for **text artifacts** — `build.sh` and `README.md`.
///
/// Unlike the UI source-string tests (see `UIInfrastructureSourceTests`), these
/// legitimately assert on file *text* rather than program behavior: their
/// subject genuinely IS a shell script and a Markdown document. There is no
/// runtime object to construct or behavior to observe — the "behavior" of a
/// build script is the ordered commands it contains, and matching that text is
/// the honest way to pin it down. So these do not need to be migrated to
/// behavior tests; they are correctly text-based by nature.
///
/// Split out of `UIInfrastructureSourceTests` (ticket 02) precisely to make the
/// distinction visible: both files are permanent text contracts, but for
/// different subjects. This file pins text artifacts whose observable contract
/// is their source text; `UIInfrastructureSourceTests` pins SwiftUI declarative
/// structure that has no supported runtime introspection seam on this toolchain.
struct TextArtifactContractTests {
    @Test func packagingStripsBinaryBeforeCodesignForEveryConfiguration() throws {
        let source = try Self.readSource("build.sh")

        #expect(source.contains("strip -S -x \"$APP_BINARY\"")) // strip local symbols from the packaged app binary
        #expect(!source.contains("if [[ \"$configuration\" == \"release\" ]]; then")) // stripping is no longer gated to release
        try Self.orderedBefore(source, "strip -S -x \"$APP_BINARY\"", "codesign --force --sign - \"$APP_PATH\"") // strip before codesign
        #expect(!source.contains("codesign --force --deep")) // this bundle has no nested code that needs recursive signing
        #expect(source.contains("binary_size=\"$(du -h \"$APP_BINARY\" | awk '{print $1}')\"")) // compute the main binary size
        #expect(source.contains("stripped: -S -x")) // log marks the packaged binary as stripped
        #expect(source.contains("configuration: $configuration")) // log distinguishes debug vs release packages
        #expect(source.contains("$(elapsed \"$t0\")ms)\"")) // include packaging time without pinning the complete log line
        #expect(source.contains("package_app debug")) // dev packaging keeps the debug compile path
    }

    @Test func buildHygieneDocumentsBuildAndTestEntrypointsAndCachePolicy() throws {
        let script = try Self.readSource("build.sh")
        let readme = try Self.readSource("README.md")

        #expect(readme.contains("## Quick Start")) // keep source-build instructions discoverable from installation
        #expect(readme.contains("Build from Source")) // distinguish source builds from release downloads
        #expect(readme.contains("macOS 13+")) // document the supported runtime baseline
        #expect(readme.contains("Xcode 16+")) // document the required build toolchain
        #expect(readme.contains("git clone https://github.com/iTsawaysu/XTools.git")) // provide the repository bootstrap command
        #expect(readme.contains("./build.sh           # Incremental debug build & open app")) // document the daily development entrypoint
        #expect(readme.contains("./build.sh release   # Production release build")) // document the release packaging entrypoint
        #expect(readme.contains("swift test           # Run automated test suite")) // document the full test entrypoint beside build commands
        #expect(readme.contains("Run `swift test` before submitting")) // contributors must run the same public test entrypoint
        #expect(script.contains("TRASH_DIR=\"${TRASH_DIR:-${TMPDIR:-/tmp}/XTools-build-archive}\"")) // use a portable default while allowing overrides

        #expect(script.contains("BUILD_DIR=\"$PROJECT_DIR/.build\"")) // build.sh shares the cache warmed by swift build/test
        #expect(script.contains("LEGACY_SCRATCH_DIR=\"$PROJECT_DIR/.swiftpm-build\"")) // retain cleanup compatibility for the old cache
        #expect(script.contains("archive_path \"$BUILD_DIR\" \".build\"")) // clean archives the active shared cache
        #expect(script.contains("archive_path \"$LEGACY_SCRATCH_DIR\" \".swiftpm-build\"")) // clean archives the legacy scratch path
        #expect(script.contains("mkdir -p \"$TRASH_DIR\"")) // create the archive destination before moving
        #expect(script.contains("mv \"$path\" \"$target\"")) // move build artifacts instead of deleting
        #expect(!script.contains("rm -rf")) // clean must not delete directories destructively
        #expect(!script.contains("rm -r")) // clean must not delete directories destructively
        #expect(!script.contains("find . -delete")) // clean must not delete directories destructively
    }

    @Test func packagingCopiesSwiftPMResourceBundlesBeforeCodesign() throws {
        let source = try Self.readSource("build.sh")

        #expect(source.contains("$BUILD_DIR/out/Products/$configuration_directory")) // support current SwiftPM/Xcode product layout
        try Self.orderedBefore(
            source,
            "$BUILD_DIR/out/Products/$configuration_directory",
            "$BUILD_DIR/arm64-apple-macosx/$configuration"
        ) // never package a stale legacy product when the current build exists
        #expect(source.contains("copy_swiftpm_resource_bundles \"$build_product_dir\""))
        #expect(source.contains("-name '*.bundle' -print0")) // discover every direct SwiftPM resource bundle beside the executable
        #expect(source.contains("*LogicTests*.bundle|*Tests*.bundle)")) // never package test-target resource bundles
        #expect(source.contains("destination=\"$APP_RESOURCES/$bundle_name\"")) // current SwiftPM accessor searches Bundle.main.resourceURL for packaged apps
        #expect(source.contains("legacy_destination=\"$APP_PATH/$bundle_name\"")) // archive root-level bundles left by the broken packaging path
        #expect(source.contains("/usr/bin/ditto \"$resource_bundle\" \"$destination\"")) // copy bundle directories without destructive cleanup
        #expect(source.contains("Readability-0.6.0.js")) // fail packaging if the HTML article extractor resource is absent
        try Self.orderedBefore(
            source,
            "copy_swiftpm_resource_bundles \"$build_product_dir\"",
            "codesign --force --sign - \"$APP_PATH\""
        )
    }

    // MARK: - Text-matching helpers
    //
    // These mirror the private helpers in the source-string test files. The
    // duplication matches the existing per-file convention in this test target
    // (ToolRoutingSourceTests and UIInfrastructureSourceTests each keep their
    // own copies) — kept local to avoid widening this ticket into a shared-
    // helper refactor.

    /// Raised when an ordering marker is missing from the source under test.
    private struct MissingMarkerError: Error { let message: String }

    /// Raised when the package root cannot be located.
    private struct MissingPackageRootError: Error {}

    private static func orderedBefore(_ source: String, _ first: String, _ second: String) throws {
        guard let firstRange = source.range(of: first),
              let secondRange = source.range(of: second) else {
            throw MissingMarkerError(message: "Missing one or both ordering markers: \(first) / \(second)")
        }

        #expect(firstRange.lowerBound < secondRange.lowerBound)
    }

    private static func readSource(_ relativePath: String) throws -> String {
        let url = try packageRoot()
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func packageRoot() throws -> URL {
        let fileManager = FileManager.default
        var current = URL(fileURLWithPath: fileManager.currentDirectoryPath)

        while true {
            let packageFile = current.appendingPathComponent("Package.swift").path
            let sourceDirectory = current.appendingPathComponent("Sources/XTools").path
            if fileManager.fileExists(atPath: packageFile),
               fileManager.fileExists(atPath: sourceDirectory) {
                return current
            }

            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                throw MissingPackageRootError()
            }
            current = parent
        }
    }
}
