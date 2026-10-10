import AppKit
import SwiftUI
import XToolsCore

/// A toolbar/keyboard request to jump to the previous or next difference.
struct DiffDifferenceNavigationRequest: Equatable {
    let id: Int
    let forward: Bool
}

struct DiffDifferenceNavigationProgress: Equatable, Sendable {
    let current: Int?
    let total: Int
}

struct IndexEditableDiffWorkspace<LeadingControl: View>: View {
    var inputTitle: String = "原始文本"
    var outputTitle: String = "对比文本"
    let leftPlaceholder: String
    let rightPlaceholder: String
    var leftDisplayText: String?
    var rightDisplayText: String?
    @Binding var left: String
    @Binding var right: String
    let rows: [DiffAlignedRow]
    var resultState: DiffExecutionResultState = .current
    var syntax: IndexDiffSyntax = .plain
    /// Enables the view-mode fold projection over unchanged regions. The
    /// binding keeps full canonical text; collapsed regions render as
    /// click-to-expand placeholder rows and panes turn read-only while any
    /// region stays collapsed.
    var foldUnchanged: Bool = false
    var error: String?
    var warning: String?
    var onClear: (() -> Void)? = nil
    var clearDisabled = false
    var leadingControl: () -> LeadingControl

    @State private var droppedFileDiagnostic: String?
    @State private var navigationRequest: DiffDifferenceNavigationRequest?
    @State private var navigationProgress = DiffDifferenceNavigationProgress(current: nil, total: 0)

    /// 一次共享的全文扫描结论：诊断文案、语气、差异导航与空态判断都读取
    /// 这份缓存。它是存储属性：每次视图值重建（即每次父级 body 求值）只
    /// 计算一次；两侧「非空」结论同时被 diagnosticText 复用，body 期不再
    /// 做任何 O(n) 全文扫描。
    struct DiffSummary {
        let leftNonEmpty: Bool
        let rightNonEmpty: Bool
        let isIdentical: Bool
        let differenceBlockCount: Int
    }

    let diffSummary: DiffSummary

    init(
        inputTitle: String = "原始文本",
        outputTitle: String = "对比文本",
        leftPlaceholder: String,
        rightPlaceholder: String,
        leftDisplayText: String? = nil,
        rightDisplayText: String? = nil,
        left: Binding<String>,
        right: Binding<String>,
        rows: [DiffAlignedRow],
        resultState: DiffExecutionResultState = .current,
        syntax: IndexDiffSyntax = .plain,
        foldUnchanged: Bool = false,
        error: String? = nil,
        warning: String? = nil,
        onClear: (() -> Void)? = nil,
        clearDisabled: Bool = false,
        @ViewBuilder leadingControl: @escaping () -> LeadingControl
    ) {
        self.inputTitle = inputTitle
        self.outputTitle = outputTitle
        self.leftPlaceholder = leftPlaceholder
        self.rightPlaceholder = rightPlaceholder
        self.leftDisplayText = leftDisplayText
        self.rightDisplayText = rightDisplayText
        self._left = left
        self._right = right
        self.rows = rows
        self.resultState = resultState
        self.syntax = syntax
        self.foldUnchanged = foldUnchanged
        self.error = error
        self.warning = warning
        self.onClear = onClear
        self.clearDisabled = clearDisabled
        self.leadingControl = leadingControl
        self.diffSummary = Self.computeDiffSummary(
            left: left.wrappedValue,
            right: right.wrappedValue,
            rows: rows,
            resultState: resultState,
            syntax: syntax,
            error: error
        )
    }

    /// 「非空」用 contains(where:) 首个非空白字符即返回（零拷贝、早退），
    /// 取代 trimmingCharacters 的全文分配；Character.isWhitespace 与
    /// .whitespacesAndNewlines 覆盖同一 Unicode 空白集合，语义等价。
    static func computeDiffSummary(
        left: String,
        right: String,
        rows: [DiffAlignedRow],
        resultState: DiffExecutionResultState,
        syntax: IndexDiffSyntax,
        error: String?
    ) -> DiffSummary {
        let leftNonEmpty = left.contains { !$0.isWhitespace }
        let rightNonEmpty = right.contains { !$0.isWhitespace }

        var identical = false
        if resultState == .current,
           error == nil,
           leftNonEmpty,
           rightNonEmpty {
            if syntax == .json && rows.isEmpty {
                identical = true
            } else if !rows.isEmpty {
                identical = rows.allSatisfy { !$0.kind.isDifference }
            }
        }

        let inputsPresent = resultState == .current
            && error == nil
            && (leftNonEmpty || rightNonEmpty)
        let blocks = inputsPresent ? differenceBlockCount(in: rows) : 0

        return DiffSummary(
            leftNonEmpty: leftNonEmpty,
            rightNonEmpty: rightNonEmpty,
            isIdentical: identical,
            differenceBlockCount: blocks
        )
    }

    private var canNavigateDifferences: Bool {
        Self.navigationEnabled(resultState: resultState, diffCount: diffSummary.differenceBlockCount)
    }

    static func navigationEnabled(
        resultState: DiffExecutionResultState,
        diffCount: Int
    ) -> Bool {
        resultState == .current && diffCount > 0
    }

    /// A consecutive replacement, insertion, or removal is one navigation
    /// destination. Inline segments remain a rendering detail of that block.
    static func differenceBlockCount(in rows: [DiffAlignedRow]) -> Int {
        var previousWasDifference = false
        var count = 0
        for row in rows {
            if row.kind.isDifference, !previousWasDifference {
                count += 1
            }
            previousWasDifference = row.kind.isDifference
        }
        return count
    }

    private var diagnosticText: String? {
        if let droppedFileDiagnostic { return droppedFileDiagnostic }
        // Running/stale notes only make sense once there is something to
        // compare; toggling options on empty panes must stay visually quiet.
        // 「非空」结论直接复用 init 期算好的 diffSummary，body 期不做 O(n) 全文扫描。
        let hasInput = diffSummary.leftNonEmpty || diffSummary.rightNonEmpty
        if resultState == .running {
            return hasInput ? "正在对比…" : nil
        }
        if resultState == .stale {
            return hasInput ? "正在更新对比结果…" : nil
        }
        guard resultState == .current else {
            return nil
        }
        if let error, !error.isEmpty {
            return error
        }
        if let warning, !warning.isEmpty {
            return warning
        }
        let summary = diffSummary
        if summary.isIdentical {
            return syntax == .json ? "两段 JSON 完全一致" : "两段文本完全一致"
        }
        if summary.differenceBlockCount > 0 {
            return "共 \(summary.differenceBlockCount) 个差异块"
        }
        return nil
    }

    private var diagnosticTone: ToolFeedbackTone {
        if droppedFileDiagnostic != nil { return .error }
        guard resultState == .current else {
            return .info
        }
        if let error, !error.isEmpty {
            return .error
        }
        if let warning, !warning.isEmpty {
            return .warning
        }
        if diffSummary.isIdentical {
            return .success
        }
        return .info
    }

    private var showsErrorState: Bool {
        diagnosticText != nil && diagnosticTone == .error
    }

    private var hasDiagnostic: Bool {
        diagnosticText != nil && (diagnosticTone == .error || diagnosticTone == .warning)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            IndexDiagnosticStatusSlot(isActive: hasDiagnostic) {
                HStack(spacing: 0) {
                    IndexDiagnosticBanner(
                        diagnostic: nil,
                        message: diagnosticText ?? "",
                        tone: diagnosticTone
                    )
                    if droppedFileDiagnostic != nil {
                        IndexIconButton(systemImage: "xmark", help: "关闭导入提示") {
                            droppedFileDiagnostic = nil
                        }
                        .padding(.trailing, 8)
                    }
                }
            }
            IndexEditableDiffMergeView(
                left: $left,
                right: $right,
                leftPlaceholder: leftPlaceholder,
                rightPlaceholder: rightPlaceholder,
                leftAccessibilityLabel: inputTitle,
                rightAccessibilityLabel: outputTitle,
                leftDisplayText: resultState == .current ? leftDisplayText : nil,
                rightDisplayText: resultState == .current ? rightDisplayText : nil,
                rows: resultState == .current ? rows : [],
                syntax: syntax,
                foldUnchanged: foldUnchanged,
                differenceNavigationRequest: navigationRequest,
                onFileDropDiagnostic: { droppedFileDiagnostic = $0 },
                onDifferenceNavigationChange: { progress in
                    // This callback can be invoked while AppKit is handling a
                    // representable update initiated by a toolbar action.
                    // Publish after that update has completed so SwiftUI does
                    // not discard the current/total indicator as a state
                    // mutation during view reconciliation.
                    DispatchQueue.main.async {
                        if navigationProgress != progress {
                            navigationProgress = progress
                        }
                    }
                }
            )
            .padding(.horizontal, ToolMetrics.Spacing.md)
            .padding(.bottom, ToolMetrics.Spacing.md)
            .padding(.top, ToolMetrics.Spacing.sm)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.panel, style: .continuous))
        .background(
            ToolTheme.panelBackground,
            in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.panel, style: .continuous)
        )
        .overlay {
            if showsErrorState {
                RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.panel, style: .continuous)
                    .strokeBorder(ToolTheme.error.opacity(0.55), lineWidth: 1)
            }
        }
        .toolShadow(ToolTheme.Shadow.panel)
        .toolAnimation(ToolMotion.Preset.diagnostic, value: hasDiagnostic)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var toolbar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                IndexBadge("STDIN", tone: .accent, isCapsule: true)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(10)
                Text(inputTitle)
                    .font(ToolTypography.panelTitle)
                    .foregroundStyle(ToolTheme.textSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(9)

                leadingControl()

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                IndexBadge("STDOUT", tone: .accent, isCapsule: true)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(10)
                Text(outputTitle)
                    .font(ToolTypography.panelTitle)
                    .foregroundStyle(ToolTheme.textSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(9)

                inlineDiagnostic

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    if let current = navigationProgress.current,
                       navigationProgress.total == diffSummary.differenceBlockCount {
                        IndexBadge(
                            "\(current) / \(navigationProgress.total)",
                            tone: .accent,
                            isCapsule: true
                        )
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityLabel("当前差异块 \(current)，共 \(navigationProgress.total) 个")
                    }
                    IndexIconButton(
                        systemImage: "chevron.up",
                        help: "上一处差异（⌥⌘↑）"
                    ) {
                        navigateDifference(false)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .disabled(!canNavigateDifferences)
                    IndexIconButton(
                        systemImage: "chevron.down",
                        help: "下一处差异（⌥⌘↓）"
                    ) {
                        navigateDifference(true)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .disabled(!canNavigateDifferences)
                    if let onClear {
                        IndexClearButton(
                            isDisabled: clearDisabled,
                            title: "清空对比",
                            showsIcon: false,
                            framed: true,
                            action: {
                                droppedFileDiagnostic = nil
                                onClear()
                            }
                        )
                    }
                }
                .layoutPriority(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 44)
        .padding(.horizontal, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ToolTheme.border)
                .frame(height: 0.5)
        }
        .accessibilityElement(children: .contain)
    }

    private func navigateDifference(_ forward: Bool) {
        guard canNavigateDifferences else { return }
        navigationRequest = DiffDifferenceNavigationRequest(
            id: (navigationRequest?.id ?? 0) + 1,
            forward: forward
        )
    }

    @ViewBuilder
    private var inlineDiagnostic: some View {
        if let diagnosticText, !hasDiagnostic {
            HStack(spacing: 4) {
                Image(systemName: diagnosticTone.systemImage)
                    .font(.system(size: ToolMetrics.IconSize.small, weight: .semibold))
                Text(diagnosticText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(ToolTypography.caption)
            .foregroundStyle(diagnosticTone.tint)
            .frame(maxWidth: 320, alignment: .leading)
            .layoutPriority(1)
            .help(diagnosticText)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(diagnosticTone.accessibilityPrefix)：\(diagnosticText)")
        }
    }
}

extension IndexEditableDiffWorkspace where LeadingControl == EmptyView {
    init(
        inputTitle: String = "原始文本",
        outputTitle: String = "对比文本",
        leftPlaceholder: String,
        rightPlaceholder: String,
        leftDisplayText: String? = nil,
        rightDisplayText: String? = nil,
        left: Binding<String>,
        right: Binding<String>,
        rows: [DiffAlignedRow],
        resultState: DiffExecutionResultState = .current,
        syntax: IndexDiffSyntax = .plain,
        foldUnchanged: Bool = false,
        error: String? = nil,
        warning: String? = nil,
        onClear: (() -> Void)? = nil,
        clearDisabled: Bool = false
    ) {
        self.init(
            inputTitle: inputTitle,
            outputTitle: outputTitle,
            leftPlaceholder: leftPlaceholder,
            rightPlaceholder: rightPlaceholder,
            leftDisplayText: leftDisplayText,
            rightDisplayText: rightDisplayText,
            left: left,
            right: right,
            rows: rows,
            resultState: resultState,
            syntax: syntax,
            foldUnchanged: foldUnchanged,
            error: error,
            warning: warning,
            onClear: onClear,
            clearDisabled: clearDisabled,
            leadingControl: { EmptyView() }
        )
    }
}
