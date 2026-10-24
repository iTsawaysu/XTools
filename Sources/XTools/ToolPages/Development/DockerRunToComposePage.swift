import XToolsCore
import SwiftUI
import XToolsDesign

@MainActor
final class DockerConversionToolWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<DockerConversionToolWorkspaceModel>(toolID: "docker-run-to-docker-compose-converter") { preferences in
        DockerConversionToolWorkspaceModel(preferences: preferences)
    }

    enum Direction: String, CaseIterable, Sendable {
        case runToCompose = "run-to-compose"
        case composeToRun = "compose-to-run"

        var id: String { rawValue }
        var label: String {
            switch self {
            case .runToCompose:
                return "Run → Compose"
            case .composeToRun:
                return "Compose → Run"
            }
        }
    }

    @Published var input = "" {
        didSet {
            guard !ExactUTF8Identity.isExactlyEqual(input, oldValue) else { return }
            execution.sourceDidChange()
        }
    }
    @Published var direction: Direction {
        didSet {
            guard direction != oldValue else { return }
            execution.sourceDidChange()
            preferences.set(direction.rawValue, for: TextDevelopmentToolPreferenceKeys.dockerConversionDirection)
        }
    }

    let execution = IndexFormatExecutionSession()
    private let preferences: ToolPreferenceStore

    var output: String { execution.binding.output }
    var error: String? { execution.binding.error }
    var warning: String? { execution.binding.warning }

    init(preferences: ToolPreferenceStore = ToolPreferenceStore(defaults: .standard)) {
        self.preferences = preferences
        direction = Direction(rawValue: preferences.value(for: TextDevelopmentToolPreferenceKeys.dockerConversionDirection)) ?? .runToCompose
    }

    func clear() {
        execution.invalidate()
        input = ""
    }
}

struct IndexDockerPage: View {
    var body: some View {
        ToolWorkspaceHost(key: DockerConversionToolWorkspaceModel.key) { workspace, _ in
            IndexDockerWorkspaceContent(
                workspace: workspace,
                execution: workspace.execution
            )
        }
    }
}

struct IndexDockerWorkspaceContent: View {
    nonisolated private static let maxInputCharacters = 200_000

    /// 输出 pane 标题（AX 过期态插值与 pane 头同源）。
    private let outputTitle = "输出"

    @ObservedObject var workspace: DockerConversionToolWorkspaceModel
    @ObservedObject var execution: IndexFormatExecutionSession
    /// 输入 pane 的文本文件拖入会话（旧壳能力随行）。
    @StateObject private var droppedFile = IndexDroppedTextFile()
    /// 输出呼吸代际：显式转换落地新鲜、非空、无错结果时 +1。
    @State private var outputBreathGeneration = 0

    private var diagnosticText: String? {
        execution.binding.error ?? execution.binding.warning
    }

    private var diagnosticTone: ToolFeedbackTone {
        execution.binding.error == nil ? .warning : .error
    }

    /// 旧壳 hasDiagnostic 门控：运行中/结果过期时不投递诊断。
    private var showsDiagnostic: Bool {
        !execution.isRunning && execution.isOutputFresh && diagnosticText != nil
    }

    private var hasStaleResult: Bool {
        !execution.isOutputFresh && (!execution.binding.output.isEmpty || diagnosticText != nil)
    }

    /// 旧壳 formatButton 门控：运行中或输入为空白时禁用主操作。
    private var formatEnabled: Bool {
        !execution.isRunning
            && !workspace.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        IndexPage("Docker Run ↔ Compose", subtitle: "docker run 命令与 Compose YAML 双向转换。", workspaceSemantic: .structuredEditorTransform) {
            // 统一壳装配（page-rollout B2）：方向分段（Run ↔ Compose，页面级
            // 模式分段）归标题行 accessory（Batch A 配方）；显式转换走壳级
            // primaryAction（⌘↩，旧「转换」钮等价——actionTitle 字符串反推
            // 随显式状态消灭）；诊断走 preference 单轨。
            WorkbenchSurface(
                title: nil,
                primaryAction: WorkbenchPrimaryAction(
                    title: "转换",
                    help: "转换（⌘↩）",
                    enabled: formatEnabled,
                    perform: convert
                ),
                shape: .inputOutput,
                titleAccessory: { directionSegment },
                content: {
                    WorkbenchIOPair(
                        leadingTitle: "输入",
                        trailingTitle: outputTitle,
                        leadingActions: [
                            .clear(
                                enabled: !(workspace.input.isEmpty && !execution.hasClearableContent),
                                onPerform: workspace.clear
                            )
                        ],
                        trailingActions: [
                            .copy(text: execution.binding.output, help: "复制全部 (⇧⌘C)", enabled: execution.isOutputFresh)
                        ],
                        leadingAccessory: { stdinBadge },
                        leading: { inputPane },
                        trailingAccessory: { stdoutCluster },
                        trailing: { outputPane }
                    )
                    // 诊断单轨：拖入拒判优先，其后是错误/警告；诊断详情随
                    // 载荷透传给纸顶 banner（Docker 无源标记，「定位」缺席，
                    // 与旧壳 onLocate 为 nil 一致）。
                    .indexWorkspaceDiagnostic(
                        droppedFile.rejection?.message ?? (showsDiagnostic ? diagnosticText : nil),
                        tone: droppedFile.rejection == nil ? diagnosticTone : .error,
                        detail: droppedFile.rejection == nil && showsDiagnostic ? execution.diagnostic : nil
                    )
                }
            )
        }
        .onChange(of: execution.isOutputFresh) {
            guard execution.isOutputFresh, !execution.binding.output.isEmpty, execution.binding.error == nil else {
                return
            }
            outputBreathGeneration += 1
        }
    }

    // MARK: - 标题行 accessory

    /// 方向分段：切换即写偏好，已有输出时按旧页语义立即重转。
    private var directionSegment: some View {
        IndexSegmentedControl(
            items: DockerConversionToolWorkspaceModel.Direction.allCases.map { ($0.id, $0.label) },
            selection: Binding(
                get: { workspace.direction.id },
                set: { raw in
                    guard let direction = DockerConversionToolWorkspaceModel.Direction(rawValue: raw) else { return }
                    workspace.direction = direction
                    if !execution.binding.output.isEmpty {
                        convert()
                    }
                }
            ),
            density: .compact
        )
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - 内容区 pane

    private var stdinBadge: some View {
        IndexBadge("STDIN", tone: .neutral, isCapsule: true)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var stdoutCluster: some View {
        HStack(spacing: ToolMetrics.Spacing.fine) {
            IndexBadge("STDOUT", tone: .neutral, isCapsule: true)
                .fixedSize(horizontal: true, vertical: false)
            outputStatus
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var outputStatus: some View {
        if execution.isRunning {
            IndexInlineDiagnosticStatus(message: "正在转换…", showsSpinner: true)
        } else if hasStaleResult {
            IndexInlineDiagnosticStatus(message: "输入已更改，请重新转换。")
        }
    }

    private var inputPane: some View {
        IndexWorkspaceTextArea(
            placeholder: inputPlaceholder,
            text: $workspace.input,
            fillsHeight: true,
            autoFocus: true,
            embedsFlat: true,
            lineNumbers: true,
            onFileDrop: { content in
                workspace.input = content
                convert()
            },
            droppedFile: droppedFile,
            workspaceSemantic: .structuredEditorTransform
        )
        .workbenchInputDropSupport(text: $workspace.input, droppedFile: droppedFile)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityLabel("输入")
        // 焦点契约（阶段③ C3）：页面首个输入 = 输入编辑器。
        .workbenchFocusTarget()
    }

    private var outputPane: some View {
        IndexOutputSurface(
            text: execution.binding.output,
            lineNumbers: true,
            syntax: workspace.direction == .runToCompose ? .yaml : nil,
            fillsHeight: true,
            embedsFlat: true
        )
        .toolOutputBreath(generation: outputBreathGeneration)
        .accessibilityLabel(hasStaleResult ? "\(outputTitle)，结果已过期" : outputTitle)
    }

    private var inputPlaceholder: String {
        switch workspace.direction {
        case .runToCompose:
            return "docker run -d -p 8080:80 -e ENV=prod --name web nginx:latest"
        case .composeToRun:
            return "services:\n  web:\n    image: nginx:latest\n    ports:\n      - 8080:80"
        }
    }

    private func convert() {
        guard !workspace.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            execution.invalidate()
            return
        }

        let snapshot = Snapshot(input: workspace.input, direction: workspace.direction)
        execution.schedule(snapshot: snapshot, delay: .zero) { snapshot in
            Self.binding(for: snapshot)
        }
    }

    struct Snapshot: Sendable {
        let input: String
        let direction: DockerConversionToolWorkspaceModel.Direction
    }

    nonisolated static func binding(for snapshot: Snapshot) -> FormatBinding {
        let trimmed = snapshot.input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return FormatBinding()
        }

        guard trimmed.count <= maxInputCharacters else {
            return FormatBinding(
                error: DockerRunToDockerComposeDiagnostics.inputTooLongMessage(
                    maxCharacters: maxInputCharacters
                )
            )
        }

        switch snapshot.direction {
        case .runToCompose:
            return runToComposeBinding(trimmed)
        case .composeToRun:
            return composeToRunBinding(trimmed)
        }
    }

    nonisolated private static func runToComposeBinding(_ input: String) -> FormatBinding {
        do {
            let result = try DockerRunToDockerComposeService.convert(input)
            let warningText = DockerRunToDockerComposeDiagnostics.warningMessage(for: result.warnings)
            let errorText = result.yaml.isEmpty
                ? DockerRunToDockerComposeDiagnostics.emptyOutputMessage
                : nil
            let diagnostic: FormatDiagnostic?
            if let errorText {
                diagnostic = FormatDiagnostic(
                    formatName: "Docker 转换",
                    message: errorText,
                    suggestion: "检查命令是否包含有效的容器参数和镜像名称。"
                )
            } else if let warningText {
                diagnostic = FormatDiagnostic(
                    formatName: "Docker 转换",
                    message: warningText,
                    suggestion: "部分命令行参数未能转换，请检查原命令与生成的 Compose 配置。",
                    details: DockerRunToDockerComposeDiagnostics.warningDetails(for: result.warnings)
                )
            } else {
                diagnostic = nil
            }
            return FormatBinding(
                output: result.yaml,
                error: errorText,
                warning: warningText,
                diagnostic: diagnostic
            )
        } catch let error as DockerRunToDockerComposeError {
            let msg = error.errorDescription ?? "无法转换 docker run 命令。"
            let suggestion: String
            if case .unresolvedShellExpression = error {
                suggestion = "使用明确的参数值；字面美元可用单引号或反斜杠保护，转换器不会执行 Shell。"
            } else {
                suggestion = "确认输入以 docker run 开头，且镜像名与参数格式正确。"
            }
            let diagnostic = FormatDiagnostic(
                formatName: "Docker 转换",
                message: msg,
                suggestion: suggestion
            )
            return FormatBinding(error: msg, diagnostic: diagnostic)
        } catch {
            let msg = DockerRunToDockerComposeDiagnostics.fallbackErrorMessage
            let diagnostic = FormatDiagnostic(
                formatName: "Docker 转换",
                message: msg,
                suggestion: "检查命令格式，必须以 docker run 开头并指定镜像。"
            )
            return FormatBinding(error: msg, diagnostic: diagnostic)
        }
    }

    nonisolated private static func composeToRunBinding(_ input: String) -> FormatBinding {
        do {
            let result = try DockerComposeToRunService.convert(input)
            let body = result.commands
                .map { "# 服务命令\n\($0)" }
                .joined(separator: "\n\n")
            let warningText = DockerComposeToRunDiagnostics.warningMessage(for: result.warnings)
            let diagnostic: FormatDiagnostic?
            if let warningText {
                diagnostic = FormatDiagnostic(
                    formatName: "Compose 转换",
                    message: warningText,
                    suggestion: "部分 Compose 声明在单一 docker run 中无法直接表达，请在命令生成后检查网络与存储卷配置。",
                    details: result.warningDetails
                )
            } else {
                diagnostic = nil
            }
            return FormatBinding(
                output: body,
                error: nil,
                warning: warningText,
                diagnostic: diagnostic
            )
        } catch let error as DockerComposeToRunError {
            // 细化诊断优先：invalidYAML 现在携带行列与针对性建议。
            let diagnostic = DockerComposeToRunDiagnostics.diagnostic(for: error)
            return FormatBinding(error: diagnostic.workspaceMessage, diagnostic: diagnostic)
        } catch let error as any FormatDiagnosticProviding {
            let diagnostic = error.diagnostic
            return FormatBinding(error: diagnostic.workspaceMessage, diagnostic: diagnostic)
        } catch {
            let msg = "docker-compose YAML 格式无效。"
            let diagnostic = FormatDiagnostic(
                formatName: "Compose 转换",
                message: msg,
                suggestion: "确认输入符合标准 Docker Compose YAML 语法规范。"
            )
            return FormatBinding(error: msg, diagnostic: diagnostic)
        }
    }
}
