import SwiftUI
import XToolsCore

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

private struct RegexWorkspaceInput: Equatable {
    let pattern: String
    let flags: String
    let text: String

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

    var body: some View {
        IndexPage(
            "正则测试",
            subtitle: "使用 ICU 引擎实时测试正则并高亮匹配。",
            workspaceSemantic: .regexResultWorkspace
        ) {
            // 宽窗左右分栏（regex101 式）：左 = 表达式 + 匹配详情，右 = 测试文本。
            // 窄窗上下堆叠，结果列表与文本各自内部滚动。
            IndexPairLayout(collapseWidth: 720, fillsHeight: true, leading: {
                IndexPanel(
                    "正则表达式",
                    content: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Text("/")
                                    .font(ToolTypography.body)
                                    .foregroundStyle(ToolTheme.textSecondary)

                                IndexTextInput(
                                    placeholder: #"\b\w+@\w+\.\w+\b"#,
                                    text: $workspace.pattern
                                )

                                Text("/")
                                    .font(ToolTypography.body)
                                    .foregroundStyle(ToolTheme.textSecondary)

                                flagMenu
                            }
                            .indexWorkspaceDiagnostic(error)

                            // 状态与统计同行呈现（窄窗自动换行），统计不再占据独立盒面。
                            ViewThatFits(in: .horizontal) {
                                HStack(alignment: .firstTextBaseline, spacing: 16) {
                                    RegexResultStatus(text: resultStatus.text, tone: resultStatus.tone)

                                    if let report = presentedReport {
                                        Spacer(minLength: 16)
                                        RegexResultSummary(stats: stats(for: report))
                                    }
                                }

                                VStack(alignment: .leading, spacing: 10) {
                                    RegexResultStatus(text: resultStatus.text, tone: resultStatus.tone)

                                    if let report = presentedReport {
                                        RegexResultSummary(stats: stats(for: report))
                                    }
                                }
                            }

                            if let report = presentedReport {
                                if !report.matches.isEmpty {
                                    ScrollView {
                                        RegexMatchList(matches: report.matches, valueMotion: .immediate, selectedIndex: selectedMatchIndex, onSelect: selectMatch)
                                            .toolTransition(resultTransition, reduceMotion: reduceMotion)
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                }
                            }
                        }
                    },
                    accessory: {
                        HStack(spacing: 8) {
                            Menu {
                                ForEach(RegexMatcher.presets) { preset in
                                    Button(preset.title) {
                                        applyPreset(preset)
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "text.badge.checkmark")
                                        .accessibilityHidden(true)

                                    Text(activePresetTitle)
                                        .toolMotionTextSwap(id: activePresetTitle)

                                    Image(systemName: "chevron.down")
                                        .font(.system(size: ToolMetrics.IconSize.micro, weight: .semibold))
                                        .foregroundStyle(ToolTheme.textSecondary)
                                        .accessibilityHidden(true)
                                }
                                .font(ToolTypography.buttonSmall)
                            }
                            .menuIndicator(.hidden)
                            .buttonStyle(IndexSmallButtonStyle())
                            .fixedSize(horizontal: true, vertical: false)
                            .accessibilityLabel("正则预设，当前为\(activePresetTitle == "预设" ? "自定义" : activePresetTitle)")

                            IndexClearButton(
                                isDisabled: !workspace.hasAnyContent,
                                title: "清空工作区",
                                action: clearWorkspace
                            )
                        }
                    }
                )
                .verticallyFilling()
            }, trailing: {
                IndexPanel(
                    "测试文本",
                    content: {
                        IndexWorkspaceTextArea(
                            placeholder: "粘贴待匹配文本…",
                            text: $workspace.text,
                            minHeight: 56,
                            fillsHeight: true,
                            temporaryHighlights: temporaryHighlights,
                            scrollRequest: scrollRequest,
                            workspaceSemantic: .regexResultWorkspace
                        )
                    },
                    accessory: {
                        IndexCopyButton(text: resultText, title: "复制匹配结果")
                    }
                )
                .verticallyFilling()
            })
        }
        .onAppear {
            displayedReport = report
        }
        .onChange(of: workspaceInput) { input in
            handleWorkspaceInputChange(input)
        }
        .onChange(of: execution.report) { report in
            present(report)
        }
    }

    /// 正文高亮：整匹配铺底色，被选中的匹配加强底色并加下划线；
    /// 捕获组按组序在调色板中循环取色（与匹配列表前景同色）。
    private var temporaryHighlights: IndexTextAreaTemporaryHighlights? {
        guard let report,
              let sourceText = execution.reportSourceText else {
            return nil
        }

        // 零长度区间无可绘制范围，先过滤，保证投影结果与输入一一配对。
        var matchPairs: [(index: Int, range: IndexTextAreaCharacterRange)] = []
        for (index, match) in report.matches.enumerated() where match.end > match.index {
            matchPairs.append((index, IndexTextAreaCharacterRange(start: match.index, end: match.end)))
        }
        let matchUtf16Ranges = IndexTextAreaCharacterRangeProjection.utf16Ranges(
            in: sourceText,
            characterRanges: matchPairs.map(\.range)
        )

        var styled: [IndexTextAreaStyledRange] = []
        for (pair, range) in zip(matchPairs, matchUtf16Ranges) {
            let style: IndexTextAreaHighlightStyle = pair.index == selectedMatchIndex
                ? .activeMatch
                : .match
            styled.append(IndexTextAreaStyledRange(range: range, style: style))
        }

        var capturePairs: [(index: Int, range: IndexTextAreaCharacterRange)] = []
        for match in report.matches {
            for (groupIndex, capture) in match.captures.enumerated() where capture.end > capture.start {
                capturePairs.append((groupIndex, IndexTextAreaCharacterRange(start: capture.start, end: capture.end)))
            }
        }
        // 投影要求区间单调推进；嵌套组按「起点早者优先、外层先于内层」排序。
        capturePairs.sort {
            $0.range.start == $1.range.start
                ? $0.range.end > $1.range.end
                : $0.range.start < $1.range.start
        }
        let captureUtf16Ranges = IndexTextAreaCharacterRangeProjection.utf16Ranges(
            in: sourceText,
            characterRanges: capturePairs.map(\.range)
        )
        for (pair, range) in zip(capturePairs, captureUtf16Ranges) {
            styled.append(IndexTextAreaStyledRange(range: range, style: .capture(pair.index)))
        }

        return IndexTextAreaTemporaryHighlights(sourceText: sourceText, styledRanges: styled)
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

        let highlightedCount = report.matches.count { $0.end > $0.index }
        if highlightedCount == report.matches.count {
            return ("已高亮 \(highlightedCount) 个匹配。", .success)
        }
        if highlightedCount == 0 {
            return ("找到 \(report.matches.count) 个零长度匹配；详情见下方。", .neutral)
        }
        return ("找到 \(report.matches.count) 个匹配，其中 \(highlightedCount) 个已高亮。", .success)
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
        guard match.end > match.index else { return }
        let range = IndexTextAreaCharacterRangeProjection.utf16Ranges(
            in: execution.reportSourceText ?? "",
            characterRanges: [IndexTextAreaCharacterRange(start: match.index, end: match.end)]
        ).first
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

    private var resultTransition: AnyTransition {
        switch resultMotionIntent {
        case .preset, .clear:
            ToolMotion.Transition.modeContent
        case .immediate:
            .identity
        }
    }

    private var activePresetTitle: String {
        workspace.activePreset?.title ?? "预设"
    }

    private var flagMenu: some View {
        Menu {
            Toggle("全局匹配 (g)", isOn: flagBinding("g"))
            Toggle("忽略大小写 (i)", isOn: flagBinding("i"))
            Toggle("多行模式 (m)", isOn: flagBinding("m"))
            Toggle("点号匹配换行 (s)", isOn: flagBinding("s"))
            Toggle("允许注释与空白 (x)", isOn: flagBinding("x"))
        } label: {
            HStack(spacing: 5) {
                Text(activeFlagsLabel)
                    .font(ToolTypography.monoLabel)
                    .foregroundStyle(ToolTheme.textPrimary)

                Image(systemName: "chevron.down")
                    .font(.system(size: ToolMetrics.IconSize.micro, weight: .semibold))
                    .foregroundStyle(ToolTheme.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .menuIndicator(.hidden)
        .buttonStyle(IndexSmallButtonStyle())
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("正则标志，当前为 \(activeFlagsLabel)")
    }

    private var activeFlagsLabel: String {
        workspace.flags.isEmpty ? "无" : workspace.flags
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
              sourceText == workspace.text,
              report.pattern == workspace.pattern,
              report.flags == workspace.flags else {
            return nil
        }
        return report
    }

    private var error: String? {
        execution.error
    }
}
