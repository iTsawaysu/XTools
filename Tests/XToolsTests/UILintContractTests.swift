import Foundation
import Testing

@Suite struct UILintContractTests {
    @Test func repositoryPassesUILint() throws {
        let root = TestMarkdownCaseSupport.repositoryRoot()
        let result = try runLint(root: root)
        #expect(result.status == 0, "ui-lint failed:\n\(result.output)")
    }

    @Test func lintCollectsAllViolationsEvenWhenOutputExceedsPipeCapacity() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xtools-ui-lint-\(UUID().uuidString)")
        let page = root
            .appendingPathComponent("Sources/XTools/ToolPages/FixturePage.swift")
        try FileManager.default.createDirectory(
            at: page.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let violationCount = 900
        let modifiers = String(repeating: "            .buttonStyle(.plain)\n", count: violationCount)
        let source = "struct FixturePage: View {\n    var body: some View {\n        Button(\"x\") {}\n"
            + modifiers + "    }\n}\n"
        try source.write(to: page, atomically: true, encoding: .utf8)

        let result = try runLint(root: root)
        #expect(result.status == 1)
        #expect(result.output.split(separator: "\n").filter { $0.contains("page-plain-button-style") }.count == violationCount)
    }

    private func runLint(root: URL) throws -> (status: Int32, output: String) {
        let script = TestMarkdownCaseSupport.repositoryRoot()
            .appendingPathComponent("tools/ui-lint.py")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", script.path, "--root", root.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(decoding: data, as: UTF8.self)
        )
    }
}
