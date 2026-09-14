import Foundation
import Testing

/// Shared support for source-string view-structure contract tests.
///
/// These helpers intentionally read Swift source files and assert that they
/// contain or omit literal structure markers. This is a transitional but
/// deliberate seam for SwiftUI/AppKit declarative wiring that this toolchain
/// cannot introspect at runtime. Logic-level behavior should still move to
/// normal behavior tests whenever there is a real seam.
///
/// The source-string suites protect page composition, control order, and
/// SwiftUI/AppKit wiring such as semantic workspace entry points, AppKit field
/// bridges, diagnostic anchors, and unavailable legacy components. They should
/// not be rewritten into ViewInspector, snapshot, or runtime rendering tests
/// until a supported and stable view-introspection seam exists for this project.

/// Raised when the package root cannot be located while reading a source file.
private struct MissingPackageRootError: Error {}

func contains(_ source: String, _ needle: String, _ message: String, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(source.contains(needle), Comment(rawValue: message), sourceLocation: sourceLocation)
}

func doesNotContain(_ source: String, _ needle: String, _ message: String, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(!source.contains(needle), Comment(rawValue: message), sourceLocation: sourceLocation)
}

func occurrenceCount(_ source: String, _ needle: String, _ minimum: Int, _ message: String, sourceLocation: SourceLocation = #_sourceLocation) {
    let count = source.components(separatedBy: needle).count - 1
    #expect(count >= minimum, Comment(rawValue: "\(message). Expected at least \(minimum), got \(count)"), sourceLocation: sourceLocation)
}

func appearsBefore(_ source: String, _ first: String, _ second: String, _ message: String, sourceLocation: SourceLocation = #_sourceLocation) {
    guard let firstRange = source.range(of: first), let secondRange = source.range(of: second) else {
        Issue.record(Comment(rawValue: "\(message). Could not find expected markers."), sourceLocation: sourceLocation)
        return
    }
    #expect(firstRange.lowerBound < secondRange.lowerBound, Comment(rawValue: message), sourceLocation: sourceLocation)
}

func sourceSlice(
    _ source: String,
    from start: String,
    to end: String,
    sourceLocation: SourceLocation = #_sourceLocation
) -> String {
    guard let startRange = source.range(of: start),
          let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
        Issue.record(Comment(rawValue: "Could not find expected source slice."), sourceLocation: sourceLocation)
        return source
    }
    return String(source[startRange.lowerBound..<endRange.lowerBound])
}

func readSource(_ relativePath: String) throws -> String {
    let url = try sourcePackageRoot()
        .appendingPathComponent(relativePath)
    return try String(contentsOf: url, encoding: .utf8)
}

func sourcePackageRoot() throws -> URL {
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

func readSharedBagComponents() throws -> String {
    let parts = [
        try readSource("Sources/XTools/ToolPages/Workbench/PageChrome/IndexPageShell.swift"),
        try readSource("Sources/XTools/ToolPages/Workbench/PageChrome/IndexWorkspaceSurfaces.swift"),
        try readSource("Sources/XTools/ToolPages/Workbench/Diagnostics/IndexResultDisplays.swift"),
    ]
    return parts.joined(separator: "\n")
}

