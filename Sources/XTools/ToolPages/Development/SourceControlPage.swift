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

struct IndexSourceControlPage: View {
    var body: some View {
        ToolWorkspaceHost(key: SourceControlWorkspaceModel.key) { workspace, _ in
            SourceControlWorkspaceContent(workspace: workspace)
        }
    }
}

private struct SourceControlWorkspaceContent: View {
    @Environment(\.fileInputPanelClient) private var fileInputPanelClient
    @Environment(\.toolToastCenter) private var toastCenter
    @ObservedObject var workspace: SourceControlWorkspaceModel
    @State private var repositoryQuery = ""
    @State private var repositoryFilter = "all"
    /// Shift 范围选择的锚点行。
    @State private var lastClickedPath: String?
    @State private var showsFailureSheet = false
    /// 目录输入的本地草稿：路径改用 commit-on-submit 语义（回车/失焦才
    /// setPath）。此前每个按键都会取消运行中的扫描、推进 generation、同步
    /// 写偏好存储并清空全部扫描派生态——逐字输入等于连续自毁现场。
    @State private var pathDraft = ""

    private var visibleRepositories: [SourceControlRepository] {
        let query = repositoryQuery.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        let filtered = workspace.repositories.filter { repository in
            let matchesQuery = query.isEmpty
                || repository.path.localizedLowercase.contains(query)
                || repository.branch.localizedLowercase.contains(query)
                || (repository.remote?.localizedLowercase.contains(query) ?? false)
            let matchesFilter: Bool
            switch repositoryFilter {
            case "update": matchesFilter = repository.isFastForwardCandidate && repository.behind > 0
            case "latest": matchesFilter = repository.isFastForwardCandidate && repository.behind == 0
            case "attention": matchesFilter = !repository.isFastForwardCandidate
            default: matchesFilter = true
            }
            return matchesQuery && matchesFilter
        }
        // 扫描流式到达期间保持稳定顺序，结束后按状态优先重排。
        return workspace.isScanning ? filtered : workspace.sortedForDisplay(filtered)
    }

    /// 可见性一次性求值：筛选 + 排序 + 三态勾选每轮渲染只算一遍，
    /// 供工具栏与列表共用（此前作为多个计算属性被重复求值 4 次）。
    private struct RepositoryVisibility {
        let items: [SourceControlRepository]
        /// false 全空 / true 全选 / nil 部分（三态）。
        let selectionState: Bool?
        let selectedVisibleCount: Int
    }

    private var repositoryVisibility: RepositoryVisibility {
        let items = visibleRepositories
        let visiblePaths = Set(items.map(\.path))
        let selectedCount = workspace.selectedPaths.intersection(visiblePaths).count
        let state: Bool? = visiblePaths.isEmpty
            ? false
            : (selectedCount == 0 ? false : (selectedCount == visiblePaths.count ? true : nil))
        return RepositoryVisibility(items: items, selectionState: state, selectedVisibleCount: selectedCount)
    }

    /// 细线进度读数：本次运行已处理 / 目标仓库数。
    private var updateFraction: Double? {
        guard workspace.isUpdating, workspace.updateRunTotal > 0 else { return nil }
        return Double(workspace.updateRunCompleted) / Double(workspace.updateRunTotal)
    }

    var body: some View {
        IndexPage("源码管理", subtitle: "同步本地 Git 仓库的最新代码。", workspaceSemantic: .queryListWorkspace) {
            syncSection
                .task { workspace.scanOnAppearIfNeeded() }
        }
        // Esc 取消正在运行的扫描/更新；⌘R 触发扫描。空闲时不拦截按键。
        .background {
            Button("") { workspace.cancel() }
                .keyboardShortcut(.cancelAction)
                .disabled(!(workspace.isScanning || workspace.isUpdating))
                .accessibilityHidden(true)
            // ⌘R 不经过字段失焦：扫描前先提交草稿，语义与回车一致。
            Button("") { scanFromCommittedPath() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!workspace.canScan)
                .accessibilityHidden(true)
        }
        .sheet(isPresented: $showsFailureSheet) {
            SourceControlFailureSummarySheet(failures: workspace.failureSummary) {
                showsFailureSheet = false
                workspace.retryFailures()
            } onDismiss: {
                showsFailureSheet = false
            }
        }
        .onChange(of: workspace.failureSummary) { failures in
            if !failures.isEmpty { showsFailureSheet = true }
        }
        .onChange(of: workspace.lastCompletion) { summary in
            defer { workspace.acknowledgeCompletionToast() }
            guard let summary, summary.failedCount == 0 else { return }
            if summary.updatedCount > 0 {
                toastCenter?.show("已更新 \(summary.updatedCount) 个仓库", tone: .success)
            } else {
                toastCenter?.show("所有仓库均已是最新", tone: .success)
            }
        }
    }

    // MARK: - Sync

    private var syncSection: some View {
        VStack(spacing: ToolMetrics.Spacing.md) {
            scopePanel
            repositoryPanel
        }
    }

    private var scopePanel: some View {
        IndexPanel("同步范围") {
            VStack(alignment: .leading, spacing: 8) {
                directoryField
                Text("扫描该目录（含子目录）下的所有 Git 仓库。目录会被记住，下次打开时自动恢复。")
                    .font(ToolTypography.caption)
                    .foregroundStyle(ToolTheme.textTertiary)
            }
        } accessory: { Text("只执行 git pull --ff-only").font(ToolTypography.caption).foregroundStyle(ToolTheme.textSecondary) }
    }

    /// 目录栏：路径输入 + 尾部内嵌的目录选择与扫描/取消图标按钮，
    /// 与 IndexSearchInput 的清空按钮同一形态，避免扫描动作独占一个按钮位。
    /// 输入过程只写本地草稿；回车（onSubmit）或失焦（onFocusChange false）
    /// 才提交 setPath——与仓库 IndexNumberInput 的提交语义一致。
    private var directoryField: some View {
        let isBusy = workspace.isScanning || workspace.isUpdating
        return IndexTextInput(
            placeholder: "工作区目录，例如 ~/work",
            text: $pathDraft,
            trailingInset: 80,
            onSubmit: { scanFromCommittedPath() },
            onFocusChange: { focused in
                if focused {
                    // 进入编辑以已提交路径为草稿基线（IndexNumberInput 同款）。
                    pathDraft = workspace.path
                } else {
                    commitPath()
                }
            }
        )
        .overlay(alignment: .trailing) {
            HStack(spacing: 2) {
                IndexIconButton(
                    systemImage: "folder",
                    help: "选择目录",
                    action: chooseDirectory
                )
                .frame(width: 32, height: 32)
                .disabled(isBusy)
                IndexIconButton(
                    systemImage: isBusy ? "xmark" : "arrow.clockwise",
                    help: isBusy ? "取消" : "扫描仓库",
                    action: { isBusy ? workspace.cancel() : scanFromCommittedPath() }
                )
                .frame(width: 32, height: 32)
                .toolMotionIconSwap(id: isBusy)
                .disabled(!isBusy && !workspace.canScan)
                .arrowCursorOnHover()
            }
            .padding(.trailing, 5)
            .arrowCursorOnHover()
        }
        .accessibilityElement(children: .contain)
        .onAppear { pathDraft = workspace.path }
        // 目录选择面板等外部路径变更始终回写草稿：点击按钮不必然先结束
        // 字段编辑，权威路径落地后草稿必须跟随，避免失焦时用旧草稿覆盖。
        .onChange(of: workspace.path) { newPath in pathDraft = newPath }
    }

    /// 把草稿提交到 workspace；空草稿不提交（避免误清已记住的目录），
    /// 与已提交路径等价时也不重复触发 setPath 的全状态重置。
    private func commitPath() {
        let trimmed = pathDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            pathDraft = workspace.path
            return
        }
        if trimmed == workspace.path.trimmingCharacters(in: .whitespacesAndNewlines) {
            pathDraft = workspace.path
            return
        }
        workspace.setPath(trimmed)
    }

    /// ⌘R / 扫描按钮共用：先落盘草稿再扫描，保证扫描用的一定是输入框里可见的路径。
    private func scanFromCommittedPath() {
        commitPath()
        workspace.scan()
    }

    private var repositoryPanel: some View {
        IndexPanel("仓库（\(workspace.repositories.count)）") {
            if workspace.repositories.isEmpty {
                if workspace.isScanning {
                    IndexProgressLabel(message: "正在扫描工作目录…", layout: .centered)
                } else if workspace.lastScanFoundNothing {
                    IndexEmptyState(
                        title: "该目录下没有 Git 仓库",
                        systemImage: "shippingbox",
                        message: "换个目录，或确认子目录中包含 Git 仓库后重新扫描"
                    )
                } else {
                    IndexEmptyState(
                        title: "尚未扫描仓库",
                        systemImage: "shippingbox",
                        message: "选择工作区目录后开始扫描，目录会被记住"
                    )
                }
            } else {
                let visibility = repositoryVisibility
                VStack(spacing: 6) {
                    repositoryToolbar(visibility)
                    if let summary = runSummary {
                        runSummaryBar(summary)
                    }
                    // 进度读数紧跟各自的细线进度条；列表占据剩余空间，
                    // 不再有任何元素排在 ScrollView 之后被推到面板底部。
                    if workspace.isScanning, let progress = workspace.scanProgress, let total = progress.readTotalCount {
                        VStack(spacing: 4) {
                            IndexProgressHairline(fraction: Double(progress.readCompletedCount) / Double(max(total, 1)))
                            Text("正在读取仓库状态 \(progress.readCompletedCount) / \(total)…")
                                .font(ToolTypography.caption)
                                .foregroundStyle(ToolTheme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else if workspace.isScanning {
                        VStack(spacing: 4) {
                            IndexProgressHairline(isIndeterminate: true)
                            Text("正在扫描目录…已发现 \(workspace.scanProgress?.discoveredCount ?? 0) 个仓库")
                                .font(ToolTypography.caption)
                                .foregroundStyle(ToolTheme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if workspace.isUpdating {
                        VStack(spacing: 4) {
                            IndexProgressHairline(fraction: updateFraction)
                            Text("已处理 \(workspace.updateRunCompleted) / \(workspace.updateRunTotal) 个仓库")
                                .font(ToolTypography.caption)
                                .foregroundStyle(ToolTheme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    ScrollViewReader { proxy in
                        ScrollView {
                            // 懒加载：几百仓的工作区只布局可见行。
                            LazyVStack(spacing: 6) {
                                ForEach(visibility.items) { repository in
                                    repositoryRow(repository)
                                        .id(repository.path)
                                }
                                if visibility.items.isEmpty {
                                    IndexEmptyState(title: "没有匹配的仓库", systemImage: "line.3.horizontal.decrease.circle", message: "试试清空搜索或切换筛选条件")
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .onChange(of: workspace.activeUpdatePath) { activePath in
                            // 串行更新时把正在拉取的行滚入视野。
                            guard let activePath else { return }
                            withAnimation { proxy.scrollTo(activePath, anchor: .top) }
                        }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .verticallyFilling()
        .indexWorkspaceDiagnostic(workspace.diagnostic?.summary)
    }

    /// 汇总条只在一次运行结束后展示；运行中由细线进度 + 计数行接管。
    private var runSummary: SourceControlWorkspaceModel.UpdateCompletionSummary? {
        guard !workspace.isUpdating, !workspace.isScanning, let summary = workspace.lastRunSummary else { return nil }
        guard summary.updatedCount + summary.upToDateCount + summary.skippedCount + summary.failedCount > 0 else { return nil }
        return summary
    }

    private func runSummaryBar(_ summary: SourceControlWorkspaceModel.UpdateCompletionSummary) -> some View {
        HStack(spacing: 8) {
            Text("上次更新")
                .font(ToolTypography.caption)
                .foregroundStyle(ToolTheme.textTertiary)
            if summary.updatedCount > 0 {
                IndexBadge("已更新 \(summary.updatedCount)", tone: .success)
            }
            if summary.upToDateCount > 0 {
                IndexBadge("已最新 \(summary.upToDateCount)", tone: .neutral)
            }
            if summary.skippedCount > 0 {
                IndexBadge("跳过 \(summary.skippedCount)", tone: .warning)
            }
            if summary.failedCount > 0 {
                IndexBadge("失败 \(summary.failedCount)", tone: .warning)
            }
            Spacer()
            if summary.skippedCount > 0 {
                Button("强制更新跳过项") { workspace.forceUpdateSkipped() }
                    .buttonStyle(IndexSmallButtonStyle())
                    .disabled(workspace.isUpdating || workspace.isScanning)
            }
            if summary.failedCount > 0 {
                Button("重试失败项（\(summary.failedCount)）") { workspace.retryFailures() }
                    .buttonStyle(IndexButtonStyle(primary: true))
                    .disabled(workspace.isUpdating || workspace.isScanning)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous)
                .fill(ToolTheme.utilityBackground)
        )
    }

    private func repositoryToolbar(_ visibility: RepositoryVisibility) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                SourceControlSelectAllCheckbox(
                    state: visibility.selectionState,
                    label: "已选 \(visibility.selectedVisibleCount)/\(visibility.items.count)"
                ) {
                    let visiblePaths = Set(visibility.items.map(\.path))
                    workspace.setVisibleSelection(visiblePaths, selected: visibility.selectionState != true)
                }
                .disabled(workspace.isUpdating)
                IndexSearchInput(placeholder: "搜索仓库或分支", text: $repositoryQuery, height: 30)
                    .frame(maxWidth: 220)
                Spacer()
                Button { workspace.update(visible: visibility.items) } label: {
                    IndexProgressMotionLabel(
                        title: workspace.isUpdating
                            ? "更新中 \(workspace.updateRunCompleted)/\(workspace.updateRunTotal)…"
                            : "更新所选（\(visibility.selectedVisibleCount)）",
                        systemImage: "arrow.down.circle",
                        isProcessing: workspace.isUpdating,
                        id: workspace.isUpdating
                    )
                }
                .buttonStyle(IndexButtonStyle(primary: true))
                .disabled(!workspace.canUpdate || visibility.selectedVisibleCount == 0)
            }
            // 筛选一键可达且带实时计数：待更新/需处理的规模一眼可见。
            IndexSegmentedControl(items: filterItems, selection: $repositoryFilter, density: .compact)
        }
    }

    private var filterItems: [(String, String)] {
        let repositories = workspace.repositories
        let pending = repositories.filter { $0.isFastForwardCandidate && $0.behind > 0 }.count
        let attention = repositories.filter { !$0.isFastForwardCandidate }.count
        let latest = repositories.count - pending - attention
        return [
            ("all", "全部 \(repositories.count)"),
            ("update", "待更新 \(pending)"),
            ("attention", "需处理 \(attention)"),
            ("latest", "已最新 \(latest)")
        ]
    }

    private func repositoryRow(_ repository: SourceControlRepository) -> some View {
        let isSelected = workspace.selectedPaths.contains(repository.path)
        let isActive = workspace.activeUpdatePath == repository.path
        // 行内重试回放当时的快照（拉取前执行器会重新校验磁盘状态）。
        let failedResult = workspace.operationResultsByID[repository.id]
        let hasFailure = failedResult?.outcome.isFailure == true
        return HStack(spacing: 8) {
            Button {
                handleRowClick(repository)
            } label: {
                HStack(spacing: 10) {
                    SourceControlRowCheckbox(isChecked: isSelected)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(URL(fileURLWithPath: repository.path).lastPathComponent)
                                .font(ToolTypography.bodyMedium)
                                .lineLimit(1)
                            if !repository.branch.isEmpty, repository.branch != "HEAD" {
                                Text(repository.branch)
                                    .font(ToolTypography.monoCaption)
                                    .foregroundStyle(ToolTheme.textSecondary)
                                    .lineLimit(1)
                            }
                            if let host = SourceControlWorkspaceModel.remoteHost(from: repository.remote) {
                                Text(host)
                                    .font(ToolTypography.micro)
                                    .foregroundStyle(ToolTheme.textTertiary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(ToolTheme.utilityBackground)
                                    )
                                    .overlay {
                                        Capsule(style: .continuous)
                                            .strokeBorder(ToolTheme.border, lineWidth: 1)
                                    }
                            }
                        }
                        Text(repository.path)
                            .font(ToolTypography.caption)
                            .foregroundStyle(ToolTheme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let detail = repositoryDetail(repository) {
                            Text(detail)
                                .font(ToolTypography.caption)
                                .foregroundStyle(hasFailure ? ToolTheme.warning : ToolTheme.textSecondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                    if isActive {
                        IndexProgressSpinner()
                    }
                    if repository.behind > 0 {
                        IndexBadge("落后 \(repository.behind)", systemImage: "arrow.down", tone: .accent)
                    }
                    IndexBadge(repositoryStatusTitle(repository), tone: repositoryStatusTone(repository))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous)
                        .fill(isSelected ? ToolTheme.selectionFill : Color.clear)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous)
                        .strokeBorder(isSelected ? ToolTheme.selectionStroke : Color.clear, lineWidth: 1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(IndexBareButtonStyle())
            .disabled(workspace.isUpdating)
            .hoverHighlight(enabled: !isSelected && !workspace.isUpdating)
            // 双击整行 = 在 Finder 中定位（单次单击仍会触发两次切换，净效果不变）。
            .simultaneousGesture(TapGesture(count: 2).onEnded { revealInFinder(repository) })
            .contextMenu { rowContextMenu(repository) }
            if let failedResult, failedResult.outcome.isFailure {
                Button("重试") { workspace.retry(failedResult.repository) }
                    .buttonStyle(IndexSmallButtonStyle())
                    .disabled(workspace.isUpdating || workspace.isScanning)
            } else if let skipped = skippedResult(of: repository) {
                Button("强制更新") { workspace.forceUpdate(skipped.repository) }
                    .buttonStyle(IndexSmallButtonStyle())
                    .disabled(workspace.isUpdating || workspace.isScanning)
            }
        }
    }

    /// 单击切换选中；Shift 单击以锚点行为界做范围选择（Finder/备忘录惯例）。
    private func handleRowClick(_ repository: SourceControlRepository) {
        defer { lastClickedPath = repository.path }
        let shiftPressed = NSEvent.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .contains(.shift)
        guard shiftPressed, let anchor = lastClickedPath,
              let anchorIndex = visibleRepositories.firstIndex(where: { $0.path == anchor }),
              let currentIndex = visibleRepositories.firstIndex(where: { $0.path == repository.path })
        else {
            workspace.toggleSelection(repository)
            return
        }
        let range = visibleRepositories[min(anchorIndex, currentIndex)...max(anchorIndex, currentIndex)].map(\.path)
        // 范围的目标状态跟随被点击行：未选中 → 选中整段，已选中 → 取消整段。
        let targetSelected = !workspace.selectedPaths.contains(repository.path)
        workspace.setVisibleSelection(Set(range), selected: targetSelected)
    }

    private func revealInFinder(_ repository: SourceControlRepository) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: repository.path)])
    }

    private func copyRepositoryPath(_ repository: SourceControlRepository) {
        IndexPasteboard.copyString(repository.path)
        toastCenter?.show("已拷贝仓库路径", tone: .info)
    }

    /// 远端地址转可浏览的网页地址（HTTPS/HTTP 原样、scp-like 与 ssh 转 https）。
    private func remoteWebURL(_ repository: SourceControlRepository) -> URL? {
        guard let remote = repository.remote, !remote.isEmpty else { return nil }
        if let components = URLComponents(string: remote),
           let scheme = components.scheme?.lowercased(),
           scheme == "https" || scheme == "http",
           components.host != nil {
            var web = components
            web.query = nil
            web.fragment = nil
            var path = web.path
            if path.hasSuffix(".git") { path.removeLast(4) }
            web.path = path
            return web.url
        }
        guard let at = remote.firstIndex(of: "@") else { return nil }
        let rest = String(remote[remote.index(after: at)...])
        var host: String?
        var path: String?
        if !remote.contains("://"), let colon = rest.firstIndex(of: ":") {
            host = String(rest[..<colon])
            path = String(rest[rest.index(after: colon)...])
        } else if let components = URLComponents(string: remote), components.scheme == "ssh", let parsedHost = components.host {
            host = parsedHost
            path = components.path
        }
        guard let host, var path else { return nil }
        path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.hasSuffix(".git") { path.removeLast(4) }
        guard !path.isEmpty else { return nil }
        return URL(string: "https://\(host)/\(path)")
    }

    @ViewBuilder
    private func rowContextMenu(_ repository: SourceControlRepository) -> some View {
        Button { revealInFinder(repository) } label: { Label("在 Finder 中显示", systemImage: "folder") }
        Button { copyRepositoryPath(repository) } label: { Label("拷贝仓库路径", systemImage: "doc.on.clipboard") }
        if remoteWebURL(repository) != nil {
            Button { openRemoteHomepage(repository) } label: { Label("打开远端主页", systemImage: "globe") }
        }
        Divider()
        Button { workspace.retry(repository) } label: { Label("更新此仓库", systemImage: "arrow.down.circle") }
            .disabled(workspace.isScanning || workspace.isUpdating)
        if !repository.isFastForwardCandidate {
            Button { workspace.forceUpdate(repository) } label: { Label("强制更新此仓库", systemImage: "exclamationmark.triangle") }
                .disabled(workspace.isScanning || workspace.isUpdating)
        }
    }

    private func openRemoteHomepage(_ repository: SourceControlRepository) {
        guard let url = remoteWebURL(repository) else { return }
        NSWorkspace.shared.open(url)
    }

    /// 行尾「强制更新」入口只挂在被跳过的行上（结果类型驱动，不解析文案）。
    private func skippedResult(of repository: SourceControlRepository) -> SourceControlOperationResult? {
        guard let result = workspace.operationResultsByID[repository.id],
              case .skipped = result.outcome else { return nil }
        return result
    }

    private func repositoryStatusTitle(_ repository: SourceControlRepository) -> String {
        if let result = workspace.operationResultsByID[repository.id] {
            switch result.outcome {
            case .updated: return "已更新"
            case .upToDate: return "已最新"
            case .skipped: return "已跳过"
            case .cancelled: return "已取消"
            case .failed: return "失败"
            }
        }
        if !repository.isFastForwardCandidate { return "需处理" }
        return repository.behind > 0 ? "待更新" : "已最新"
    }

    /// 行详情只在有信息量时返回（sha 与落后/跳过/失败原因），
    /// 避免与右侧状态徽章重复的「与远端一致」填充文案。
    private func repositoryDetail(_ repository: SourceControlRepository) -> String? {
        if workspace.activeUpdatePath == repository.path { return "正在拉取最新代码…" }
        if let result = workspace.operationResultsByID[repository.id],
           case let .failed(diagnostic) = result.outcome {
            return diagnostic.summary
        }
        var parts: [String] = []
        if !repository.shortRevision.isEmpty { parts.append(repository.shortRevision) }
        if repository.behind > 0 { parts.append("落后 \(repository.behind)") }
        if let reason = skipReason(repository) { parts.append(reason) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// UI 侧从扫描数据推导「需处理」的具体原因（执行器仍按 Core 规则跳过）。
    private func skipReason(_ repository: SourceControlRepository) -> String? {
        guard !repository.isFastForwardCandidate else { return nil }
        if repository.diagnostic != nil { return "状态读取失败" }
        if repository.status == .conflicted { return "存在未解决冲突" }
        if repository.status == .modified { return "有未提交改动" }
        if repository.status == .untracked { return "有未跟踪文件" }
        if repository.remote == nil { return "未配置远端" }
        if !repository.hasUpstream { return "未配置 upstream" }
        if repository.branch.isEmpty || repository.branch == "HEAD" { return "分离头指针" }
        if repository.remoteState == .diverged { return "与远端分叉" }
        if repository.remoteState == .localAhead { return "本地领先" }
        return nil
    }

    private func repositoryStatusTone(_ repository: SourceControlRepository) -> IndexBadgeTone {
        if let result = workspace.operationResultsByID[repository.id] {
            switch result.outcome {
            case .updated, .upToDate: return .success
            case .failed: return .warning
            case .skipped, .cancelled: return .neutral
            }
        }
        if !repository.isFastForwardCandidate { return .warning }
        return repository.behind > 0 ? .accent : .success
    }

    private func chooseDirectory() {
        Task { @MainActor in
            do {
                let request = FileInputPanelRequest(title: "选择工作区目录", canChooseDirectories: true, canChooseFiles: false)
                if let url = try await fileInputPanelClient.selectFile(request), url.path != workspace.path {
                    workspace.setPath(url.path)
                }
            } catch {
                // 面板取消/失败保持现状：不得清空已扫描结果。
            }
        }
    }
}

// MARK: - Checkbox

/// 三态全选 checkbox（macOS HIG：父级控制多个子级时，子级状态不一致必须
/// 显示 mixed 横线态）。点击语义：全部可见已选 → 取消全部；否则 → 全选可见。
private struct SourceControlSelectAllCheckbox: View {
    let state: Bool?
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                SourceControlCheckboxShape(state: state, size: 17)
                Text(label)
                    .font(ToolTypography.label)
                    .foregroundStyle(ToolTheme.textSecondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(IndexBareButtonStyle())
        .accessibilityLabel("全选当前列表")
        .accessibilityValue(state == true ? "已全选" : (state == false ? "未选择" : "部分选择"))
        .toolAnimation(ToolMotion.Preset.controlFeedback, value: state)
    }
}

private struct SourceControlRowCheckbox: View {
    let isChecked: Bool

    var body: some View {
        SourceControlCheckboxShape(state: isChecked, size: 16)
            .toolAnimation(ToolMotion.Preset.controlFeedback, value: isChecked)
    }
}

/// 勾选框视觉：`true` 勾、`false` 空、`nil` mixed 横线。固定尺寸槽位，
/// 切换只动内部图形，不改变行高与命中区。
private struct SourceControlCheckboxShape: View {
    let state: Bool?
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.nestedControl, style: .continuous)
                .fill(fillColor)
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.nestedControl, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
            Image(systemName: state == nil ? "minus" : "checkmark")
                .font(ToolTypography.controlLabel(weight: .semibold))
                .foregroundStyle(state == true ? ToolTheme.onAccent : ToolTheme.accent)
                .accessibilityHidden(true)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var fillColor: Color {
        switch state {
        case true: return ToolTheme.accent
        case nil: return ToolTheme.accentSoft
        case false: return ToolTheme.editorBackground
        }
    }

    private var borderColor: Color {
        switch state {
        case true: return ToolTheme.accent
        case nil: return ToolTheme.accentBorder
        case false: return ToolTheme.strongBorder
        }
    }
}

// MARK: - Failure Summary Sheet

/// 批量更新完成后的失败汇总（HIG：部分失败汇总一处，避免逐个弹窗）。
/// 计数与失败列表来自模型里的类型化结果，展示层不解析显示字符串。
private struct SourceControlFailureSummarySheet: View {
    let failures: [SourceControlWorkspaceModel.UpdateFailureSummary]
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(ToolTheme.warning)
                    .font(.system(size: ToolMetrics.IconSize.large))
                Text("\(failures.count) 个仓库更新失败")
                    .font(ToolTypography.sectionTitle)
                Spacer()
            }
            Text("失败的仓库未影响其余仓库的拉取。可在下方查看原因，或直接重试失败项。")
                .font(ToolTypography.caption)
                .foregroundStyle(ToolTheme.textSecondary)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(failures) { failure in
                        failureRow(failure)
                    }
                }
                .padding(.vertical, 1)
            }
            .frame(maxHeight: 300)
            .background(
                RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                    .fill(ToolTheme.utilityBackground)
            )
            .overlay {
                RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                    .strokeBorder(ToolTheme.border, lineWidth: 1)
            }
            HStack {
                Spacer()
                Button("关闭", action: onDismiss)
                    .buttonStyle(IndexSmallButtonStyle(framed: true))
                    .keyboardShortcut(.cancelAction)
                Button { onRetry() } label: {
                    Label("重试失败项（\(failures.count)）", systemImage: "arrow.clockwise")
                }
                .buttonStyle(IndexButtonStyle(primary: true))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
        .background(ToolTheme.panelBackground)
    }

    private func failureRow(_ failure: SourceControlWorkspaceModel.UpdateFailureSummary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(ToolTheme.warning)
                    .font(.system(size: ToolMetrics.IconSize.small))
                    .accessibilityHidden(true)
                Text(URL(fileURLWithPath: failure.repository.path).lastPathComponent)
                    .font(ToolTypography.bodyMedium)
                    .lineLimit(1)
                if !failure.repository.branch.isEmpty, failure.repository.branch != "HEAD" {
                    Text(failure.repository.branch)
                        .font(ToolTypography.monoCaption)
                        .foregroundStyle(ToolTheme.textTertiary)
                        .lineLimit(1)
                }
                if let host = SourceControlWorkspaceModel.remoteHost(from: failure.repository.remote) {
                    Text(host)
                        .font(ToolTypography.micro)
                        .foregroundStyle(ToolTheme.textTertiary)
                }
                Spacer()
                IndexBadge(failure.diagnostic.shortLabel, tone: .warning)
            }
            Text(failure.repository.path)
                .font(ToolTypography.caption)
                .foregroundStyle(ToolTheme.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(failure.diagnostic.summary)
                .font(ToolTypography.caption)
                .foregroundStyle(ToolTheme.textSecondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous)
                .fill(ToolTheme.panelBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous)
                .strokeBorder(ToolTheme.warningSoft, lineWidth: 1)
        }
    }
}

// MARK: - Hover Highlight

/// 可点选列表行的悬停反馈：柔和 hoverFill 底 + 整行 contentShape 命中区。
/// `enabled` 为 false 时不渲染悬停底色——禁用行不应假装可点。
private struct HoverHighlight: ViewModifier {
    var enabled: Bool = true

    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous)
                    .fill(enabled && hovered ? ToolTheme.hoverFill : Color.clear)
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                hovered = hovering
            }
    }
}

private extension View {
    func hoverHighlight(enabled: Bool = true) -> some View {
        modifier(HoverHighlight(enabled: enabled))
    }
}

private extension SourceControlOperationOutcome {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}
