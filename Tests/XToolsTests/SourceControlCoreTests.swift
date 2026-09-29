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
            case .statusV2: return GitProcessOutput(exitCode: 0, standardOutput: "# branch.oid abc123\n# branch.head main\n# branch.upstream origin/main\n# branch.ab +0 -2\n")
            case .remote: return GitProcessOutput(exitCode: 0, standardOutput: "https://gitlab.example/acme/repo.git\n")
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
            case .statusV2: return GitProcessOutput(exitCode: 0, standardOutput: "# branch.oid abc123\n# branch.head main\n")
            case .remote: return GitProcessOutput(exitCode: 1)
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
            case .statusV2: return GitProcessOutput(exitCode: 0, standardOutput: "# branch.oid abc123\n# branch.head main\n")
            default: return GitProcessOutput(exitCode: 1)
            }
        }

        let snapshot = try await SourceControlScanner(git: git).scan(scope: .directory(path: root.path))
        XCTAssertEqual(snapshot.repositories.map(\.path), [root.path])
    }

    func testScannerClassifiesConflictsAndUntrackedFiles() async throws {
        let git = MockGitClient { request in
            switch request.kind {
            case .statusV2: return GitProcessOutput(exitCode: 0, standardOutput: "# branch.oid abc\n# branch.head main\nu AA 3 000000 100644 100644 h1 h2 file.txt\n? other.txt\n")
            case .remote: return GitProcessOutput(exitCode: 0, standardOutput: "origin\n")
            default: return GitProcessOutput(exitCode: 1)
            }
        }
        let root = makeTemporaryDirectory()
        try FileManager.default.createDirectory(atPath: "\(root.path)/.git", withIntermediateDirectories: true)
        let snapshot = try await SourceControlScanner(git: git).scan(scope: .repository(path: root.path))
        XCTAssertEqual(snapshot.repositories.first?.status, .conflicted)
        XCTAssertFalse(snapshot.repositories.first?.isFastForwardCandidate == true)
    }

    // MARK: - Scan progress & offline classification

    func testScanReportsDiscoveryAndReadProgress() async throws {
        let root = makeTemporaryDirectory()
        for name in ["one", "two", "three"] {
            try FileManager.default.createDirectory(atPath: "\(root.path)/\(name)/.git", withIntermediateDirectories: true)
        }
        let git = MockGitClient { request in
            switch request.kind {
            case .statusV2: return GitProcessOutput(exitCode: 0, standardOutput: "# branch.oid abc123\n# branch.head main\n")
            case .remote: return GitProcessOutput(exitCode: 1)
            default: return GitProcessOutput(exitCode: 1)
            }
        }
        final class ProgressBox: @unchecked Sendable {
            private let lock = NSLock()
            private var storage: [SourceControlScanProgress] = []
            func append(_ progress: SourceControlScanProgress) {
                lock.lock(); storage.append(progress); lock.unlock()
            }
            var values: [SourceControlScanProgress] {
                lock.lock(); defer { lock.unlock() }
                return storage
            }
        }
        let events = ProgressBox()
        _ = try await SourceControlScanner(git: git).scan(scope: .directory(path: root.path)) { _ in } onProgress: { progress in
            events.append(progress)
        }
        let progressEvents = events.values

        let walkEvents = progressEvents.filter { $0.readTotalCount == nil }
        let readEvents = progressEvents.filter { $0.readTotalCount != nil }
        XCTAssertFalse(walkEvents.isEmpty, "目录遍历期应上报发现计数")
        XCTAssertEqual(walkEvents.map(\.discoveredCount), walkEvents.map(\.discoveredCount).sorted(), "发现计数应单调递增")
        XCTAssertFalse(readEvents.isEmpty, "读取期应上报 N/M 进度")
        XCTAssertEqual(readEvents.last?.readTotalCount, 3)
        XCTAssertEqual(readEvents.last?.readCompletedCount, 3)
    }

    /// 扫描离线化：不再逐仓 `ls-remote`，干净且与本地跟踪一致的仓库直接判 upToDate。
    func testCleanRepositoryClassifiesUpToDateWithoutRemoteLookup() async throws {
        let root = makeTemporaryDirectory()
        try FileManager.default.createDirectory(atPath: "\(root.path)/.git", withIntermediateDirectories: true)
        let git = MockGitClient { request in
            switch request.kind {
            case .statusV2: return GitProcessOutput(exitCode: 0, standardOutput: "# branch.oid abc123\n# branch.head main\n# branch.upstream origin/main\n# branch.ab +0 -0\n")
            case .remote: return GitProcessOutput(exitCode: 0, standardOutput: "origin\thttps://gitlab.example/acme/repo.git (fetch)\n")
            default: return GitProcessOutput(exitCode: 1)
            }
        }

        let snapshot = try await SourceControlScanner(git: git).scan(scope: .repository(path: root.path))
        XCTAssertEqual(snapshot.repositories.first?.remoteState, .upToDate)
        XCTAssertTrue(snapshot.repositories.first?.isFastForwardCandidate == true)
        let calls = await git.calls
        // 单仓扫描只允许这四条命令；不再有逐项查询，也不发起任何网络请求。
        XCTAssertEqual(Set(calls), [.statusV2, .remote, .branches, .defaultBranch], "扫描命令面应为固定的四条白名单命令")
        XCTAssertEqual(calls.count, 4, "每仓恰好四条命令")
    }

    // MARK: - Porcelain v2 snapshot parsing

    func testStatusV2SnapshotParsesDetachedInitialAndRecordPrecedence() {
        let detached = GitStatusV2Snapshot(statusV2: "# branch.oid deadbeef\n# branch.head (detached)\n")
        XCTAssertEqual(detached.branch, "HEAD")
        XCTAssertEqual(detached.worktreeStatus, .detached, "分离头指针优先于工作区条目")

        let initial = GitStatusV2Snapshot(statusV2: "# branch.oid (initial)\n# branch.head main\n")
        XCTAssertNil(initial.revision, "尚无提交的仓库 HEAD 为空而非读取失败")
        XCTAssertEqual(initial.worktreeStatus, .clean)
        XCTAssertNil(initial.upstream)

        let diverged = GitStatusV2Snapshot(
            statusV2: "# branch.oid abc\n# branch.head feat\n# branch.upstream origin/feat\n# branch.ab +3 -5\n? new.txt\n1 .M N... 100644 100644 100644 h1 h2 a.swift\n"
        )
        XCTAssertEqual(diverged.branch, "feat")
        XCTAssertEqual(diverged.revision, "abc")
        XCTAssertEqual(diverged.upstream, "origin/feat")
        XCTAssertEqual(diverged.ahead, 3)
        XCTAssertEqual(diverged.behind, 5)
        XCTAssertEqual(diverged.worktreeStatus, .untracked, "untracked 优先于 modified")

        let conflicted = GitStatusV2Snapshot(
            statusV2: "# branch.oid abc\n# branch.head main\nu AA 3 000000 100644 100644 h1 h2 file.txt\n? other.txt\n"
        )
        XCTAssertEqual(conflicted.worktreeStatus, .conflicted, "未合并记录优先级最高")
    }

    func testDiagnosticShortLabelMapsCommonCodes() {
        XCTAssertEqual(SourceControlDiagnostic(code: "pull-dirty-worktree", summary: "", recovery: "").shortLabel, "本地改动会被覆盖")
        XCTAssertEqual(SourceControlDiagnostic(code: "stale-snapshot", summary: "", recovery: "").shortLabel, "仓库已变化")
        XCTAssertEqual(SourceControlDiagnostic(code: "pull-remote-unavailable", summary: "", recovery: "").shortLabel, "远端不可达")
        XCTAssertEqual(SourceControlDiagnostic(code: "totally-unknown", summary: "", recovery: "").shortLabel, "失败")
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
            case .statusV2: return GitProcessOutput(exitCode: 0, standardOutput: "# branch.oid abc123\n# branch.head main\n# branch.upstream origin/main\n1 .M N... 100644 100644 100644 h1 h2 file.swift\n")
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
