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

        let outcomes = model.operationResults.map(\.outcome)
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
        let brokenOutcomeBefore = model.operationResults.first { $0.repository.path == brokenPath }?.outcome
        XCTAssertTrue({ if case .failed = brokenOutcomeBefore { return true }; return false }())

        model.retryFailures()
        await waitUntil { !model.isUpdating && !model.isScanning }

        XCTAssertTrue(model.failureSummary.isEmpty)
        let brokenOutcome = model.operationResults.first { $0.repository.path == brokenPath }?.outcome
        XCTAssertTrue({ if case .upToDate = brokenOutcome { return true }; return false }(), "重试后失败仓库应变为已最新")
        // 未失败的仓库结果在重试批次中被保留。
        let alphaOutcome = model.operationResults.first { !$0.repository.path.hasSuffix("broken") }?.outcome
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

        let brokenOutcome = model.operationResults.first { $0.repository.path == brokenPath }?.outcome
        XCTAssertTrue({ if case .upToDate = brokenOutcome { return true }; return false }(), "回退快照后重试应真正执行拉取")
    }

    func testScanModeAndDirectoryPersistAcrossModelRecreation() async throws {
        let defaults = makeIsolatedDefaults()
        let preferences = ToolPreferenceStore(defaults: defaults)
        let fixture = makeFixtureHome(repositories: ["work/alpha"])
        let first = makeModel(home: fixture.home, git: fixture.git, preferences: preferences)

        XCTAssertEqual(first.mode, .machine)
        first.setMode(.directory)
        first.setPath("/Users/demo/work")

        let recreated = SourceControlWorkspaceModel(
            preferences: preferences,
            scanner: SourceControlScanner(git: fixture.git, homeDirectoryPath: { fixture.home.path }),
            updater: SourceControlUpdateExecutor(git: fixture.git)
        )
        XCTAssertEqual(recreated.mode, .directory)
        XCTAssertEqual(recreated.path, "/Users/demo/work")
    }

    func testDirectoryModeWithoutPathCannotScanButMachineAlwaysCan() async throws {
        let fixture = makeFixtureHome(repositories: ["work/alpha"])
        let model = makeModel(home: fixture.home, git: fixture.git)
        model.setMode(.directory)
        model.setPath("   ")

        XCTAssertFalse(model.canScan)

        model.setMode(.machine)
        XCTAssertTrue(model.canScan)
    }

    // MARK: - Helpers

    private struct Fixture {
        let home: URL
        let git: WorkspaceMockGitClient
    }

    private func makeModel(home: URL, git: WorkspaceMockGitClient, preferences: ToolPreferenceStore? = nil) -> SourceControlWorkspaceModel {
        SourceControlWorkspaceModel(
            preferences: preferences ?? ToolPreferenceStore(defaults: makeIsolatedDefaults()),
            scanner: SourceControlScanner(git: git, homeDirectoryPath: { home.path }),
            updater: SourceControlUpdateExecutor(git: git)
        )
    }

    private func makeFixtureHome(repositories: [String]) -> Fixture {
        let path = "/tmp/xtools-source-control-model-tests-\(UUID().uuidString)"
        let home = URL(fileURLWithPath: path)
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

/// 扫描 + 更新共用的 Git 桩：扫描命令返回干净的快进候选数据，
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
        case .branch:
            return GitProcessOutput(exitCode: 0, standardOutput: "main\n")
        case .revision:
            return GitProcessOutput(exitCode: 0, standardOutput: "abc123\n")
        case .remote:
            return GitProcessOutput(exitCode: 0, standardOutput: "origin\thttps://gitlab.example/acme/repo.git (fetch)\n")
        case .upstream:
            return GitProcessOutput(exitCode: 0, standardOutput: "origin/main\n")
        case .status:
            if dirtyStatusPaths.contains(request.repositoryPath) {
                return GitProcessOutput(exitCode: 0, standardOutput: " M file.swift\n")
            }
            return GitProcessOutput(exitCode: 0, standardOutput: "")
        case .divergence:
            return GitProcessOutput(exitCode: 0, standardOutput: "0\t0\n")
        case .remoteRevision:
            return GitProcessOutput(exitCode: 0, standardOutput: "abc123\trefs/heads/main\n")
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
