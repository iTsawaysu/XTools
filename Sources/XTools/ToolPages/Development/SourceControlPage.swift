import SwiftUI
import XToolsCore

@MainActor
final class SourceControlWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<SourceControlWorkspaceModel>(toolID: "source-control") { preferences in
        SourceControlWorkspaceModel(preferences: preferences)
    }

    enum ScopeMode: String, CaseIterable, Identifiable {
        case machine
        case directory

        var id: String { rawValue }

        var title: String {
            switch self {
            case .machine: return "整机扫描"
            case .directory: return "指定目录"
            }
        }
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

    @Published private(set) var mode: ScopeMode
    @Published var path = ""
    @Published private(set) var repositories: [SourceControlRepository] = []
    @Published private(set) var selectedPaths: Set<String> = []
    @Published private(set) var isScanning = false
    @Published private(set) var isUpdating = false
    @Published private(set) var diagnostic: SourceControlDiagnostic?
    @Published private(set) var operationResults: [SourceControlOperationResult] = []
    @Published private(set) var failureSummary: [UpdateFailureSummary] = []
    @Published private(set) var lastCompletion: UpdateCompletionSummary?
    /// Repository currently being pulled (serial run) for the row spinner.
    @Published private(set) var activeUpdatePath: String?
    @Published private(set) var updateRunCompleted = 0
    @Published private(set) var updateRunTotal = 0
    @Published var gitLabURL = "https://gitlab.example.com"
    @Published var projectPath = ""
    @Published var mergeRepositoryPath = ""
    @Published var sourceBranch = ""
    @Published var targetBranch = "main"
    @Published var mergeTitle = ""
    @Published var mergeDescription = ""
    @Published var token = ""
    @Published private(set) var mergeDiagnostic: SourceControlDiagnostic?
    @Published private(set) var preflight: GitLabPreflightResult?
    @Published private(set) var createdMergeRequest: GitLabMergeRequest?
    @Published private(set) var isCheckingMerge = false
    @Published private(set) var isCreatingMerge = false
    @Published private(set) var discoveredProjects: [RemoteRepositorySummary] = []
    @Published private(set) var discoveredService: RemoteRepositoryService?
    @Published private(set) var selectedDiscoveredID: RemoteRepositorySummary.ID?
    @Published private(set) var isDiscovering = false
    @Published private(set) var discoveryDiagnostic: SourceControlDiagnostic?

    private let preferences: ToolPreferenceStore
    private let scanner: SourceControlScanner
    private let updater: SourceControlUpdateExecutor
    private var hasScannedInSession = false
    private var task: Task<Void, Never>?
    private var generation = 0
    private var discoveryTask: Task<Void, Never>?
    private var discoveryGeneration = 0
    private let mergeClient = GitLabMergeRequestClient()
    private let discoveryClient = RemoteRepositoryDiscoveryClient()

    init(
        preferences: ToolPreferenceStore = ToolPreferenceStore(),
        scanner: SourceControlScanner = SourceControlScanner(),
        updater: SourceControlUpdateExecutor = SourceControlUpdateExecutor()
    ) {
        self.preferences = preferences
        self.scanner = scanner
        self.updater = updater
        mode = ScopeMode(rawValue: preferences.value(for: SourceControlToolPreferenceKeys.scanMode)) ?? .machine
        path = preferences.value(for: SourceControlToolPreferenceKeys.scanDirectory)
    }

    var selectedRepositories: [SourceControlRepository] {
        repositories.filter { selectedPaths.contains($0.path) }
    }

    var mergeRepository: SourceControlRepository? {
        repositories.first { $0.path == mergeRepositoryPath }
    }

    /// The scope caption shown next to the repository list.
    var scopeTitle: String {
        switch mode {
        case .machine: return "主目录 · 整机扫描"
        case .directory:
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "指定目录" : "目录：\(trimmed)"
        }
    }

    var targetBranchOptions: [String] {
        var options: [String] = []
        if let defaultBranch = mergeRepository?.defaultBranch, !defaultBranch.isEmpty {
            options.append(defaultBranch)
        }
        options.append(contentsOf: mergeRepository?.branches ?? [])
        options.append(contentsOf: ["main", "develop", "release"])
        options = options.reduce(into: []) { result, branch in
            if !branch.isEmpty, !result.contains(branch) { result.append(branch) }
        }
        if !targetBranch.isEmpty, !options.contains(targetBranch) { options.insert(targetBranch, at: 0) }
        return options
    }

    func selectMergeRepository(_ path: String) {
        mergeRepositoryPath = path
        guard let repository = repositories.first(where: { $0.path == path }) else { return }
        sourceBranch = repository.branch == "HEAD" ? "" : repository.branch
        if projectPath.isEmpty, let remote = repository.remote {
            let reference = Self.gitLabReference(from: remote)
            if let host = reference.host, gitLabURL == "https://gitlab.example.com" {
                gitLabURL = "https://\(host)"
            }
            if let project = reference.projectPath { projectPath = project }
        }
    }

    private static func gitLabReference(from remote: String) -> (host: String?, projectPath: String?) {
        if let url = URL(string: remote), let host = url.host {
            var path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if path.hasSuffix(".git") { path.removeLast(4) }
            return (host, path.isEmpty ? nil : path)
        }
        guard let at = remote.firstIndex(of: "@"), let colon = remote[at...].firstIndex(of: ":") else {
            return (nil, nil)
        }
        let host = String(remote[remote.index(after: at)..<colon])
        var path = String(remote[remote.index(after: colon)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.hasSuffix(".git") { path.removeLast(4) }
        return (host.isEmpty ? nil : host, path.isEmpty ? nil : path)
    }

    var canScan: Bool {
        (mode == .machine || !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && !isScanning && !isUpdating && !isCheckingMerge && !isCreatingMerge
    }
    var canUpdate: Bool {
        !selectedRepositories.isEmpty
            && !isScanning && !isUpdating && !isCheckingMerge && !isCreatingMerge
    }
    var canDiscover: Bool {
        guard let url = URL(string: gitLabURL.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return url.host != nil && !isDiscovering
    }

    /// 选中项目是否来自 GitHub 发现：PR 创建是 GitLab 专属 API，提前拦下。
    private var selectedDiscoveredProjectIsGitHub: Bool {
        discoveredProjects.first { $0.id == selectedDiscoveredID }?.service == .github
    }

    func appendOperationResult(_ result: SourceControlOperationResult, generation expectedGeneration: Int? = nil) {
        if let expectedGeneration, expectedGeneration != generation { return }
        operationResults.removeAll { $0.repository.id == result.repository.id }
        operationResults.append(result)
    }

    func setMode(_ newMode: ScopeMode) {
        guard newMode != mode else { return }
        task?.cancel()
        generation &+= 1
        isScanning = false
        isUpdating = false
        isCheckingMerge = false
        isCreatingMerge = false
        mode = newMode
        preferences.set(newMode.rawValue, for: SourceControlToolPreferenceKeys.scanMode)
        resetScanDerivedState()
    }

    func setPath(_ value: String) {
        task?.cancel()
        generation &+= 1
        isScanning = false
        isUpdating = false
        isCheckingMerge = false
        isCreatingMerge = false
        path = value
        preferences.set(value, for: SourceControlToolPreferenceKeys.scanDirectory)
        resetScanDerivedState()
    }

    private func resetScanDerivedState() {
        repositories = []
        selectedPaths = []
        diagnostic = nil
        operationResults = []
        failureSummary = []
        preflight = nil
        createdMergeRequest = nil
        mergeDiagnostic = nil
        activeUpdatePath = nil
        updateRunCompleted = 0
        updateRunTotal = 0
        updateOrder = []
    }

    /// 回车或按钮触发：扫描当前 Git 服务地址上 Token 有权限访问的项目。
    /// 独立于同步任务（discoveryTask），不与扫描/更新互相打断。
    func discoverProjects() {
        guard canDiscover else { return }
        let hostURL = URL(string: gitLabURL.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let hostURL else {
            discoveryDiagnostic = SourceControlError.invalidGitLabURL.diagnostic
            return
        }
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            discoveryDiagnostic = SourceControlError.invalidToken.diagnostic
            return
        }
        discoveryTask?.cancel()
        discoveryGeneration &+= 1
        let operationGeneration = discoveryGeneration
        isDiscovering = true
        discoveryDiagnostic = nil
        discoveryTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await discoveryClient.discover(hostURL: hostURL, token: token)
                guard !Task.isCancelled, discoveryGeneration == operationGeneration else { return }
                discoveredProjects = result.projects
                discoveredService = result.service
                selectedDiscoveredID = nil
            } catch is CancellationError {
                return
            } catch let error as SourceControlError {
                guard discoveryGeneration == operationGeneration else { return }
                discoveryDiagnostic = error.diagnostic
            } catch {
                guard discoveryGeneration == operationGeneration else { return }
                discoveryDiagnostic = SourceControlError.invalidResponse.diagnostic
            }
            if discoveryGeneration == operationGeneration {
                isDiscovering = false
            }
        }
    }

    /// 点击发现列表中的一行：预填项目路径，并把目标分支设为项目默认分支。
    func selectDiscoveredProject(_ summary: RemoteRepositorySummary) {
        selectedDiscoveredID = summary.id
        projectPath = summary.pathWithNamespace
        if let branch = summary.defaultBranch, !branch.isEmpty {
            targetBranch = branch
        }
    }

    func cancelDiscovery() {
        discoveryTask?.cancel()
        discoveryGeneration &+= 1
        isDiscovering = false
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
        let scope: SourceControlScanScope = mode == .machine
            ? .machine
            : .directory(path: path.trimmingCharacters(in: .whitespacesAndNewlines))
        isScanning = true
        diagnostic = nil
        failureSummary = []
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await scanner.scan(scope: scope)
                guard !Task.isCancelled, generation == operationGeneration else { return }
                repositories = snapshot.repositories
                // 默认全选：成熟工具（SourceTree / JetBrains Update Project /
                // gita）在发现后都作用于全部结果；不可安全快进的仓库在
                // 更新时按安全规则跳过并在行内说明原因。
                selectedPaths = Set(snapshot.repositories.map(\.path))
                if mergeRepositoryPath.isEmpty || !snapshot.repositories.contains(where: { $0.path == mergeRepositoryPath }) {
                    if let first = snapshot.repositories.first {
                        selectMergeRepository(first.path)
                    }
                }
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
            }
        }
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

    func invalidateMergePreflight() {
        if isCheckingMerge || isCreatingMerge {
            task?.cancel()
            generation &+= 1
            isCheckingMerge = false
            isCreatingMerge = false
        }
        preflight = nil
        createdMergeRequest = nil
        mergeDiagnostic = nil
    }

    // MARK: - Update

    func update() {
        guard canUpdate else { return }
        startUpdate(selectedRepositories, resetResults: true)
    }

    func retry(_ repository: SourceControlRepository) {
        guard !isScanning, !isUpdating, !isCheckingMerge, !isCreatingMerge else { return }
        startUpdate([repository], resetResults: false)
    }

    /// 失败汇总 sheet 的「重试失败项」：只重跑失败的仓库，保留其余结果。
    /// 重试目标优先取刷新扫描里仍是快进候选的数据；刷新快照在仓库已
    /// 恢复干净时是陈旧的（会把它标成不可快进），此时回退到失败时的
    /// 快照——执行器拉取前会重新对磁盘做安全校验，不会绕过保护。
    func retryFailures() {
        guard !failureSummary.isEmpty,
              !isScanning, !isUpdating, !isCheckingMerge, !isCreatingMerge else { return }
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

    private func startUpdate(_ targets: [SourceControlRepository], resetResults: Bool) {
        guard !targets.isEmpty else { return }
        task?.cancel()
        generation &+= 1
        let operationGeneration = generation
        isUpdating = true
        diagnostic = nil
        if resetResults {
            operationResults = []
            failureSummary = []
        } else {
            let targetIDs = Set(targets.map(\.id))
            operationResults.removeAll { targetIDs.contains($0.repository.id) }
        }
        updateRunCompleted = 0
        updateRunTotal = targets.count
        updateOrder = targets.map(\.path)
        activeUpdatePath = targets.first?.path
        task = Task { [weak self] in
            guard let self else { return }
            _ = await updater.update(repositories: targets) { [weak self] result in
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

    /// 从本次运行的目标推导类型化完成计数与失败汇总。
    private func publishCompletion(for targets: [SourceControlRepository]) {
        let outcomesByID = Dictionary(operationResults.map { ($0.repository.id, $0.outcome) }, uniquingKeysWith: { _, last in last })
        var updated = 0, upToDate = 0, skipped = 0, failed = 0
        var failures: [UpdateFailureSummary] = []
        for target in targets {
            switch outcomesByID[target.id] {
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
        lastCompletion = UpdateCompletionSummary(
            updatedCount: updated,
            upToDateCount: upToDate,
            skippedCount: skipped,
            failedCount: failed
        )
    }

    /// 更新完成后的状态重扫：不清失败汇总与结果行，选择恢复为全选。
    private func refreshAfterUpdate() {
        let operationGeneration = generation
        let scope: SourceControlScanScope = mode == .machine
            ? .machine
            : .directory(path: path.trimmingCharacters(in: .whitespacesAndNewlines))
        isScanning = true
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await scanner.scan(scope: scope)
                guard !Task.isCancelled, generation == operationGeneration else { return }
                repositories = snapshot.repositories
                selectedPaths = Set(snapshot.repositories.map(\.path))
                if mergeRepositoryPath.isEmpty || !snapshot.repositories.contains(where: { $0.path == mergeRepositoryPath }) {
                    if let first = snapshot.repositories.first {
                        selectMergeRepository(first.path)
                    }
                }
            } catch {
                // 刷新失败不打断刚完成的更新结果；保留现有列表。
            }
            if generation == operationGeneration {
                isScanning = false
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
        isUpdating = false
        isCheckingMerge = false
        isCreatingMerge = false
        activeUpdatePath = nil
        cancelDiscovery()
    }

    func checkMergeRequest() {
        guard !isCheckingMerge, !isCreatingMerge, !isScanning, !isUpdating else { return }
        if selectedDiscoveredProjectIsGitHub {
            mergeDiagnostic = SourceControlError.pullRequestUnsupported.diagnostic
            return
        }
        guard let url = URL(string: gitLabURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            mergeDiagnostic = SourceControlError.invalidGitLabURL.diagnostic
            return
        }
        let input = GitLabMergeRequestInput(gitLabURL: url, projectPath: projectPath, sourceBranch: sourceBranch, targetBranch: targetBranch, title: mergeTitle, description: mergeDescription)
        isCheckingMerge = true
        mergeDiagnostic = nil
        preflight = nil
        task?.cancel()
        generation &+= 1
        let operationGeneration = generation
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await mergeClient.preflight(input, token: token)
                guard generation == operationGeneration else { return }
                preflight = result
            } catch let error as SourceControlError {
                guard generation == operationGeneration else { return }
                mergeDiagnostic = error.diagnostic
            } catch {
                guard generation == operationGeneration else { return }
                mergeDiagnostic = SourceControlError.invalidResponse.diagnostic
            }
            if generation == operationGeneration { isCheckingMerge = false }
        }
    }

    func createMergeRequest() {
        guard case .ready? = preflight, !isCreatingMerge, !isScanning, !isUpdating else { return }
        guard let url = URL(string: gitLabURL.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        let input = GitLabMergeRequestInput(gitLabURL: url, projectPath: projectPath, sourceBranch: sourceBranch, targetBranch: targetBranch, title: mergeTitle, description: mergeDescription)
        isCreatingMerge = true
        mergeDiagnostic = nil
        task?.cancel()
        generation &+= 1
        let operationGeneration = generation
        task = Task { [weak self] in
            guard let self else { return }
            do {
                // Re-run the opened-MR check after the user confirmation. The
                // preflight shown on screen may be stale by the time POST runs.
                let latestPreflight = try await mergeClient.preflight(input, token: token)
                guard case .ready = latestPreflight else {
                    guard generation == operationGeneration else { return }
                    preflight = latestPreflight
                    isCreatingMerge = false
                    return
                }
                let result = try await mergeClient.create(input, token: token)
                guard generation == operationGeneration else { return }
                createdMergeRequest = result
            } catch let error as SourceControlError {
                guard generation == operationGeneration else { return }
                mergeDiagnostic = error.diagnostic
            } catch {
                guard generation == operationGeneration else { return }
                mergeDiagnostic = SourceControlError.invalidResponse.diagnostic
            }
            if generation == operationGeneration { isCreatingMerge = false }
        }
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
    @State private var section = "sync"
    @State private var showsToken = false
    @State private var repositoryQuery = ""
    @State private var repositoryFilter = "all"
    @State private var showsUpdateConfirmation = false
    @State private var showsMergeConfirmation = false
    @State private var showsFailureSheet = false

    private var visibleRepositories: [SourceControlRepository] {
        let query = repositoryQuery.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        return workspace.repositories.filter { repository in
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
    }

    /// 可见行整体的勾选状态：false 全空 / true 全选 / nil 部分（三态）。
    private var visibleSelectionState: Bool? {
        let visiblePaths = Set(visibleRepositories.map(\.path))
        guard !visiblePaths.isEmpty else { return false }
        let selectedCount = workspace.selectedPaths.intersection(visiblePaths).count
        if selectedCount == 0 { return false }
        return selectedCount == visiblePaths.count ? true : nil
    }

    private var selectedVisibleCount: Int {
        workspace.selectedPaths.intersection(Set(visibleRepositories.map(\.path))).count
    }

    /// 细线进度读数：本次运行已处理 / 目标仓库数。
    private var updateFraction: Double? {
        guard workspace.isUpdating, workspace.updateRunTotal > 0 else { return nil }
        return Double(workspace.updateRunCompleted) / Double(workspace.updateRunTotal)
    }

    var body: some View {
        IndexPage("源码管理", subtitle: "同步本地 Git 仓库，并创建 GitLab Merge Request。", workspaceSemantic: .queryListWorkspace) {
            IndexSegmentedControl(
                items: [("sync", "仓库同步"), ("merge", "创建 Merge Request")],
                selection: $section,
                density: .regular
            )
            if section == "sync" {
                syncSection
                    .task { workspace.scanOnAppearIfNeeded() }
            } else {
                mergeSection
            }
        }
        .alert("确认更新仓库？", isPresented: $showsUpdateConfirmation) {
            Button("取消", role: .cancel) {}
            Button("确认更新") { workspace.update() }
        } message: {
            Text("将按顺序对所选仓库执行 git pull --ff-only。有未提交改动、没有 upstream 或无法快进的仓库会自动跳过，失败不会影响其余仓库。")
        }
        .alert("确认创建 Merge Request？", isPresented: $showsMergeConfirmation) {
            Button("取消", role: .cancel) {}
            Button("创建") { workspace.createMergeRequest() }
        } message: {
            Text("创建前会再次查询相同源分支和目标分支的 opened MR，避免重复请求。Token 只用于当前请求。")
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
            VStack(alignment: .leading, spacing: 10) {
                IndexSegmentedControl(
                    items: SourceControlWorkspaceModel.ScopeMode.allCases.map { ($0.id, $0.title) },
                    selection: Binding(
                        get: { workspace.mode.id },
                        set: { workspace.setMode(.init(rawValue: $0) ?? .machine) }
                    ),
                    density: .compact
                )
                .disabled(workspace.isScanning || workspace.isUpdating)
                if workspace.mode == .directory {
                    HStack(spacing: 8) {
                        IndexTextInput(
                            placeholder: "工作区目录，例如 ~/work",
                            text: Binding(get: { workspace.path }, set: workspace.setPath),
                            onSubmit: { workspace.scan() }
                        )
                        Button { chooseDirectory() } label: { Label("选择", systemImage: "folder") }
                            .buttonStyle(IndexSmallButtonStyle())
                            .disabled(workspace.isScanning || workspace.isUpdating)
                    }
                    Text("扫描该目录（含子目录）下的所有 Git 仓库。目录会被记住，下次打开时自动恢复。")
                        .font(ToolTypography.caption)
                        .foregroundStyle(ToolTheme.textTertiary)
                } else {
                    Text("扫描当前用户主目录下的所有 Git 仓库，忽略资源库、媒体与依赖缓存目录。")
                        .font(ToolTypography.caption)
                        .foregroundStyle(ToolTheme.textTertiary)
                }
                HStack(spacing: 8) {
                    Button { workspace.scan() } label: {
                        IndexProgressMotionLabel(
                            title: workspace.isScanning ? "扫描中…" : "扫描仓库",
                            systemImage: "arrow.clockwise",
                            isProcessing: workspace.isScanning,
                            id: workspace.isScanning
                        )
                    }
                    .buttonStyle(IndexButtonStyle())
                    .disabled(!workspace.canScan)
                    if workspace.isScanning || workspace.isUpdating {
                        Button("取消") { workspace.cancel() }.buttonStyle(IndexSmallButtonStyle())
                    }
                }
            }
        } accessory: { Text("只执行 git pull --ff-only").font(ToolTypography.caption).foregroundStyle(ToolTheme.textSecondary) }
    }

    private var repositoryPanel: some View {
        IndexPanel("仓库（\(workspace.repositories.count)）") {
            if workspace.repositories.isEmpty {
                if workspace.isScanning {
                    IndexProgressLabel(message: "正在扫描工作目录…", layout: .centered)
                } else {
                    IndexEmptyState(
                        title: "尚未扫描仓库",
                        systemImage: "shippingbox",
                        message: workspace.mode == .directory ? "选择目录后开始扫描" : "点击「扫描仓库」扫描本机仓库"
                    )
                }
            } else {
                VStack(spacing: 6) {
                    repositoryToolbar
                    if workspace.isScanning {
                        IndexProgressHairline(isIndeterminate: true)
                    }
                    if workspace.isUpdating {
                        IndexProgressHairline(fraction: updateFraction)
                    }
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(visibleRepositories) { repository in
                                repositoryRow(repository)
                            }
                        }
                    }
                    if workspace.isUpdating {
                        Text("已处理 \(workspace.updateRunCompleted) / \(workspace.updateRunTotal) 个仓库")
                            .font(ToolTypography.caption)
                            .foregroundStyle(ToolTheme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if visibleRepositories.isEmpty {
                        IndexEmptyState(title: "没有匹配的仓库", systemImage: "line.3.horizontal.decrease.circle", message: "试试清空搜索或切换筛选条件")
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        } accessory: {
            Text(workspace.scopeTitle)
                .font(ToolTypography.caption)
                .foregroundStyle(ToolTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .verticallyFilling()
        .indexWorkspaceDiagnostic(workspace.diagnostic?.summary)
    }

    private var repositoryToolbar: some View {
        HStack(spacing: 8) {
            SourceControlSelectAllCheckbox(
                state: visibleSelectionState,
                label: "已选 \(selectedVisibleCount)/\(visibleRepositories.count)"
            ) {
                let visiblePaths = Set(visibleRepositories.map(\.path))
                workspace.setVisibleSelection(visiblePaths, selected: visibleSelectionState != true)
            }
            .disabled(workspace.isUpdating)
            IndexSearchInput(placeholder: "搜索仓库或分支", text: $repositoryQuery, height: 30)
                .frame(maxWidth: 220)
            IndexOptionMenu(
                items: [("all", "全部"), ("update", "待更新"), ("latest", "已最新"), ("attention", "需处理")],
                selection: $repositoryFilter,
                title: "筛选"
            )
            Spacer()
            Button { showsUpdateConfirmation = true } label: {
                IndexProgressMotionLabel(
                    title: workspace.isUpdating
                        ? "更新中 \(workspace.updateRunCompleted)/\(workspace.updateRunTotal)…"
                        : "更新所选（\(workspace.selectedPaths.count)）",
                    systemImage: "arrow.down.circle",
                    isProcessing: workspace.isUpdating,
                    id: workspace.isUpdating
                )
            }
            .buttonStyle(IndexButtonStyle(primary: true))
            .disabled(!workspace.canUpdate)
        }
    }

    private func repositoryRow(_ repository: SourceControlRepository) -> some View {
        let isSelected = workspace.selectedPaths.contains(repository.path)
        let isActive = workspace.activeUpdatePath == repository.path
        // 行内重试回放当时的快照（拉取前执行器会重新校验磁盘状态）。
        let failedResult = workspace.operationResults.last(where: { $0.repository.id == repository.id })
        return HStack(spacing: 8) {
            Button {
                workspace.toggleSelection(repository)
            } label: {
                HStack(spacing: 10) {
                    SourceControlRowCheckbox(isChecked: isSelected)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(URL(fileURLWithPath: repository.path).lastPathComponent)
                                .font(ToolTypography.bodyMedium)
                                .lineLimit(1)
                            Text(repository.branch)
                                .font(ToolTypography.monoCaption)
                                .foregroundStyle(ToolTheme.textSecondary)
                                .lineLimit(1)
                        }
                        Text(repository.path)
                            .font(ToolTypography.caption)
                            .foregroundStyle(ToolTheme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(repositoryDetail(repository))
                            .font(ToolTypography.caption)
                            .foregroundStyle(ToolTheme.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    if isActive {
                        IndexProgressSpinner()
                            .help("正在拉取")
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
            .help("切换选中：\(URL(fileURLWithPath: repository.path).lastPathComponent)")
            if let failedResult, failedResult.outcome.isFailure {
                Button("重试") { workspace.retry(failedResult.repository) }
                    .buttonStyle(IndexSmallButtonStyle())
                    .disabled(workspace.isUpdating || workspace.isScanning)
            }
        }
    }

    private func discoveredProjectRow(_ project: RemoteRepositorySummary) -> some View {
        let isSelected = workspace.selectedDiscoveredID == project.id
        return Button { workspace.selectDiscoveredProject(project) } label: {
            HStack(spacing: 9) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? ToolTheme.accent : ToolTheme.textTertiary)
                    .font(.system(size: ToolMetrics.IconSize.large))
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name).font(ToolTypography.bodyMedium).lineLimit(1)
                    Text(project.pathWithNamespace).font(ToolTypography.caption).foregroundStyle(ToolTheme.textTertiary).lineLimit(1)
                }
                Spacer()
                if project.service == .github {
                    IndexBadge("GitHub", tone: .neutral)
                }
                if let branch = project.defaultBranch, !branch.isEmpty {
                    IndexBadge(branch, tone: .neutral)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .hoverHighlight()
        }
        .buttonStyle(IndexBareButtonStyle())
    }

    private func repositoryStatusTitle(_ repository: SourceControlRepository) -> String {
        if let result = workspace.operationResults.last(where: { $0.repository.id == repository.id }) {
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

    private func repositoryDetail(_ repository: SourceControlRepository) -> String {
        if workspace.activeUpdatePath == repository.path { return "正在拉取最新代码…" }
        if let result = workspace.operationResults.last(where: { $0.repository.id == repository.id }),
           case let .failed(diagnostic) = result.outcome {
            return diagnostic.summary
        }
        var detail = repository.behind > 0 ? "落后 \(repository.behind) 个提交" : "与远端一致"
        if let reason = skipReason(repository) {
            detail += " · \(reason)，更新时会跳过"
        }
        return "\(repository.shortRevision) · \(detail)"
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
        if let result = workspace.operationResults.last(where: { $0.repository.id == repository.id }) {
            switch result.outcome {
            case .updated, .upToDate: return .success
            case .failed: return .warning
            case .skipped, .cancelled: return .neutral
            }
        }
        if !repository.isFastForwardCandidate { return .warning }
        return repository.behind > 0 ? .accent : .success
    }

    // MARK: - Merge

    private var mergeSection: some View {
        // .fill 布局无外层滚动，merge 段面板多于视口时自行滚动。
        ScrollView {
            VStack(spacing: ToolMetrics.Spacing.md) {
                connectionSection
                mergeRequestForm
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    // ① 地址 + Token → 回车 → 扫描有权限的项目（细线加载动画 + 可点选列表）
    private var connectionSection: some View {
        IndexPanel("连接 Git 服务") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    IndexTextInput(
                        placeholder: "Git 服务地址（GitLab / GitHub）",
                        text: $workspace.gitLabURL,
                        onSubmit: { workspace.discoverProjects() }
                    )
                    Button { workspace.discoverProjects() } label: {
                        IndexProgressMotionLabel(
                            title: workspace.isDiscovering ? "扫描中…" : "查找项目",
                            systemImage: "magnifyingglass",
                            isProcessing: workspace.isDiscovering,
                            id: workspace.isDiscovering
                        )
                    }
                    .buttonStyle(IndexButtonStyle())
                    .disabled(!workspace.canDiscover)
                }
                IndexSecureInput(
                    placeholder: "访问 Token（仅保留在当前页面）",
                    text: $workspace.token,
                    showsSecret: $showsToken,
                    secretNoun: "Token"
                )
                if !workspace.token.isEmpty {
                    HStack {
                        Spacer()
                        Button("清除 Token") { workspace.token = ""; showsToken = false }
                            .buttonStyle(IndexSmallButtonStyle())
                    }
                }
                if workspace.isDiscovering {
                    IndexProgressHairline(isIndeterminate: true)
                    Text("正在扫描有权限的项目…")
                        .font(ToolTypography.caption)
                        .foregroundStyle(ToolTheme.textSecondary)
                } else if !workspace.discoveredProjects.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(discoverySummaryTitle)
                            .font(ToolTypography.caption)
                            .foregroundStyle(ToolTheme.textSecondary)
                        ScrollView {
                            VStack(spacing: 4) {
                                ForEach(workspace.discoveredProjects) { project in
                                    discoveredProjectRow(project)
                                }
                            }
                        }
                        .frame(maxHeight: discoveryListHeight)
                    }
                }
            }
        } accessory: {
            Text("填好地址和 Token 后回车").font(ToolTypography.caption).foregroundStyle(ToolTheme.textSecondary)
        }
        .indexWorkspaceDiagnostic(workspace.discoveryDiagnostic?.summary)
    }

    private var discoverySummaryTitle: String {
        let service = workspace.discoveredService == .github ? "GitHub" : "GitLab"
        return "找到 \(workspace.discoveredProjects.count) 个有权限的项目（\(service)），点击选择："
    }

    /// 最多露出约 5 行，其余滚动查看。
    private var discoveryListHeight: CGFloat {
        CGFloat(min(max(workspace.discoveredProjects.count, 1), 5)) * 48 + 4
    }

    // ② MR 表单：项目路径（可由发现预填）、分支、标题、预检与创建
    private var mergeRequestForm: some View {
        IndexPanel("Merge Request") {
            VStack(alignment: .leading, spacing: 10) {
                if !workspace.repositories.isEmpty {
                    IndexOptionMenu(
                        items: workspace.repositories.map { ($0.path, URL(fileURLWithPath: $0.path).lastPathComponent) },
                        selection: Binding(get: { workspace.mergeRepositoryPath }, set: workspace.selectMergeRepository),
                        title: "本地仓库"
                    )
                }
                IndexTextInput(placeholder: "项目路径，例如 group/project（可由上方发现预填）", text: $workspace.projectPath)
                HStack(spacing: 8) {
                    IndexTextInput(placeholder: "源分支", text: $workspace.sourceBranch)
                    IndexOptionMenu(items: workspace.targetBranchOptions.map { ($0, $0) }, selection: $workspace.targetBranch, title: "目标分支")
                }
                IndexTextInput(placeholder: "标题", text: $workspace.mergeTitle)
                IndexTextInput(placeholder: "描述（可选）", text: $workspace.mergeDescription, height: 64)
                HStack(spacing: 8) {
                    Button { workspace.checkMergeRequest() } label: { IndexProgressMotionLabel(title: workspace.isCheckingMerge ? "预检中…" : "预检", systemImage: "checkmark.shield", isProcessing: workspace.isCheckingMerge, id: workspace.isCheckingMerge) }.buttonStyle(IndexSmallButtonStyle()).disabled(workspace.token.isEmpty)
                    Button { showsMergeConfirmation = true } label: { IndexProgressMotionLabel(title: workspace.isCreatingMerge ? "创建中…" : "创建 Merge Request", systemImage: "arrow.up.right.square", isProcessing: workspace.isCreatingMerge, id: workspace.isCreatingMerge) }.buttonStyle(IndexButtonStyle()).disabled(workspace.isCreatingMerge || workspace.preflight != .ready)
                    if workspace.isCheckingMerge || workspace.isCreatingMerge {
                        Button("取消") { workspace.cancel() }.buttonStyle(IndexSmallButtonStyle())
                    }
                }
                if case let .duplicate(existing) = workspace.preflight {
                    Text("已存在开放请求 !\(existing.iid)，请打开现有请求或修改分支。")
                        .font(ToolTypography.caption).foregroundStyle(ToolTheme.warning)
                }
                if let created = workspace.createdMergeRequest {
                    Text("已创建 !\(created.iid)").font(ToolTypography.bodyMedium).foregroundStyle(ToolTheme.success)
                }
            }
        }
        .indexWorkspaceDiagnostic(workspace.mergeDiagnostic?.summary)
        .onChange(of: [workspace.gitLabURL, workspace.projectPath, workspace.sourceBranch, workspace.targetBranch, workspace.mergeTitle, workspace.token, workspace.mergeRepositoryPath]) { _ in
            workspace.invalidateMergePreflight()
        }
    }

    private func chooseDirectory() {
        Task { @MainActor in
            do {
                let request = FileInputPanelRequest(title: "选择工作区目录", canChooseDirectories: true, canChooseFiles: false)
                if let url = try await fileInputPanelClient.selectFile(request) { workspace.setPath(url.path) }
            } catch {
                workspace.setPath(workspace.path)
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
        .help("切换当前列表的全选状态")
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
                Text(URL(fileURLWithPath: failure.repository.path).lastPathComponent)
                    .font(ToolTypography.bodyMedium)
                    .lineLimit(1)
                Text(failure.repository.branch)
                    .font(ToolTypography.monoCaption)
                    .foregroundStyle(ToolTheme.textTertiary)
                    .lineLimit(1)
                Spacer()
                IndexBadge(failure.diagnostic.code, tone: .warning)
            }
            Text(failure.repository.path)
                .font(ToolTypography.caption)
                .foregroundStyle(ToolTheme.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text("\(failure.diagnostic.summary) \(failure.diagnostic.recovery)")
                .font(ToolTypography.caption)
                .foregroundStyle(ToolTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
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
