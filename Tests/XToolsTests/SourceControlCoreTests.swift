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

    // MARK: - Pull failure classification

    func testPullFailureClassifiesDirtyWorktreeDivergenceAndRemoteErrors() {
        XCTAssertEqual(
            SourceControlDiagnostic.pullFailure(standardError: "error: Your local changes to the following files would be overwritten by merge:\n\tfile.swift\nPlease commit your changes or stash them before you merge.").code,
            "pull-dirty-worktree"
        )
        XCTAssertEqual(
            SourceControlDiagnostic.pullFailure(standardError: "fatal: Not possible to fast-forward, aborting.").code,
            "pull-diverged"
        )
        XCTAssertEqual(
            SourceControlDiagnostic.pullFailure(standardError: "git@gitlab.example: Permission denied (publickey).\nfatal: Could not read from remote repository.").code,
            "pull-remote-unavailable"
        )
        XCTAssertEqual(
            SourceControlDiagnostic.pullFailure(standardError: "fatal: unable to access 'https://gitlab.example/acme/repo.git/': timed out").code,
            "pull-remote-unavailable"
        )
    }

    func testPullFailureFallbackCarriesFirstStderrLine() {
        let diagnostic = SourceControlDiagnostic.pullFailure(standardError: "\nfatal: weird failure\nsecond line")
        XCTAssertEqual(diagnostic.code, "pull-failed")
        XCTAssertTrue(diagnostic.summary.contains("fatal: weird failure"))
        XCTAssertFalse(diagnostic.summary.contains("second line"))
    }

    func testExecutorSurfacesClassifiedPullFailureDiagnostic() async {
        let repository = SourceControlRepository(
            path: "/tmp/pull-failure",
            branch: "main",
            shortRevision: "abc",
            remote: "origin",
            status: .clean,
            upstream: "origin/main",
            revision: "abc123",
            remoteState: .upToDate
        )
        let git = MockGitClient { request in
            switch request.kind {
            case .pullFastForward:
                return GitProcessOutput(
                    exitCode: 1,
                    standardError: "error: Your local changes to the following files would be overwritten by merge"
                )
            default: return GitProcessOutput(exitCode: 0)
            }
        }

        let results = await SourceControlUpdateExecutor(git: git).update(repositories: [repository])
        guard case let .failed(diagnostic)? = results.first?.outcome else {
            return XCTFail("Expected classified pull failure")
        }
        XCTAssertEqual(diagnostic.code, "pull-dirty-worktree")
    }

    // MARK: - Force update

    /// 强制更新只放开「工作区必须干净」的预检：非快进候选默认跳过，
    /// force 时执行 pull，且不再因脏状态中断（identity 校验仍保留）。
    func testForceUpdateBypassesCleanWorktreeRequirement() async {
        let root = makeTemporaryDirectory()
        try? FileManager.default.createDirectory(atPath: "\(root.path)/.git", withIntermediateDirectories: true)
        let repository = SourceControlRepository(
            path: root.path,
            branch: "main",
            shortRevision: "abc",
            remote: "origin",
            status: .modified,
            upstream: "origin/main",
            revision: "abc123",
            remoteState: .upToDate
        )
        let git = MockGitClient { request in
            switch request.kind {
            case .repositoryRoot: return GitProcessOutput(exitCode: 0, standardOutput: request.repositoryPath + "\n")
            case .branch: return GitProcessOutput(exitCode: 0, standardOutput: "main\n")
            case .revision: return GitProcessOutput(exitCode: 0, standardOutput: "abc123\n")
            case .upstream: return GitProcessOutput(exitCode: 0, standardOutput: "origin/main\n")
            case .status: return GitProcessOutput(exitCode: 0, standardOutput: " M file.swift\n")
            case .pullFastForward: return GitProcessOutput(exitCode: 0, standardOutput: "Already up to date.\n")
            default: return GitProcessOutput(exitCode: 0)
            }
        }
        let executor = SourceControlUpdateExecutor(git: git)

        let skipped = await executor.update(repositories: [repository])
        guard case .skipped? = skipped.first?.outcome else {
            return XCTFail("Expected dirty repository to be skipped without force")
        }

        let forced = await executor.update(repositories: [repository], force: true)
        guard case .upToDate? = forced.first?.outcome else {
            return XCTFail("Expected forced pull to run despite dirty worktree, got \(String(describing: forced.first?.outcome))")
        }
        let calls = await git.calls
        XCTAssertEqual(calls.filter { $0 == .pullFastForward }.count, 1, "Only the forced run should pull")
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
