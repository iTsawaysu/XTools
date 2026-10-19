import Foundation
import Testing

/// Runs `tools/ui-lint.py` so `swift test` and the build script share one
/// guardrail. The lint owns the rules; this test only proves the gate is wired.
struct UILintContractTests {
    @Test func toolPagesStayWithinTheDesignLintBaseline() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "tools/ui-lint.py"]
        process.currentDirectoryURL = root

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(process.terminationStatus == 0, "\(output)")
    }
}
