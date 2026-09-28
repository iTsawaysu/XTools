import SwiftUI
import XToolsCore

@MainActor
final class SourceControlWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<SourceControlWorkspaceModel>(toolID: "source-control") { _ in
        SourceControlWorkspaceModel()
    }

    enum ScopeMode: String, CaseIterable, Identifiable {
        case repository = "单个仓库"
        case directory = "工作区"
        var id: String { rawValue }
    }

    @Published var mode: ScopeMode = .directory
    @Published var path = ""
    @Published private(set) var repositories: [SourceControlRepository] = []
    @Published private(set) var selectedPaths: Set<String> = []
    @Published private(set) var isScanning = false
    @Published private(set) var isUpdating = false
    @Published private(set) var diagnostic: SourceControlDiagnostic?
    @Published private(set) var operationResults: [SourceControlOperationResult] = []
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

    private var task: Task<Void, Never>?
    private var generation = 0
    private var discoveryTask: Task<Void, Never>?
    private var discoveryGeneration = 0
    private let scanner = SourceControlScanner()
    private let updater = SourceControlUpdateExecutor()
    private let mergeClient = GitLabMergeRequestClient()
    private let discoveryClient = RemoteRepositoryDiscoveryClient()

    var selectedRepositories: [SourceControlRepository] {
        repositories.filter { selectedPaths.contains($0.path) }
    }

    var mergeRepository: SourceControlRepository? {
        repositories.first { $0.path == mergeRepositoryPath }
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
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.hasSuffix(".git") { path.removeLast(4) }
        return (host.isEmpty ? nil : host, path.isEmpty ? nil : path)
    }

    var canScan: Bool {
        !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        operationResults.append(result)
    }

    func setPath(_ value: String) {
        task?.cancel()
        generation &+= 1
        isScanning = false
        isUpdating = false
        isCheckingMerge = false
        isCreatingMerge = false
        path = value
        repositories = []
        selectedPaths = []
        diagnostic = nil
        operationResults = []
        preflight = nil
        createdMergeRequest = nil
        mergeDiagnostic = nil
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

    func scan() {
        guard canScan else { return }
        task?.cancel()
        generation &+= 1
        let operationGeneration = generation
        let selectedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedMode = mode
        isScanning = true
        diagnostic = nil
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let scope: SourceControlScanScope = selectedMode == .repository
                    ? .repository(path: selectedPath)
                    : .directory(path: selectedPath)
                let snapshot = try await scanner.scan(scope: scope)
                guard !Task.isCancelled, generation == operationGeneration else { return }
                repositories = snapshot.repositories
                selectedPaths = Set(snapshot.repositories.filter(\.isFastForwardCandidate).map(\.path))
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

    func toggleSelection(_ repository: SourceControlRepository) {
        if selectedPaths.contains(repository.path) { selectedPaths.remove(repository.path) }
        else { selectedPaths.insert(repository.path) }
    }

    func selectAllFastForwardCandidates() {
        selectedPaths = Set(repositories.filter(\.isFastForwardCandidate).map(\.path))
    }

    func selectFastForwardCandidates(in paths: Set<String>) {
        selectedPaths = Set(repositories.filter { paths.contains($0.path) && $0.isFastForwardCandidate }.map(\.path))
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

    func update() {
        guard canUpdate else { return }
        startUpdate(selectedRepositories, resetResults: true)
    }

    func retry(_ repository: SourceControlRepository) {
        guard repository.isFastForwardCandidate,
              !isScanning, !isUpdating, !isCheckingMerge, !isCreatingMerge else { return }
        startUpdate([repository], resetResults: false)
    }

    private func startUpdate(_ targets: [SourceControlRepository], resetResults: Bool) {
        task?.cancel()
        generation &+= 1
        let operationGeneration = generation
        isUpdating = true
        diagnostic = nil
        if resetResults { operationResults = [] }
        else { operationResults.removeAll { $0.repository.id == targets.first?.id } }
        task = Task { [weak self] in
            guard let self else { return }
            _ = await updater.update(repositories: targets) { [weak self] result in
                await self?.appendOperationResult(result, generation: operationGeneration)
            }
            guard !Task.isCancelled, generation == operationGeneration else { return }
            isUpdating = false
            scan()
        }
    }

    func cancel() {
        task?.cancel()
        generation &+= 1
        isScanning = false
        isUpdating = false
        isCheckingMerge = false
        isCreatingMerge = false
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
    @ObservedObject var workspace: SourceControlWorkspaceModel
    @State private var section = "sync"
    @State private var showsToken = false
    @State private var repositoryQuery = ""
    @State private var repositoryFilter = "all"
    @State private var showsUpdateConfirmation = false
    @State private var showsMergeConfirmation = false

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

    /// 细线进度读数：已处理的仓库数 / 所选仓库数。
    private var updateFraction: Double? {
        guard workspace.isUpdating, !workspace.selectedPaths.isEmpty else { return nil }
        return Double(min(workspace.operationResults.count, workspace.selectedPaths.count))
            / Double(workspace.selectedPaths.count)
    }

    var body: some View {
        IndexPage("源码管理", subtitle: "同步本地 Git 仓库，并创建 GitLab Merge Request。", workspaceSemantic: .queryListWorkspace) {
            IndexSegmentedControl(
                items: [("sync", "仓库同步"), ("merge", "创建 Merge Request")],
                selection: $section,
                density: .regular
            )
            if section == "sync" { syncSection } else { mergeSection }
        }
        .alert("确认更新仓库？", isPresented: $showsUpdateConfirmation) {
            Button("取消", role: .cancel) {}
            Button("确认更新") { workspace.update() }
        } message: {
            Text("将按顺序执行 git pull --ff-only。工作区有改动、没有 upstream 或无法快进的仓库会跳过。")
        }
        .alert("确认创建 Merge Request？", isPresented: $showsMergeConfirmation) {
            Button("取消", role: .cancel) {}
            Button("创建") { workspace.createMergeRequest() }
        } message: {
            Text("创建前会再次查询相同源分支和目标分支的 opened MR，避免重复请求。Token 只用于当前请求。")
        }
    }

    private var syncSection: some View {
        VStack(spacing: ToolMetrics.Spacing.md) {
            IndexPanel("同步范围") {
                VStack(alignment: .leading, spacing: 10) {
                    IndexSegmentedControl(
                        items: SourceControlWorkspaceModel.ScopeMode.allCases.map { ($0.id, $0.rawValue) },
                        selection: Binding(get: { workspace.mode.id }, set: { workspace.mode = .init(rawValue: $0) ?? .directory }),
                        density: .compact
                    )
                    .disabled(workspace.isScanning || workspace.isUpdating)
                    HStack(spacing: 8) {
                        IndexTextInput(placeholder: workspace.mode == .directory ? "选择工作区目录" : "选择仓库目录", text: Binding(get: { workspace.path }, set: workspace.setPath))
                        Button { chooseDirectory() } label: { Label("选择", systemImage: "folder") }
                            .buttonStyle(IndexSmallButtonStyle())
                    }
                    HStack(spacing: 8) {
                        Button { workspace.scan() } label: {
                            IndexProgressMotionLabel(title: workspace.isScanning ? "扫描中…" : "扫描仓库", systemImage: "arrow.clockwise", isProcessing: workspace.isScanning, id: workspace.isScanning)
                        }.buttonStyle(IndexButtonStyle())
                        if workspace.isScanning || workspace.isUpdating {
                            Button("取消") { workspace.cancel() }.buttonStyle(IndexSmallButtonStyle())
                        }
                    }
                }
            } accessory: { Text("只执行 git pull --ff-only").font(ToolTypography.caption).foregroundStyle(ToolTheme.textSecondary) }
            IndexPanel("仓库（\(workspace.repositories.count)）") {
                if workspace.repositories.isEmpty {
                    if workspace.isScanning {
                        IndexProgressLabel(message: "正在扫描工作目录…", layout: .centered)
                    } else {
                        IndexEmptyState(title: "尚未扫描仓库", systemImage: "shippingbox", message: "选择目录后开始扫描")
                    }
                } else {
                    VStack(spacing: 6) {
                        HStack {
                            IndexSearchInput(placeholder: "搜索仓库或分支", text: $repositoryQuery, height: 30)
                                .frame(maxWidth: 280)
                            IndexOptionMenu(
                                items: [("all", "全部"), ("update", "待更新"), ("latest", "已最新"), ("attention", "需处理")],
                                selection: $repositoryFilter,
                                title: "筛选"
                            )
                            Button("全选当前") {
                                workspace.selectFastForwardCandidates(in: Set(visibleRepositories.map(\.path)))
                            }.buttonStyle(IndexSmallButtonStyle())
                            Spacer()
                            Button { showsUpdateConfirmation = true } label: {
                                IndexProgressMotionLabel(title: workspace.isUpdating ? "更新中…" : "更新所选（\(workspace.selectedPaths.count)）", systemImage: "arrow.down.circle", isProcessing: workspace.isUpdating, id: workspace.isUpdating)
                            }.buttonStyle(IndexSmallButtonStyle()).disabled(!workspace.canUpdate)
                        }
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
                            Text("已处理 \(workspace.operationResults.count) / \(workspace.selectedPaths.count) 个仓库")
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
            }
            .verticallyFilling()
            .indexWorkspaceDiagnostic(workspace.diagnostic?.summary)
        }
    }

    private func repositoryRow(_ repository: SourceControlRepository) -> some View {
        let isSelected = workspace.selectedPaths.contains(repository.path)
        return HStack(spacing: 8) {
            Button { workspace.toggleSelection(repository) } label: {
                HStack(spacing: 9) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? ToolTheme.accent : ToolTheme.textTertiary)
                        .font(.system(size: ToolMetrics.IconSize.large))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(URL(fileURLWithPath: repository.path).lastPathComponent).font(ToolTypography.bodyMedium)
                        Text(repository.path).font(ToolTypography.caption).foregroundStyle(ToolTheme.textTertiary).lineLimit(1)
                        Text(repositoryDetail(repository)).font(ToolTypography.caption).foregroundStyle(ToolTheme.textSecondary)
                    }
                    Spacer()
                    IndexBadge(repositoryStatusTitle(repository), tone: repositoryStatusTone(repository))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .hoverHighlight(enabled: repository.isFastForwardCandidate)
            }
            .buttonStyle(IndexBareButtonStyle())
            .disabled(!repository.isFastForwardCandidate)
            if let result = workspace.operationResults.last(where: { $0.repository.id == repository.id }),
               case .failed = result.outcome {
                Button("重试") { workspace.retry(repository) }
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
        if let result = workspace.operationResults.last(where: { $0.repository.id == repository.id }),
           case let .failed(diagnostic) = result.outcome {
            return diagnostic.summary
        }
        let freshness = repository.behind > 0 ? "落后 \(repository.behind) 个提交" : "与远端一致"
        return "\(repository.branch) · \(repository.shortRevision) · \(freshness)"
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
                let title = workspace.mode == .directory ? "选择工作区目录" : "选择仓库目录"
                let request = FileInputPanelRequest(title: title, canChooseDirectories: true, canChooseFiles: false)
                if let url = try await fileInputPanelClient.selectFile(request) { workspace.setPath(url.path) }
            } catch {
                workspace.setPath(workspace.path)
            }
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
