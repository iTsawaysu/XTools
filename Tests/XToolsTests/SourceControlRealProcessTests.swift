import Foundation
import XCTest
@testable import XToolsCore

/// Integration tests that exercise `SystemGitProcessClient` as a real child
/// process. The mock-based core tests cannot observe process-level wedges, so
/// the scanner must also be proven against the real transport under the same
/// concurrency the UI produces (several repositories scanned in parallel).
final class SourceControlRealProcessTests: XCTestCase {
    func testRunReturnsRealGitOutput() async throws {
        let root = makeTemporaryDirectory()
        let repositoryURL = root.appendingPathComponent("repo")
        try createFixtureRepository(at: repositoryURL)

        let client = SystemGitProcessClient()
        let output = try await client.run(
            GitCommandRequest(kind: .branch, repositoryPath: repositoryURL.path),
            timeout: .seconds(10)
        )

        XCTAssertEqual(output.exitCode, 0)
        XCTAssertEqual(output.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines), "main")
    }

    /// Regression test: scanning several repositories concurrently used to
    /// wedge the cooperative pool permanently. The watchdog fails the test
    /// instead of hanging the suite if that ever comes back.
    func testScannerScansMultipleRepositoriesUnderRealConcurrency() async throws {
        let root = makeTemporaryDirectory()
        let repositoryCount = 6
        for index in 0..<repositoryCount {
            try createFixtureRepository(at: root.appendingPathComponent("repo-\(index)"))
        }

        let started = Date()
        let snapshot = try await withThrowingTaskGroup(of: SourceControlScanSnapshot?.self) { group -> SourceControlScanSnapshot in
            group.addTask { () -> SourceControlScanSnapshot? in
                try await SourceControlScanner(git: SystemGitProcessClient(), maximumConcurrentRepositories: 4)
                    .scan(scope: .directory(path: root.path))
            }
            group.addTask { () -> SourceControlScanSnapshot? in
                do { try await Task.sleep(for: .seconds(30)) } catch { return nil }
                XCTFail("Workspace scan wedged: concurrent Git processes must not deadlock the cooperative pool")
                throw SourceControlError.timedOut
            }
            let first = try await group.next() ?? nil
            group.cancelAll()
            guard let snapshot = first else { throw SourceControlError.timedOut }
            return snapshot
        }
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertEqual(snapshot.repositories.count, repositoryCount)
        XCTAssertTrue(snapshot.repositories.allSatisfy { $0.branch == "main" })
        XCTAssertLessThan(elapsed, 30, "Scanning \(repositoryCount) tiny repositories must stay interactive (took \(elapsed)s)")
    }

    /// A child that outlives its timeout (here via an orphaned `sleep` holding
    /// the pipe, mirroring an orphaned ssh) must still surface as `.timedOut`
    /// within the timeout plus the bounded drain grace.
    func testRunTimesOutWithinBoundedGrace() async throws {
        let script = makeExecutableScript(body: "#!/bin/sh\necho partial-output\nsleep 30\n")
        let client = SystemGitProcessClient(executableURL: script)

        let started = Date()
        do {
            _ = try await client.run(
                GitCommandRequest(kind: .status, repositoryPath: "/tmp"),
                timeout: .seconds(1)
            )
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(error as? SourceControlError, .timedOut, "Unexpected error: \(error)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 10, "Timeout must not wait out the full child runtime")
    }

    /// Cancelling a running scan must terminate the child and return promptly.
    func testRunReportsCancellationPromptly() async throws {
        let script = makeExecutableScript(body: "#!/bin/sh\nsleep 30\n")
        let client = SystemGitProcessClient(executableURL: script)

        let started = Date()
        let task = Task {
            try await client.run(
                GitCommandRequest(kind: .status, repositoryPath: "/tmp"),
                timeout: .seconds(30)
            )
        }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertEqual(error as? SourceControlError, .cancelled, "Unexpected error: \(error)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 10, "Cancellation must not wait out the full child runtime")
    }

    // MARK: - Fixtures

    private func makeTemporaryDirectory() -> URL {
        let url = URL(fileURLWithPath: "/tmp/xtools-source-control-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func createFixtureRepository(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try runGit(["init", "-q", "-b", "main", url.path])
        try "fixture".write(to: url.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        try runGit(["-C", url.path, "add", "-A"])
        try runGit(["-C", url.path, "-c", "user.email=test@example.com", "-c", "user.name=Test", "commit", "-qm", "init"])
    }

    private func runGit(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "SourceControlRealProcessTests", code: Int(process.terminationStatus))
        }
    }

    private func makeExecutableScript(body: String) -> URL {
        let url = makeTemporaryDirectory().appendingPathComponent("slow-command.sh")
        try? body.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}
