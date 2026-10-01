import XCTest
import XToolsCore
@testable import XTools

/// 仓库同步 workspace model 的行为测试：默认全选、可见行三态切换、
/// 部分失败汇总、失败项重试、扫描范围持久化。
@MainActor
final class SourceControlWorkspaceModelTests: XCTestCase {
    func testScanSelectsAllRepositoriesByDefault() async throws {
        let fixture = makeFixtureHome(repositories: ["work/alpha", "work/beta", "work/gamma"])
        let model = makeModel(home: fixture.home, git: fixture.git)

        model.scan()
        await waitUntil { !model.isScanning && !model.repositories.isEmpty }

        XCTAssertEqual(model.repositories.count, 3)
        XCTAssertEqual(model.selectedPaths, Set(model.repositories.map(\.path)))
    }

    func testVisibleSelectionTogglesAndClears() async throws {
        let fixture = makeFixtureHome(repositories: ["work/alpha", "work/beta"])
        let model = makeModel(home: fixture.home, git: fixture.git)
        model.scan()
        await waitUntil { !model.isScanning }

        let paths = model.repositories.map(\.path)
        let subset = Set([paths[0]])
        model.setVisibleSelection(subset, selected: false)
        XCTAssertEqual(model.selectedPaths, Set([paths[1]]))

        model.selectAll()
        XCTAssertEqual(model.selectedPaths, Set(paths))

        model.clearSelection()
        XCTAssertTrue(model.selectedPaths.isEmpty)
    }

    func testUpdatePartialFailureProducesSummaryWithoutBlockingOthers() async throws {
        let fixture = makeFixtureHome(repositories: ["work/alpha", "work/broken", "work/gamma"])
        let brokenPath = "\(fixture.home.path)/work/broken"
        await fixture.git.setFailingPullPaths([brokenPath])
        let model = makeModel(home: fixture.home, git: fixture.git)
        model.scan()
        await waitUntil { !model.isScanning }
        let total = model.repositories.count

        model.update()
        await waitUntil { !model.isUpdating && !model.isScanning }

        let outcomes = model.operationResultsByID.values.map(\.outcome)
        XCTAssertEqual(outcomes.filter { if case .upToDate = $0 { return true }; return false }.count, total - 1)
        XCTAssertEqual(model.failureSummary.count, 1)
        XCTAssertEqual(model.failureSummary.first?.repository.path, brokenPath)
        XCTAssertEqual(model.failureSummary.first?.diagnostic.code, "pull-dirty-worktree")
        XCTAssertEqual(model.lastCompletion?.failedCount, 1)
    }

    func testRetryFailuresRetriesOnlyFailedRepositories() async throws {
        let fixture = makeFixtureHome(repositories: ["work/alpha", "work/broken"])
        let brokenPath = "\(fixture.home.path)/work/broken"
        await fixture.git.setFailingPullPaths([brokenPath])
        let model = makeModel(home: fixture.home, git: fixture.git)
        model.scan()
        await waitUntil { !model.isScanning }
        model.update()
        await waitUntil { !model.isUpdating && !model.isScanning }
        XCTAssertEqual(model.failureSummary.count, 1)

        await fixture.git.setFailingPullPaths([])
        let brokenOutcomeBefore = model.operationResultsByID[brokenPath]?.outcome
        XCTAssertTrue({ if case .failed = brokenOutcomeBefore { return true }; return false }())

        model.retryFailures()
        await waitUntil { !model.isUpdating && !model.isScanning }

        XCTAssertTrue(model.failureSummary.isEmpty)
        let brokenOutcome = model.operationResultsByID[brokenPath]?.outcome
        XCTAssertTrue({ if case .upToDate = brokenOutcome { return true }; return false }(), "重试后失败仓库应变为已最新")
        // 未失败的仓库结果在重试批次中被保留。
        let alphaOutcome = model.operationResultsByID.values.first { !$0.repository.path.hasSuffix("broken") }?.outcome
        XCTAssertTrue({ if case .upToDate = alphaOutcome { return true }; return false }())
    }

    /// 真实缺陷回归：失败后的刷新扫描如果显示仓库变脏（非快进候选），
    /// 重试必须回退到失败时的快照，而不是把脏快照交给执行器跳过。
    func testRetryFailuresFallsBackToSnapshotWhenRefreshShowsNonFastForward() async throws {
        let fixture = makeFixtureHome(repositories: ["work/broken"])
        let brokenPath = "\(fixture.home.path)/work/broken"
        let model = makeModel(home: fixture.home, git: fixture.git)
        model.scan()
        await waitUntil { !model.isScanning }

        // 扫描后仓库变脏：更新时快照校验失败；随后的刷新扫描把它标记为不可快进。
        await fixture.git.setDirtyStatusPaths([brokenPath])
        model.update()
        await waitUntil { !model.isUpdating && !model.isScanning }
        XCTAssertEqual(model.failureSummary.count, 1)
        XCTAssertEqual(model.repositories.first { $0.path == brokenPath }?.isFastForwardCandidate, false)

        // 用户清理了仓库：磁盘已恢复干净，重试应回退到失败时的快照并成功拉取。
        await fixture.git.setDirtyStatusPaths([])
        model.retryFailures()
        await waitUntil { !model.isUpdating && !model.isScanning }

        let brokenOutcome = model.operationResultsByID[brokenPath]?.outcome
        XCTAssertTrue({ if case .upToDate = brokenOutcome { return true }; return false }(), "回退快照后重试应真正执行拉取")
    }

    /// 跳过的仓库（如未跟踪/未提交改动）可强制更新：仍走 ff-only，
    /// 只放开「工作区必须干净」的预检；汇总条数据随之刷新。
    func testForceUpdateSkippedRepositoriesPullsDespiteDirtyWorktree() async throws {
        let fixture = makeFixtureHome(repositories: ["work/clean", "work/dirty"])
        let dirtyPath = "\(fixture.home.path)/work/dirty"
        await fixture.git.setDirtyStatusPaths([dirtyPath])
        let model = makeModel(home: fixture.home, git: fixture.git)
        model.scan()
        await waitUntil { !model.isScanning }

        model.update()
        await waitUntil { !model.isUpdating && !model.isScanning }
        XCTAssertEqual(model.lastRunSummary?.skippedCount, 1)
        XCTAssertEqual(model.lastRunSummary?.upToDateCount, 1)
        let dirtyOutcome = model.operationResultsByID[dirtyPath]?.outcome
        XCTAssertTrue({ if case .skipped = dirtyOutcome { return true }; return false }())

        // 用户显式强制：脏仓库也应执行 pull 并成功。
        model.forceUpdateSkipped()
        await waitUntil { !model.isUpdating && !model.isScanning }

        let forcedOutcome = model.operationResultsByID[dirtyPath]?.outcome
        XCTAssertTrue({ if case .upToDate = forcedOutcome { return true }; return false }(), "强制更新应真正执行拉取")
        XCTAssertEqual(model.lastRunSummary?.skippedCount, 0, "强制批次不应再有跳过")
        // 未参与强制批次的仓库结果保留。
        let cleanOutcome = model.operationResultsByID.values.first { !$0.repository.path.hasSuffix("dirty") }?.outcome
        XCTAssertTrue({ if case .upToDate = cleanOutcome { return true }; return false }())
    }

    func testScanDirectoryPersistsAcrossModelRecreation() async throws {
        let defaults = makeIsolatedDefaults()
        let preferences = ToolPreferenceStore(defaults: defaults)
        let fixture = makeFixtureHome(repositories: ["work/alpha"])
        let first = makeModel(home: fixture.home, git: fixture.git, preferences: preferences)

        first.setPath("/Users/demo/work")

        let recreated = SourceControlWorkspaceModel(
            preferences: preferences,
            scanner: SourceControlScanner(git: fixture.git),
            updater: SourceControlUpdateExecutor(git: fixture.git)
        )
        XCTAssertEqual(recreated.path, "/Users/demo/work")
        XCTAssertTrue(recreated.canScan)
    }

    func testScanRequiresDirectoryPath() async throws {
        let fixture = makeFixtureHome(repositories: ["work/alpha"])
        let model = makeModel(home: fixture.home, git: fixture.git)
        model.setPath("   ")

        XCTAssertFalse(model.canScan)

        model.setPath(fixture.home.path)
        XCTAssertTrue(model.canScan)
    }

    func testManualRescanClearsStaleOperationResults() async throws {
        let fixture = makeFixtureHome(repositories: ["work/alpha", "work/beta"])
        let model = makeModel(home: fixture.home, git: fixture.git)
        model.scan()
        await waitUntil { !model.isScanning }
        model.update()
        await waitUntil { !model.isUpdating && !model.isScanning }
        XCTAssertFalse(model.operationResultsByID.isEmpty, "更新运行后应有行内结果")

        model.scan()
        await waitUntil { !model.isScanning }

        XCTAssertTrue(model.operationResultsByID.isEmpty, "手动重扫应清空上次运行的结果徽章")
        XCTAssertTrue(model.failureSummary.isEmpty)
    }

    func testResolveScanProgressNeverRegressesFromReadPhaseToWalkPhase() {
        let walk = SourceControlScanProgress(discoveredCount: 12, readCompletedCount: 0, readTotalCount: nil)
        let read = SourceControlScanProgress(discoveredCount: 12, readCompletedCount: 3, readTotalCount: 12)
        let lateWalk = SourceControlScanProgress(discoveredCount: 12, readCompletedCount: 0, readTotalCount: nil)

        XCTAssertEqual(SourceControlWorkspaceModel.resolveScanProgress(current: nil, incoming: walk), walk)
        XCTAssertEqual(SourceControlWorkspaceModel.resolveScanProgress(current: walk, incoming: read), read)
        // 读数期开始后，迟到的遍历期事件不得把文案回退成「已发现 N 个仓库」。
        XCTAssertNil(SourceControlWorkspaceModel.resolveScanProgress(current: read, incoming: lateWalk))
        // 遍历期内部只接受单调递增的发现计数。
        XCTAssertNil(SourceControlWorkspaceModel.resolveScanProgress(current: walk, incoming: .init(discoveredCount: 8, readCompletedCount: 0, readTotalCount: nil)))
        XCTAssertEqual(
            SourceControlWorkspaceModel.resolveScanProgress(current: walk, incoming: .init(discoveredCount: 15, readCompletedCount: 0, readTotalCount: nil))?.discoveredCount,
            15
        )
    }

    func testScanOfEmptyDirectoryDistinguishesFoundNothingFromNotScanned() async throws {
        let fixture = makeFixtureHome(repositories: [])
        let model = makeModel(home: fixture.home, git: fixture.git)
        XCTAssertFalse(model.lastScanFoundNothing, "未扫描时不应显示空目录空态")

        model.scan()
        await waitUntil { !model.isScanning }

        XCTAssertTrue(model.repositories.isEmpty)
        XCTAssertTrue(model.lastScanFoundNothing, "合法目录扫描无结果应标记为空目录")

        model.setPath(fixture.home.path)
        XCTAssertFalse(model.lastScanFoundNothing, "改路径应复位空目录标记")

        let populated = makeFixtureHome(repositories: ["work/alpha"])
        let found = makeModel(home: populated.home, git: populated.git)
        found.scan()
        await waitUntil { !found.isScanning }
        XCTAssertFalse(found.lastScanFoundNothing)
        XCTAssertEqual(found.repositories.count, 1)
    }

    func testExpandedDirectoryPathExpandsLeadingTildeOnly() {
        XCTAssertEqual(SourceControlWorkspaceModel.expandedDirectoryPath("/absolute/path"), "/absolute/path")
        XCTAssertEqual(SourceControlWorkspaceModel.expandedDirectoryPath("/Users/sun/work"), "/Users/sun/work")
        XCTAssertTrue(SourceControlWorkspaceModel.expandedDirectoryPath("~/work").hasPrefix("/Users/"), "前导 ~ 应展开为用户主目录")
        XCTAssertNotEqual(SourceControlWorkspaceModel.expandedDirectoryPath("~/work"), "~/work")
    }

    func testUpdateVisibleScopeOnlyPullsVisibleRepositories() async throws {
        let fixture = makeFixtureHome(repositories: ["work/alpha", "work/beta", "work/gamma"])
        let model = makeModel(home: fixture.home, git: fixture.git)
        model.scan()
        await waitUntil { !model.isScanning }
        XCTAssertEqual(model.selectedPaths.count, 3, "默认全选")

        // 模拟筛选后只更新可见的两行。
        let visible = Array(model.repositories.prefix(2))
        model.update(visible: visible)
        await waitUntil { !model.isUpdating && !model.isScanning }

        XCTAssertEqual(model.operationResultsByID.count, 2, "只应更新可见的仓库")
        XCTAssertNil(model.operationResultsByID[model.repositories[2].path], "不可见仓库不应被更新")
    }

    func testRemoteHostParsesHTTPSAndSCPLikeRemotes() {
        XCTAssertEqual(SourceControlWorkspaceModel.remoteHost(from: "https://github.com/acme/repo.git"), "GitHub")
        XCTAssertEqual(SourceControlWorkspaceModel.remoteHost(from: "https://gitlab.com/acme/repo.git"), "GitLab")
        XCTAssertEqual(SourceControlWorkspaceModel.remoteHost(from: "git@gitlab.example.com:acme/repo.git"), "gitlab.example.com")
        XCTAssertEqual(SourceControlWorkspaceModel.remoteHost(from: "ssh://git@github.com/acme/repo.git"), "GitHub")
        XCTAssertNil(SourceControlWorkspaceModel.remoteHost(from: nil))
        XCTAssertNil(SourceControlWorkspaceModel.remoteHost(from: "/local/path"))
    }

    func testDisplayOrderPrioritizesAttentionStatesOverUpToDate() {
        func repository(_ name: String, behind: Int = 0, modified: Bool = false) -> SourceControlRepository {
            SourceControlRepository(
                path: "/tmp/repos/\(name)",
                branch: "main",
                shortRevision: "abc1234",
                remote: "https://git.example.com/group/\(name).git",
                status: modified ? .modified : .clean,
                behind: behind,
                hasUpstream: true,
                upstream: "origin/main",
                revision: "abc1234",
                remoteState: behind > 0 ? .updateAvailable : .upToDate
            )
        }
        let failed = repository("failed", behind: 2)
        let outdated = repository("outdated", behind: 3)
        let attention = repository("attention", modified: true)
        let updated = repository("updated")
        let latest = repository("latest")
        let zetaLatest = repository("zeta-latest")
        let results = [
            SourceControlOperationResult(
                repository: failed,
                outcome: .failed(SourceControlDiagnostic(code: "pull-failed", summary: "拉取失败", recovery: "稍后重试"))
            ),
            SourceControlOperationResult(repository: updated, outcome: .updated)
        ]

        let ordered = SourceControlWorkspaceModel.displayOrder(
            of: [latest, updated, attention, zetaLatest, failed, outdated],
            results: results
        )

        XCTAssertEqual(ordered, [failed, outdated, attention, updated, latest, zetaLatest])
    }

    // MARK: - Helpers

    private struct Fixture {
        let home: URL
        let git: WorkspaceMockGitClient
    }

    private func makeModel(home: URL, git: WorkspaceMockGitClient, preferences: ToolPreferenceStore? = nil) -> SourceControlWorkspaceModel {
        let model = SourceControlWorkspaceModel(
            preferences: preferences ?? ToolPreferenceStore(defaults: makeIsolatedDefaults()),
            scanner: SourceControlScanner(git: git),
            updater: SourceControlUpdateExecutor(git: git)
        )
        model.setPath(home.path)
        return model
    }

    private func makeFixtureHome(repositories: [String]) -> Fixture {
        let path = "/tmp/xtools-source-control-model-tests-\(UUID().uuidString)"
        let home = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        for repository in repositories {
            try? FileManager.default.createDirectory(atPath: "\(path)/\(repository)/.git", withIntermediateDirectories: true)
        }
        return Fixture(home: home, git: WorkspaceMockGitClient())
    }

    private func makeIsolatedDefaults() -> UserDefaults {
        let name = "xtools-source-control-model-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func waitUntil(
        _ condition: @MainActor () -> Bool,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let start = Date()
        while !condition() {
            if Date().timeIntervalSince(start) > timeout {
                XCTFail("等待模型状态超时", file: file, line: line)
                return
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}

/// 扫描 + 更新共用的 Git 桩：单次 porcelain v2 返回干净的快进候选数据，
/// `.repositoryRoot` 必须回显请求路径（执行器的快照校验依赖它），
/// pull 是否失败由可变集合控制。
private actor WorkspaceMockGitClient: GitProcessClient {
    private var failingPullPaths: Set<String> = []
    private var dirtyStatusPaths: Set<String> = []

    func setFailingPullPaths(_ paths: Set<String>) {
        failingPullPaths = paths
    }

    func setDirtyStatusPaths(_ paths: Set<String>) {
        dirtyStatusPaths = paths
    }

    func run(_ request: GitCommandRequest, timeout: Duration) async throws -> GitProcessOutput {
        switch request.kind {
        case .repositoryRoot:
            return GitProcessOutput(exitCode: 0, standardOutput: request.repositoryPath + "\n")
        case .statusV2:
            var output = "# branch.oid abc123\n# branch.head main\n# branch.upstream origin/main\n# branch.ab +0 -0\n"
            if dirtyStatusPaths.contains(request.repositoryPath) {
                output += "1 .M N... 100644 100644 100644 h1 h2 file.swift\n"
            }
            return GitProcessOutput(exitCode: 0, standardOutput: output)
        case .remote:
            return GitProcessOutput(exitCode: 0, standardOutput: "origin\thttps://gitlab.example/acme/repo.git (fetch)\n")
        case .pullFastForward:
            if failingPullPaths.contains(request.repositoryPath) {
                return GitProcessOutput(
                    exitCode: 1,
                    standardError: "error: Your local changes to the following files would be overwritten by merge"
                )
            }
            return GitProcessOutput(exitCode: 0, standardOutput: "Already up to date.\n")
        default:
            return GitProcessOutput(exitCode: 1)
        }
    }
}
