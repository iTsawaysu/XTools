import SwiftUI
import XToolsCore
import XToolsDesign

@MainActor
final class RegexToolWorkspaceModel: ObservableObject, ToolWorkspacePayloadEvicting {
    static let key = ToolWorkspaceKey<RegexToolWorkspaceModel>(toolID: "regex-tester") { _ in
        RegexToolWorkspaceModel()
    }

    @Published var pattern = ""
    @Published var flags = "g"
    @Published var text = ""
    let debouncer = IndexDebouncer()
    let execution = RegexExecutionSession()

    var hasAnyContent: Bool {
        !pattern.isEmpty
            || flags != "g"
            || !text.isEmpty
            || execution.report != nil
            || execution.error != nil
            || execution.isRunning
    }

    var activePreset: RegexMatcher.Preset? {
        let normalizedFlags = RegexMatcher.normalizeFlagsForUI(flags)
        return RegexMatcher.presets.first {
            $0.pattern == pattern && RegexMatcher.normalizeFlagsForUI($0.flags) == normalizedFlags
        }
    }

    func applyPreset(_ preset: RegexMatcher.Preset) {
        debouncer.cancel()
        execution.invalidate()
        pattern = preset.pattern
        flags = RegexMatcher.normalizeFlagsForUI(preset.flags)
        text = preset.exampleText
    }

    func clear() {
        debouncer.cancel()
        execution.invalidate()
        pattern = ""
        flags = "g"
        text = ""
    }

    /// 离开工具时释放匹配报告（可达 10k 匹配 + 捕获记录）与挂起的防抖执行；
    /// pattern/flags/text 草稿保留，回到工具后下一次编辑照常重跑。
    func evictHeavyPayloads() {
        debouncer.cancel()
        execution.invalidate()
    }
}

struct RegexWorkspaceInput: Equatable {
    let pattern: String
    let flags: String
    let text: String

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.flags == rhs.flags
            && ExactUTF8Identity.isExactlyEqual(lhs.pattern, rhs.pattern)
            && ExactUTF8Identity.isExactlyEqual(lhs.text, rhs.text)
    }

    init(pattern: String, flags: String, text: String) {
        self.pattern = pattern
        self.flags = flags
        self.text = text
    }

    @MainActor
    init(workspace: RegexToolWorkspaceModel) {
        self.init(pattern: workspace.pattern, flags: workspace.flags, text: workspace.text)
    }

    init(preset: RegexMatcher.Preset) {
        self.init(
            pattern: preset.pattern,
            flags: RegexMatcher.normalizeFlagsForUI(preset.flags),
            text: preset.exampleText
        )
    }
}

private enum RegexResultMotionIntent: Equatable {
    case preset(RegexWorkspaceInput)
    case clear
    case immediate
}

struct IndexRegexPage: View {
    var body: some View {
        ToolWorkspaceHost(key: RegexToolWorkspaceModel.key) { workspace, _ in
            IndexRegexWorkspaceContent(
                workspace: workspace,
                execution: workspace.execution
            )
        }
    }
}

private struct IndexRegexWorkspaceContent: View {
    @ObservedObject var workspace: RegexToolWorkspaceModel
    @ObservedObject var execution: RegexExecutionSession

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedReport: RegexMatcher.Report?
    @State private var resultMotionIntent = RegexResultMotionIntent.immediate
    /// 正文里被定位的匹配（0 起）；再次点击同一行取消。
    @State private var selectedMatchIndex: Int?
    @State private var scrollRequest: IndexTextAreaScrollRequest?
    @State private var scrollRequestToken = 0

    /// 预设菜单的「自定义」哨兵：当前表达式不等于任何预设时的选中项。
    /// 自定义是派生态（只能经编辑进入），选择它不做任何事。
    private static let customPresetItemID = "custom"

    var body: some View {
        IndexPage(
            "正则测试",
            subtitle: "使用 ICU 引擎实时测试正则并高亮匹配。",
            workspaceSemantic: .regexResultWorkspace
        ) {
            // 统一壳（unified-workbench D1）：表达式/预设/标志开关收纳进弹性
            // 参数区（默认全展开、随窗宽换行，无横向滚动、无折叠后门）；
            // 内容区为「测试文本 → 匹配结果」对等双栏（regex101 式宽分窄堆，
            // 720pt 等宽分栏数学与旧 pair 契约一致）；语法错误仍收纸顶单槽。
            WorkbenchSurface(title: nil, shape: .inputOutput, parameters: { parameterFlow }) {
                WorkbenchIOPair(
                    leadingTitle: "测试文本",
                    trailingTitle: "匹配结果",
                    splitPolicy: .default,
                    leadingActions: [
                        .clear(
                            title: "清空工作区",
                            enabled: workspace.hasAnyContent,
                            onPerform: clearWorkspace
                        )
                    ],
                    trailingActions: [
                        .copy(text: resultText, title: "复制匹配结果")
                    ],
                    trailingFooter: IndexWorkbenchFooter(
                        status: resultStatus.text,
                        statusTone: toneColor(resultStatus.tone),
                        trailingText: summaryText
                    ),
                    leading: { textEditor },
                    trailing: { matchList }
                )
                // 诊断单轨发布：正则语法错误经 preference 聚合到纸顶单槽
                //（与旧壳参数轨同一文本、同一播报门控、同一错误描边）。
                .indexWorkspaceDiagnostic(error)
            }
        }
        .onAppear {
            displayedReport = report
        }
        .onChange(of: workspaceInput) {
            handleWorkspaceInputChange(workspaceInput)
        }
        .onChange(of: execution.report) {
            present(execution.report)
        }
    }

    // MARK: - 弹性参数区（unified-workbench D1）

    /// 参数区：正则独占一行（长表达式可得全带宽，超长部分在字段内部滚动）；
    /// 预设菜单与五个标志开关进流式组，随窗宽换行。全部参数一次铺开、
    /// 默认无折叠（design.md §10：RegexTester 参数默认展开全部）。
    private var parameterFlow: some View {
        WorkbenchParameterFlow {
            WorkbenchParameterItem("正则表达式") {
                patternField
            }
            WorkbenchParameterGroup {
                WorkbenchParameterItem("预设") {
                    presetMenu
                }
                WorkbenchParameterItem {
                    IndexOptionSwitch(title: "全局匹配 (g)", isOn: flagBinding("g"))
                }
                WorkbenchParameterItem {
                    IndexOptionSwitch(title: "忽略大小写 (i)", isOn: flagBinding("i"))
                }
                WorkbenchParameterItem {
                    IndexOptionSwitch(title: "多行模式 (m)", isOn: flagBinding("m"))
                }
                WorkbenchParameterItem {
                    IndexOptionSwitch(title: "点号匹配换行 (s)", isOn: flagBinding("s"))
                }
                WorkbenchParameterItem {
                    IndexOptionSwitch(title: "允许注释与空白 (x)", isOn: flagBinding("x"))
                }
            }
        }
    }

    /// 正则字段：保留旧页 "/…/" 字面量记法；占满参数行余宽（IndexTextInput
    /// 自身贪婪扩展，放在流式组外由 VStack 提出有界宽度）。
    private var patternField: some View {
        HStack(spacing: ToolMetrics.Spacing.fine) {
            Text("/")
                .font(ToolTypography.body)
                .foregroundStyle(ToolTheme.textSecondary)

            IndexTextInput(
                placeholder: #"\b\w+@\w+\.\w+\b"#,
                text: $workspace.pattern,
                height: ToolMetrics.Control.row
            )
            // 焦点契约（阶段③ C3）：页面首个输入 = 参数区的表达式字段。
            .workbenchFocusTarget()

            Text("/")
                .font(ToolTypography.body)
                .foregroundStyle(ToolTheme.textSecondary)
        }
    }

    /// 预设菜单（旧手写原生 Menu → IndexOptionMenu）：选中项即当前生效
    /// 预设；表达式被改动后自动回到「自定义」。挑同一项（含「自定义」）
    /// 不触发任何变更。
    private var presetMenu: some View {
        IndexOptionMenu(
            items: presetItems,
            selection: presetSelection,
            title: "预设"
        )
    }

    private var presetItems: [(String, String)] {
        [(Self.customPresetItemID, "自定义")]
            + RegexMatcher.presets.map { ($0.id, $0.title) }
    }

    private var presetSelection: Binding<String> {
        Binding(
            get: { workspace.activePreset?.id ?? Self.customPresetItemID },
            set: { selected in
                guard selected != Self.customPresetItemID,
                      let preset = RegexMatcher.presets.first(where: { $0.id == selected })
                else { return }
                applyPreset(preset)
            }
        )
    }

    // MARK: - 内容区 pane

    /// 测试文本 pane：受控 AppKit 编辑器 + 正文高亮（整匹配铺底色、被选中
    /// 的匹配加强底色并加下划线、捕获组按组序循环取色）与一次性滚动定位
    /// 请求，全部保持旧页路径。
    private var textEditor: some View {
        IndexWorkspaceTextArea(
            placeholder: "粘贴待匹配文本…",
            text: $workspace.text,
            minHeight: 56,
            fillsHeight: true,
            temporaryHighlights: temporaryHighlights,
            scrollRequest: scrollRequest,
            workspaceSemantic: .regexResultWorkspace
        )
    }

    /// 匹配结果 pane：有匹配才渲染列表；点击行在正文中定位（再次点击取消）。
    /// 状态与统计由 pane footer 播报；预设/清空的低频动效分支
    /// （resultPresence*，输入中的 .identity 即时分支）保持原语义。
    @ViewBuilder
    private var matchList: some View {
        if let report = presentedReport, !report.matches.isEmpty {
            ScrollView {
                RegexMatchList(
                    matches: report.matches,
                    valueMotion: .immediate,
                    selectedIndex: selectedMatchIndex,
                    onSelect: selectMatch
                )
                .toolTransition(resultTransition, reduceMotion: reduceMotion)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// 正文高亮：整匹配铺底色，被选中的匹配加强底色并加下划线；
    /// 捕获组按组序在调色板中循环取色（与匹配列表前景同色）。
    private var temporaryHighlights: IndexTextAreaTemporaryHighlights? {
        guard let report,
              let sourceText = execution.reportSourceText else {
            return nil
        }

        return RegexHighlightProjection.make(
            report: report,
            sourceText: sourceText,
            selectedMatchIndex: selectedMatchIndex
        )
    }

    private var resultStatus: (text: String, tone: IndexBadgeTone) {
        guard !workspace.pattern.isEmpty else {
            return ("输入正则表达式后显示匹配。", .neutral)
        }

        if error != nil {
            return ("请修正上方正则表达式。", .error)
        }

        guard let report else {
            return ("正在更新匹配…", .neutral)
        }

        guard !report.matches.isEmpty else {
            return ("未找到匹配。", .neutral)
        }

        let highlightedCount = report.matches.count { ($0.utf16Range?.length ?? ($0.end - $0.index)) > 0 }
        if highlightedCount == report.matches.count {
            return ("已高亮 \(highlightedCount) 个匹配。", .success)
        }
        if highlightedCount == 0 {
            return ("找到 \(report.matches.count) 个零长度匹配；详情见下方。", .neutral)
        }
        return ("找到 \(report.matches.count) 个匹配，其中 \(highlightedCount) 个已高亮。", .success)
    }

    private func toneColor(_ tone: IndexBadgeTone) -> Color? {
        switch tone {
        case .neutral:
            return nil
        case .success:
            return ToolTheme.success
        case .warning:
            return ToolTheme.warning
        case .error:
            return ToolTheme.error
        case .accent:
            return ToolTheme.accent
        }
    }

    /// 非零统计压进 pane 脚尾部；状态行占脚部首位（窄窗单行截断）。
    private var summaryText: String {
        guard let report = presentedReport else { return "" }
        return stats(for: report).map { "\($0.0) \($0.1)" }.joined(separator: " · ")
    }

    private var workspaceInput: RegexWorkspaceInput {
        RegexWorkspaceInput(workspace: workspace)
    }

    private func handleWorkspaceInputChange(_ input: RegexWorkspaceInput) {
        switch resultMotionIntent {
        case .preset(let target) where target == input:
            break
        case .clear where input == RegexWorkspaceInput(pattern: "", flags: "g", text: ""):
            break
        default:
            resultMotionIntent = .immediate
        }
        schedule(input)
    }

    private func schedule(_ input: RegexWorkspaceInput) {
        execution.invalidate()
        guard !workspace.pattern.isEmpty else {
            workspace.debouncer.cancel()
            return
        }

        let patternSnapshot = input.pattern
        let textSnapshot = input.text
        let flagsSnapshot = input.flags
        workspace.debouncer.schedule {
            execution.run(pattern: patternSnapshot, text: textSnapshot, flags: flagsSnapshot)
        }
    }

    private func applyPreset(_ preset: RegexMatcher.Preset) {
        let previousInput = workspaceInput
        let targetInput = RegexWorkspaceInput(preset: preset)
        resultMotionIntent = .preset(targetInput)
        withToolAnimation(ToolMotion.Preset.resultPresenceExit, reduceMotion: reduceMotion) {
            workspace.applyPreset(preset)
        }
        if previousInput == targetInput {
            schedule(targetInput)
        }
    }

    private func clearWorkspace() {
        resultMotionIntent = .clear
        withToolAnimation(ToolMotion.Preset.resultPresenceExit, reduceMotion: reduceMotion) {
            workspace.clear()
        }
    }

    /// 点击匹配行：在正文中定位该匹配（再次点击取消）。滚动经一次性
    /// token 请求下发给 AppKit 文本视图，避免在 onChange 里持续滚动。
    private func selectMatch(_ index: Int) {
        guard let report,
              report.matches.indices.contains(index) else {
            return
        }

        if selectedMatchIndex == index {
            selectedMatchIndex = nil
            return
        }

        selectedMatchIndex = index
        let match = report.matches[index]
        let range = RegexHighlightProjection.range(
            exact: match.utf16Range,
            start: match.index,
            end: match.end,
            in: execution.reportSourceText ?? ""
        )
        guard let range, range.length > 0 else { return }
        scrollRequestToken &+= 1
        scrollRequest = IndexTextAreaScrollRequest(token: scrollRequestToken, utf16Range: range)
    }

    private func present(_ candidate: RegexMatcher.Report?) {
        selectedMatchIndex = nil
        guard let candidate,
              candidate == report else {
            switch resultMotionIntent {
            case .preset, .clear:
                withToolAnimation(ToolMotion.Preset.resultPresenceExit, reduceMotion: reduceMotion) {
                    displayedReport = nil
                }
            case .immediate:
                displayedReport = nil
            }
            return
        }

        switch resultMotionIntent {
        case .preset(let target) where target == workspaceInput:
            withToolAnimation(ToolMotion.Preset.resultPresenceAppearance, reduceMotion: reduceMotion) {
                displayedReport = candidate
            }
        case .clear, .preset, .immediate:
            displayedReport = candidate
        }
    }

    /// 输入中的高频更新走 .identity（无过渡直切）；只有预设/清空这类
    /// 低频意图才挂 modeContent 过渡——高频路径不加结果动效（spec 合同）。
    private var resultTransition: AnyTransition {
        switch resultMotionIntent {
        case .preset, .clear:
            ToolMotion.Transition.modeContent
        case .immediate:
            .identity
        }
    }

    private func flagBinding(_ flag: Character) -> Binding<Bool> {
        Binding(
            get: { workspace.flags.contains(flag) },
            set: { isOn in
                setFlag(flag, enabled: isOn)
            }
        )
    }

    private func setFlag(_ flag: Character, enabled: Bool) {
        var orderedFlags = workspace.flags.filter { !$0.isWhitespace && $0 != flag }
        if enabled {
            orderedFlags.append(flag)
        }
        workspace.flags = normalizeFlagOrder(String(orderedFlags))
    }

    private func normalizeFlagOrder(_ value: String) -> String {
        RegexMatcher.normalizeFlagsForUI(value)
    }

    private func stats(for report: RegexMatcher.Report) -> [(String, String)] {
        // 匹配数已由状态行播报，这里只保留非零的捕获/命名组/覆盖字符，
        // 避免零值统计在结果区占位。
        var entries: [(String, String)] = []
        if report.statistics.captureCount > 0 {
            entries.append(("捕获", "\(report.statistics.captureCount)"))
        }
        if report.statistics.namedGroupCount > 0 {
            entries.append(("命名组", "\(report.statistics.namedGroupCount)"))
        }
        if report.statistics.matchedCharacterCount > 0 {
            entries.append(("字符", "\(report.statistics.matchedCharacterCount)"))
        }
        return entries
    }

    private var presentedReport: RegexMatcher.Report? {
        guard let displayedReport,
              displayedReport == report else {
            return nil
        }
        return displayedReport
    }

    private var resultText: String {
        guard let report else { return "" }
        return RegexMatcher.summaryText(for: report)
    }

    private var report: RegexMatcher.Report? {
        guard let report = execution.report,
              let sourceText = execution.reportSourceText,
              ExactUTF8Identity.isExactlyEqual(sourceText, workspace.text),
              ExactUTF8Identity.isExactlyEqual(report.pattern, workspace.pattern),
              report.flags == workspace.flags else {
            return nil
        }
        return report
    }

    private var error: String? {
        execution.error
    }
}

/// Keep each capture's group identity beside its exact native range. Nested
/// captures may overlap; filtering ranges must never shift the palette index.
enum RegexHighlightProjection {
    static func make(
        report: RegexMatcher.Report,
        sourceText: String,
        selectedMatchIndex: Int?
    ) -> IndexTextAreaTemporaryHighlights {
        var styled: [IndexTextAreaStyledRange] = []
        for (index, match) in report.matches.enumerated() {
            if let range = range(exact: match.utf16Range, start: match.index, end: match.end, in: sourceText) {
                styled.append(.init(range: range, style: index == selectedMatchIndex ? .activeMatch : .match))
            }
        }
        for match in report.matches {
            for (groupIndex, capture) in match.captures.enumerated() {
                if let range = range(exact: capture.utf16Range, start: capture.start, end: capture.end, in: sourceText) {
                    styled.append(.init(range: range, style: .capture(groupIndex)))
                }
            }
        }
        return IndexTextAreaTemporaryHighlights(sourceText: sourceText, styledRanges: styled)
    }

    static func range(exact: NSRange?, start: Int, end: Int, in text: String) -> NSRange? {
        if let exact {
            return exact.location != NSNotFound && exact.length > 0 ? exact : nil
        }
        // Compatibility for reports built manually before exact ranges existed.
        return IndexTextAreaCharacterRangeProjection.utf16Ranges(
            in: text,
            characterRanges: [.init(start: start, end: end)]
        ).first
    }
}
