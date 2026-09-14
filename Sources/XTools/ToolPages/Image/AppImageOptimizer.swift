import Foundation
import XToolsCore

/// Resolves bundled/Homebrew optimizer binaries; a missing binary degrades
/// cleanly to ImageIO output so image tools never break.
enum AppImageOptimizer {
    static var searchDirectories: [String] {
        var directories: [String] = []

        // Bundled helpers (present after packaging; harmless when absent).
        if let helpers = Bundle.main.url(forResource: nil, withExtension: nil, subdirectory: "Helpers")?.path {
            directories.append(helpers)
        }
        if let resourcePath = Bundle.main.resourcePath {
            directories.append((resourcePath as NSString).appendingPathComponent("Helpers"))
        }
        directories.append(Bundle.main.bundlePath + "/Contents/Helpers")

        // Development fallbacks: Homebrew on Apple Silicon and Intel.
        directories.append("/opt/homebrew/bin")
        directories.append("/usr/local/bin")

        return directories
    }

    /// Shared optimizer; safe to capture in `@Sendable` closures (value-typed,
    /// holds only `Sendable` locator and process runner).
    static func make() -> any ExternalImageOptimizing {
        ProcessImageOptimizer(
            locator: FileSystemImageOptimizerToolLocator(searchDirectories: searchDirectories)
        )
    }
}
