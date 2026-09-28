import Foundation
import XCTest
@testable import XToolsCore

final class SourceControlCoreTests: XCTestCase {
    func testScannerDiscoversRepositoriesWithinDirectoryAndParsesStatus() async throws {
        let root = makeTemporaryDirectory()
        let repositoryPath = root.appendingPathComponent("repo").path
        try FileManager.default.createDirectory(atPath: repositoryPath, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: "\(repositoryPath)/.git", withIntermediateDirectories: true)

        let git = MockGitClient { request in
            switch request.kind {
            case .branch: return GitProcessOutput(exitCode: 0, standardOutput: "main\n")
            case .revision: return GitProcessOutput(exitCode: 0, standardOutput: "abc123\n")
            case .remote: return GitProcessOutput(exitCode: 0, standardOutput: "https://gitlab.example/acme/repo.git\n")
            case .status: return GitProcessOutput(exitCode: 0, standardOutput: "")
            case .divergence: return GitProcessOutput(exitCode: 0, standardOutput: "2\t0\n")
            default: return GitProcessOutput(exitCode: 1)
            }
        }

        let snapshot = try await SourceControlScanner(git: git).scan(scope: .directory(path: root.path))
        XCTAssertEqual(snapshot.repositories.count, 1)
        XCTAssertEqual(snapshot.repositories.first?.branch, "main")
        XCTAssertEqual(snapshot.repositories.first?.behind, 2)
        XCTAssertTrue(snapshot.repositories.first?.isFastForwardCandidate == true)
    }

    func testWorkspaceRepositoryStillDiscoversNestedRepositories() async throws {
        let root = makeTemporaryDirectory()
        let nestedPath = root.appendingPathComponent("nested").path
        try FileManager.default.createDirectory(atPath: root.appendingPathComponent(".git").path, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: nestedPath, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: "\(nestedPath)/.git", withIntermediateDirectories: true)

        let git = MockGitClient { request in
            switch request.kind {
            case .branch: return GitProcessOutput(exitCode: 0, standardOutput: "main\n")
            case .revision: return GitProcessOutput(exitCode: 0, standardOutput: "abc123\n")
            case .remote: return GitProcessOutput(exitCode: 1)
            case .status: return GitProcessOutput(exitCode: 0, standardOutput: "")
            default: return GitProcessOutput(exitCode: 1)
            }
        }

        let snapshot = try await SourceControlScanner(git: git).scan(scope: .directory(path: root.path))
        XCTAssertEqual(snapshot.repositories.map(\.path), [nestedPath])
    }

    func testDirectoryModeUsesRepositoryRootWhenNoNestedRepositoriesExist() async throws {
        let root = makeTemporaryDirectory()
        try FileManager.default.createDirectory(atPath: root.appendingPathComponent(".git").path, withIntermediateDirectories: true)

        let git = MockGitClient { request in
            switch request.kind {
            case .branch: return GitProcessOutput(exitCode: 0, standardOutput: "main\n")
            case .revision: return GitProcessOutput(exitCode: 0, standardOutput: "abc123\n")
            case .status: return GitProcessOutput(exitCode: 0)
            default: return GitProcessOutput(exitCode: 1)
            }
        }

        let snapshot = try await SourceControlScanner(git: git).scan(scope: .directory(path: root.path))
        XCTAssertEqual(snapshot.repositories.map(\.path), [root.path])
    }

    func testScannerClassifiesConflictsAndUntrackedFiles() async throws {
        let git = MockGitClient { request in
            switch request.kind {
            case .branch: return GitProcessOutput(exitCode: 0, standardOutput: "main\n")
            case .revision: return GitProcessOutput(exitCode: 0, standardOutput: "abc\n")
            case .remote: return GitProcessOutput(exitCode: 0, standardOutput: "origin\n")
            case .status: return GitProcessOutput(exitCode: 0, standardOutput: "UU file.txt\n")
            default: return GitProcessOutput(exitCode: 1)
            }
        }
        let root = makeTemporaryDirectory()
        try FileManager.default.createDirectory(atPath: "\(root.path)/.git", withIntermediateDirectories: true)
        let snapshot = try await SourceControlScanner(git: git).scan(scope: .repository(path: root.path))
        XCTAssertEqual(snapshot.repositories.first?.status, .conflicted)
        XCTAssertFalse(snapshot.repositories.first?.isFastForwardCandidate == true)
    }

    func testUpdatesOnlyFastForwardCandidatesInInputOrder() async {
        let first = SourceControlRepository(path: "/tmp/one", branch: "main", shortRevision: "a", remote: "origin", status: .clean)
        let skipped = SourceControlRepository(path: "/tmp/two", branch: "main", shortRevision: "b", remote: "origin", status: .modified)
        let third = SourceControlRepository(path: "/tmp/three", branch: "main", shortRevision: "c", remote: "origin", status: .clean)
        let git = MockGitClient { _ in GitProcessOutput(exitCode: 0, standardOutput: "Already up to date.\n") }

        let results = await SourceControlUpdateExecutor(git: git).update(repositories: [first, skipped, third])
        XCTAssertEqual(results.map(\.repository.path), ["/tmp/one", "/tmp/two", "/tmp/three"])
        XCTAssertEqual(results.map(\.outcome), [.upToDate, .skipped, .upToDate])
        let calls = await git.calls
        XCTAssertEqual(calls, [.pullFastForward, .pullFastForward])
    }

    func testRepositoryWithoutUpstreamIsNotSelectedForPull() {
        let repository = SourceControlRepository(
            path: "/tmp/no-upstream",
            branch: "main",
            shortRevision: "a",
            remote: "origin",
            status: .clean,
            hasUpstream: false
        )
        XCTAssertFalse(repository.isFastForwardCandidate)
    }

    func testUpToDateCleanRepositoryRemainsSafePullCandidate() {
        let repository = SourceControlRepository(
            path: "/tmp/up-to-date",
            branch: "main",
            shortRevision: "abc",
            remote: "origin",
            status: .clean,
            hasUpstream: true,
            remoteState: .upToDate
        )
        XCTAssertTrue(repository.isFastForwardCandidate)
    }

    func testGitLabPreflightEncodesProjectPathAndUsesTokenOnlyAsHeader() async throws {
        let transport = MockGitLabTransport { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/merge_requests") { return GitLabHTTPResponse(statusCode: 200, data: Data("[]".utf8)) }
            return GitLabHTTPResponse(statusCode: 200, data: Data("{}".utf8))
        }
        let input = GitLabMergeRequestInput(
            gitLabURL: URL(string: "https://gitlab.example")!,
            projectPath: "acme/mobile-app",
            sourceBranch: "feature/login",
            targetBranch: "main",
            title: "登录"
        )
        let result = try await GitLabMergeRequestClient(transport: transport).preflight(input, token: "secret-token")
        XCTAssertEqual(result, .ready)
        let request = await transport.requests.last
        XCTAssertTrue(request?.url?.absoluteString.contains("acme%2Fmobile-app") == true)
        XCTAssertEqual(request?.value(forHTTPHeaderField: "PRIVATE-TOKEN"), "secret-token")
    }

    func testGitLabCreateReconcilesTimeoutWithExistingMergeRequest() async throws {
        let existingJSON = "[{\"iid\":42,\"title\":\"登录\",\"source_branch\":\"feature/login\",\"target_branch\":\"main\",\"web_url\":\"https://gitlab.example/acme/mobile/-/merge_requests/42\"}]"
        let transport = MockGitLabTransport { request in
            if request.httpMethod == "POST" { throw URLError(.timedOut) }
            return GitLabHTTPResponse(statusCode: 200, data: Data(existingJSON.utf8))
        }
        let input = GitLabMergeRequestInput(
            gitLabURL: URL(string: "https://gitlab.example")!,
            projectPath: "acme/mobile",
            sourceBranch: "feature/login",
            targetBranch: "main",
            title: "登录"
        )
        let request = try await GitLabMergeRequestClient(transport: transport).create(input, token: "token")
        XCTAssertEqual(request.iid, 42)
    }

    func testGitLabPreflightReportsDuplicateOpenedMergeRequest() async throws {
        let existingJSON = "[{\"iid\":7,\"title\":\"已有请求\",\"source_branch\":\"feature/login\",\"target_branch\":\"main\"}]"
        let transport = MockGitLabTransport { request in
            if request.url?.path.hasSuffix("/merge_requests") == true {
                return GitLabHTTPResponse(statusCode: 200, data: Data(existingJSON.utf8))
            }
            return GitLabHTTPResponse(statusCode: 200, data: Data("{}".utf8))
        }
        let input = GitLabMergeRequestInput(
            gitLabURL: URL(string: "https://gitlab.example")!,
            projectPath: "acme/mobile",
            sourceBranch: "feature/login",
            targetBranch: "main",
            title: "登录"
        )

        let result = try await GitLabMergeRequestClient(transport: transport).preflight(input, token: "token")
        guard case let .duplicate(request) = result else {
            return XCTFail("Expected duplicate opened merge request")
        }
        XCTAssertEqual(request.iid, 7)
    }

    func testGitLabRejectsEmptyTokenBeforeNetworkRequest() async throws {
        let transport = MockGitLabTransport { _ in
            return GitLabHTTPResponse(statusCode: 500)
        }
        let input = GitLabMergeRequestInput(
            gitLabURL: URL(string: "https://gitlab.example.com")!,
            projectPath: "acme/mobile",
            sourceBranch: "feature/login",
            targetBranch: "main",
            title: "登录"
        )

        do {
            _ = try await GitLabMergeRequestClient(transport: transport).preflight(input, token: "  ")
            XCTFail("Expected invalid token")
        } catch let error as SourceControlError {
            XCTAssertEqual(error, .invalidToken)
        }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }

    private func makeTemporaryDirectory() -> URL {
        let path = "/tmp/xtools-source-control-tests-\(UUID().uuidString)"
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private actor MockGitClient: GitProcessClient {
    private let handler: @Sendable (GitCommandRequest) -> GitProcessOutput
    private(set) var calls: [GitCommandKind] = []

    init(handler: @escaping @Sendable (GitCommandRequest) -> GitProcessOutput) {
        self.handler = handler
    }

    func run(_ request: GitCommandRequest, timeout: Duration) async throws -> GitProcessOutput {
        calls.append(request.kind)
        return handler(request)
    }
}

private actor MockGitLabTransport: GitLabHTTPTransport {
    private let handler: @Sendable (URLRequest) throws -> GitLabHTTPResponse
    private(set) var requests: [URLRequest] = []

    init(handler: @escaping @Sendable (URLRequest) throws -> GitLabHTTPResponse) {
        self.handler = handler
    }

    func send(_ request: URLRequest) async throws -> GitLabHTTPResponse {
        requests.append(request)
        return try handler(request)
    }
}
