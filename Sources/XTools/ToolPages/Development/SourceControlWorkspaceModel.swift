import SwiftUI
import AppKit
import XToolsCore

@MainActor
final class SourceControlWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<SourceControlWorkspaceModel>(toolID: "source-control") { preferences in
        SourceControlWorkspaceModel(preferences: preferences)
    }

    /// Typed completion counts for the batch-update toast. The UUID keeps two
    /// identical runs distinct so `onChange` observers fire for each one.
    struct UpdateCompletionSummary: Equatable {
        let id = UUID()
        let updatedCount: Int
        let upToDateCount: Int
        let skippedCount: Int
        let failedCount: Int
    }

    struct UpdateFailureSummary: Identifiable, Equatable {
        let repository: SourceControlRepository
        let diagnostic: SourceControlDiagnostic

        var id: String { repository.id }
    }

    @Published var path = ""
    @Published private(set) var repositories: [SourceControlRepository] = []
    @Published private(set) var selectedPaths: Set<String> = []
    @Published private(set) var isScanning = false
    /// 扫描实时进度：目录遍历期只有发现计数；读取期有 N/M。
    @Published private(set) var scanProgress: SourceControlScanProgress?
    @Published private(set) var isUpdating = false
    @Published private(set) var diagnostic: SourceControlDiagnostic?
    /// 行内操作结果按仓库 id（= path）字典存储：模型侧一次写入，行渲染
    /// 读取 O(1)——此前每行 5 处 `last(where:)` 线性扫 + 每轮渲染重建
    /// outcomesByID 字典是 O(n²) churn。写入方保持「同仓库后写覆盖」语义，
    /// 与旧数组的 removeAll+append 一致。
    @Published private(set) var operationResultsByID: [String: SourceControlOperationResult] = [:]
    /// operationResultsByID 的变更代数：sortedForDisplay 的 memoize 以此
    /// 识别结果集身份，避免无变化时每轮 body 重建排序。
    private var operationResultsGeneration = 0
    @Published private(set) var failureSummary: [UpdateFailureSummary] = []
    @Published private(set) var lastCompletion: UpdateCompletionSummary?
    /// 持久保留的最近一次批量结果计数（汇总条数据源）；新扫描/改路径清除。
    @Published private(set) var lastRunSummary: UpdateCompletionSummary?
    /// 最近一次扫描在合法目录下一无所获：用于区分「未扫描」与「空目录」空态。
    @Published private(set) var lastScanFoundNothing = false
    /// Repository currently being pulled (serial run) for the row spinner.
    @Published private(set) var activeUpdatePath: String?
    @Published private(set) var updateRunCompleted = 0
    @Published private(set) var updateRunTotal = 0
    private let preferences: ToolPreferenceStore
    private let scanner: SourceControlScanner
    private let updater: SourceControlUpdateExecutor
    private var hasScannedInSession = false
    private var task: Task<Void, Never>?
    private var generation = 0

    init(
        preferences: ToolPreferenceStore = ToolPreferenceStore(),
        scanner: SourceControlScanner = SourceControlScanner(),
        updater: SourceControlUpdateExecutor = SourceControlUpdateExecutor()
    ) {
        self.preferences = preferences
        self.scanner = scanner
        self.updater = updater
        path = preferences.value(for: SourceControlToolPreferenceKeys.scanDirectory)
    }

    var selectedRepositories: [SourceControlRepository] {
        repositories.filter { selectedPaths.contains($0.path) }
    }

    /// 扫描用目录：展开前导 `~`（占位符示例即 ~/work，输入必须可直接使用）。
    static func expandedDirectoryPath(_ raw: String) -> String {
        (raw as NSString).expandingTildeInPath
    }

    /// 行内远端平台徽章：GitHub / GitLab / 自建 host（HTTPS 与 scp-like 均解析）。
    static func remoteHost(from remote: String?) -> String? {
        guard let remote, !remote.isEmpty else { return nil }
        var host: String?
        if let url = URL(string: remote), let parsed = url.host {
            host = parsed
        } else if let at = remote.firstIndex(of: "@"), let colon = remote[at...].firstIndex(of: ":") {
            let parsed = String(remote[remote.index(after: at)..<colon])
            host = parsed.isEmpty ? nil : parsed
        }
        guard let host, !host.isEmpty else { return nil }
        switch host.lowercased() {
        case "github.com": return "GitHub"
        case "gitlab.com": return "GitLab"
        default: return host
        }
    }

    var canScan: Bool {
        !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isScanning && !isUpdating
    }
    var canUpdate: Bool {
        !selectedRepositories.isEmpty
            && !isScanning && !isUpdating
    }

    func appendOperationResult(_ result: SourceControlOperationResult, generation expectedGeneration: Int? = nil) {
        if let expectedGeneration, expectedGeneration != generation { return }
        operationResultsByID[result.repository.id] = result
        operationResultsGeneration &+= 1
    }

    /// 结果集整体替换（清空/重置）：所有清空路径统一走这里以推进 memoize 代数。
    private func replaceOperationResults(_ newValue: [String: SourceControlOperationResult]) {
        if newValue.isEmpty, operationResultsByID.isEmpty { return }
        operationResultsByID = newValue
        operationResultsGeneration &+= 1
    }

    func setPath(_ value: String) {
        task?.cancel()
        generation &+= 1
        isScanning = false
        isUpdating = false
        path = value
        preferences.set(value, for: SourceControlToolPreferenceKeys.scanDirectory)
        resetScanDerivedState()
    }

    private func resetScanDerivedState() {
        repositories = []
        selectedPaths = []
        scanProgress = nil
        diagnostic = nil
        replaceOperationResults([:])
        failureSummary = []
        lastRunSummary = nil
        lastScanFoundNothing = false
        activeUpdatePath = nil
        updateRunCompleted = 0
        updateRunTotal = 0
        updateOrder = []
    }

    // MARK: - Scan

    /// 打开同步页时自动扫描一次（会话内仅首次；目录模式需已有路径）。
    func scanOnAppearIfNeeded() {
        guard !hasScannedInSession, canScan else { return }
        hasScannedInSession = true
        scan()
    }

    func scan() {
        guard canScan else { return }
        task?.cancel()
        generation &+= 1
        let operationGeneration = generation
        let scope = SourceControlScanScope.directory(path: Self.expandedDirectoryPath(path.trimmingCharacters(in: .whitespacesAndNewlines)))
        isScanning = true
        scanProgress = nil
        diagnostic = nil
        repositories = []
        selectedPaths = []
        failureSummary = []
        lastRunSummary = nil
        lastScanFoundNothing = false
        // 手动重扫意味着重新观察现场：上次运行的行内结果徽章一并作废，
        // 避免展示与新鲜扫描数据矛盾的「已更新/已跳过」。
        replaceOperationResults([:])
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await scanner.scan(
                    scope: scope,
                    onRepository: { [weak self] repository in
                        // 流式上屏：扫描期行陆续出现并保持默认全选。
                        await self?.appendScannedRepository(repository, generation: operationGeneration)
                    },
                    onProgress: { [weak self] progress in
                        await self?.recordScanProgress(progress, generation: operationGeneration)
                    }
                )
                guard !Task.isCancelled, generation == operationGeneration else { return }
                repositories = snapshot.repositories
                lastScanFoundNothing = snapshot.repositories.isEmpty
                // 默认全选：成熟工具（SourceTree / JetBrains Update Project /
                // gita）在发现后都作用于全部结果；不可安全快进的仓库在
                // 更新时按安全规则跳过并在行内说明原因。
                selectedPaths = Set(snapshot.repositories.map(\.path))
            } catch let error as SourceControlError {
                guard generation == operationGeneration else { return }
                diagnostic = error.diagnostic
            } catch is CancellationError {
                return
            } catch {
                guard generation == operationGeneration else { return }
                diagnostic = SourceControlError.commandFailed.diagnostic
            }
            if generation == operationGeneration {
                isScanning = false
                scanProgress = nil
            }
        }
    }

    private func appendScannedRepository(_ repository: SourceControlRepository, generation expectedGeneration: Int) {
        guard expectedGeneration == generation else { return }
        guard !repositories.contains(where: { $0.id == repository.id }) else { return }
        repositories.append(repository)
        selectedPaths.insert(repository.path)
    }

    private func recordScanProgress(_ progress: SourceControlScanProgress, generation expectedGeneration: Int) {
        guard expectedGeneration == generation else { return }
        if let resolved = Self.resolveScanProgress(current: scanProgress, incoming: progress) {
            scanProgress = resolved
        }
    }

    /// 目录遍历期的发现计数经无序 Task 投递：只接受单调递增，且读数期
    /// 一旦开始就不再被迟到的遍历期事件回退。返回 nil 表示保留现状。
    static func resolveScanProgress(
        current: SourceControlScanProgress?,
        incoming: SourceControlScanProgress
    ) -> SourceControlScanProgress? {
        guard let current else { return incoming }
        if incoming.readTotalCount == nil {
            if current.readTotalCount != nil { return nil }
            if incoming.discoveredCount < current.discoveredCount { return nil }
        }
        return incoming
    }

    // MARK: - Selection

    func toggleSelection(_ repository: SourceControlRepository) {
        if selectedPaths.contains(repository.path) { selectedPaths.remove(repository.path) }
        else { selectedPaths.insert(repository.path) }
    }

    func selectAll() {
        selectedPaths = Set(repositories.map(\.path))
    }

    func clearSelection() {
        selectedPaths = []
    }

    /// 三态全选开关作用域：当前可见（搜索/筛选后）的行。
    func setVisibleSelection(_ paths: Set<String>, selected: Bool) {
        if selected { selectedPaths.formUnion(paths) }
        else { selectedPaths.subtract(paths) }
    }

    // MARK: - Update

    func update() {
        guard canUpdate else { return }
        startUpdate(selectedRepositories, resetResults: true)
    }

    /// 更新作用域跟随当前可见（搜索/筛选后）的行——与三态全选框同一语义：
    /// 筛选出「需处理」后点更新，只更新可见的这些仓库。
    func update(visible: [SourceControlRepository]) {
        guard canUpdate else { return }
        let targets = visible.filter { selectedPaths.contains($0.path) }
        guard !targets.isEmpty else { return }
        startUpdate(targets, resetResults: true)
    }

    func retry(_ repository: SourceControlRepository) {
        guard !isScanning, !isUpdating else { return }
        startUpdate([repository], resetResults: false)
    }

    /// 跳过行的强制更新：放开「工作区必须干净」的预检，让 `git pull
    /// --ff-only` 自行决定（改动会被覆盖或无法快进时 git 仍会拒绝）。
    func forceUpdate(_ repository: SourceControlRepository) {
        guard !isScanning, !isUpdating else { return }
        startUpdate([repository], resetResults: false, force: true)
    }

    /// 汇总条「强制更新跳过项」：批量重跑上次被跳过的仓库。
    func forceUpdateSkipped() {
        guard !isScanning, !isUpdating else { return }
        let targets = repositories.filter { repository in
            guard let outcome = operationResultsByID[repository.id]?.outcome else { return false }
            if case .skipped = outcome { return true }
            return false
        }
        startUpdate(targets, resetResults: false, force: true)
    }

    /// 失败汇总 sheet 的「重试失败项」：只重跑失败的仓库，保留其余结果。
    /// 重试目标优先取刷新扫描里仍是快进候选的数据；刷新快照在仓库已
    /// 恢复干净时是陈旧的（会把它标成不可快进），此时回退到失败时的
    /// 快照——执行器拉取前会重新对磁盘做安全校验，不会绕过保护。
    func retryFailures() {
        guard !failureSummary.isEmpty,
              !isScanning, !isUpdating else { return }
        let targets = failureSummary.map { summary -> SourceControlRepository in
            if let fresh = repositories.first(where: { $0.path == summary.repository.path }),
               fresh.isFastForwardCandidate {
                return fresh
            }
            return summary.repository
        }
        failureSummary = []
        startUpdate(targets, resetResults: false)
    }

    private func startUpdate(_ targets: [SourceControlRepository], resetResults: Bool, force: Bool = false) {
        guard !targets.isEmpty else { return }
        task?.cancel()
        generation &+= 1
        let operationGeneration = generation
        isUpdating = true
        diagnostic = nil
        if resetResults {
            replaceOperationResults([:])
            failureSummary = []
        } else {
            var results = operationResultsByID
            var mutated = false
            for target in targets where results[target.id] != nil {
                results.removeValue(forKey: target.id)
                mutated = true
            }
            if mutated {
                replaceOperationResults(results)
            }
        }
        updateRunCompleted = 0
        updateRunTotal = targets.count
        updateOrder = targets.map(\.path)
        activeUpdatePath = targets.first?.path
        task = Task { [weak self] in
            guard let self else { return }
            _ = await updater.update(repositories: targets, force: force) { [weak self] result in
                await self?.recordUpdateResult(result, generation: operationGeneration, total: targets.count)
            }
            guard !Task.isCancelled, generation == operationGeneration else { return }
            isUpdating = false
            activeUpdatePath = nil
            publishCompletion(for: targets)
            // 刷新各仓库的落后/最新状态；保留失败汇总与既有结果行，让
            // 用户能直接从汇总或行内重试。
            refreshAfterUpdate()
        }
    }

    private func recordUpdateResult(_ result: SourceControlOperationResult, generation expectedGeneration: Int, total: Int) {
        guard expectedGeneration == generation else { return }
        appendOperationResult(result)
        updateRunCompleted = min(updateRunCompleted + 1, total)
        // Serial run: the just-finished repository's slot points at the next
        // target captured at start time.
        activeUpdatePath = nextUpdateTargetPath(after: result.repository.path)
    }

    private var updateOrder: [String] = []

    private func nextUpdateTargetPath(after path: String) -> String? {
        guard let index = updateOrder.firstIndex(of: path) else { return nil }
        let next = index + 1
        return next < updateOrder.count ? updateOrder[next] : nil
    }

    /// 列表展示排序：需要用户关注的状态靠前，已最新垫底。
    /// 失败 > 待更新 > 需处理（含被跳过）> 已更新 > 已最新，同级按路径自然序。
    /// 输入（可见行集合 + 结果集代数）未变时直接复用上次排序输出：排序的
    /// localizedStandardCompare 是行渲染热路径里最贵的一步。
    func sortedForDisplay(_ repositories: [SourceControlRepository]) -> [SourceControlRepository] {
        if displayOrderCacheHasInput,
           displayOrderCacheInput == repositories,
           displayOrderCacheResultsGeneration == operationResultsGeneration {
            return displayOrderCacheOutput
        }
        let sorted = Self.displayOrder(
            of: repositories,
            outcomesByID: operationResultsByID.mapValues(\.outcome)
        )
        displayOrderCacheHasInput = true
        displayOrderCacheInput = repositories
        displayOrderCacheResultsGeneration = operationResultsGeneration
        displayOrderCacheOutput = sorted
        return sorted
    }

    private var displayOrderCacheHasInput = false
    private var displayOrderCacheInput: [SourceControlRepository] = []
    private var displayOrderCacheResultsGeneration = -1
    private var displayOrderCacheOutput: [SourceControlRepository] = []

    static func displayOrder(
        of repositories: [SourceControlRepository],
        outcomesByID: [String: SourceControlOperationOutcome]
    ) -> [SourceControlRepository] {
        func attentionRank(_ repository: SourceControlRepository) -> Int {
            if case .failed = outcomesByID[repository.id] { return 0 }
            if repository.isFastForwardCandidate, repository.behind > 0 { return 1 }
            if !repository.isFastForwardCandidate { return 2 }
            if case .updated = outcomesByID[repository.id] { return 3 }
            return 4
        }
        return repositories.sorted {
            let lhs = attentionRank($0), rhs = attentionRank($1)
            return lhs == rhs
                ? $0.path.localizedStandardCompare($1.path) == .orderedAscending
                : lhs < rhs
        }
    }

    /// 从本次运行的目标推导类型化完成计数与失败汇总。
    private func publishCompletion(for targets: [SourceControlRepository]) {
        var updated = 0, upToDate = 0, skipped = 0, failed = 0
        var failures: [UpdateFailureSummary] = []
        for target in targets {
            switch operationResultsByID[target.id]?.outcome {
            case .updated: updated += 1
            case .upToDate: upToDate += 1
            case .skipped: skipped += 1
            case .cancelled: break
            case .failed(let diagnostic):
                failed += 1
                failures.append(UpdateFailureSummary(
                    repository: repositories.first { $0.path == target.path } ?? target,
                    diagnostic: diagnostic
                ))
            case nil: break
            }
        }
        failureSummary = failures
        let summary = UpdateCompletionSummary(
            updatedCount: updated,
            upToDateCount: upToDate,
            skippedCount: skipped,
            failedCount: failed
        )
        lastCompletion = summary
        lastRunSummary = summary
    }

    /// 更新完成后的状态重扫：不清失败汇总与结果行，选择恢复为全选。
    private func refreshAfterUpdate() {
        let operationGeneration = generation
        let scope = SourceControlScanScope.directory(path: Self.expandedDirectoryPath(path.trimmingCharacters(in: .whitespacesAndNewlines)))
        isScanning = true
        scanProgress = nil
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await scanner.scan(
                    scope: scope,
                    onRepository: { [weak self] repository in
                        await self?.appendScannedRepository(repository, generation: operationGeneration)
                    },
                    onProgress: { [weak self] progress in
                        await self?.recordScanProgress(progress, generation: operationGeneration)
                    }
                )
                guard !Task.isCancelled, generation == operationGeneration else { return }
                repositories = snapshot.repositories
                selectedPaths = Set(snapshot.repositories.map(\.path))
            } catch {
                // 刷新失败不打断刚完成的更新结果；保留现有列表。
            }
            if generation == operationGeneration {
                isScanning = false
                scanProgress = nil
            }
        }
    }

    func acknowledgeCompletionToast() {
        lastCompletion = nil
    }

    func cancel() {
        task?.cancel()
        generation &+= 1
        isScanning = false
        scanProgress = nil
        isUpdating = false
        activeUpdatePath = nil
    }

}
