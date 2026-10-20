import SwiftUI

enum IndexGenerateParseMode: String, CaseIterable, Identifiable {
    case generate
    case parse

    var id: String { rawValue }

    var label: String {
        switch self {
        case .generate: return "生成"
        case .parse: return "解析"
        }
    }

    static var segmentedItems: [(String, String)] {
        allCases.map { ($0.rawValue, $0.label) }
    }
}

struct IndexGenerateParseModeBar: View {
    @Binding var selection: IndexGenerateParseMode
    var clearAllDisabled = false
    let onClearAll: () -> Void

    private var selectionBinding: Binding<String> {
        Binding(
            get: { selection.rawValue },
            set: { selection = IndexGenerateParseMode(rawValue: $0) ?? selection }
        )
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 9) {
                modeControl
                Spacer(minLength: 9)
                clearAllButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 9) {
                modeControl
                clearAllButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var modeControl: some View {
        IndexSegmentedControl(
            items: IndexGenerateParseMode.segmentedItems,
            selection: selectionBinding
        )
        .accessibilityLabel("操作模式")
    }

    private var clearAllButton: some View {
        Button(action: onClearAll) {
            Label("清空", systemImage: IndexActionSymbol.clear)
                .font(ToolTypography.buttonSmall)
        }
        .buttonStyle(IndexSmallButtonStyle())
        .disabled(clearAllDisabled)
        .accessibilityLabel("清空所有内容")
    }
}

struct IndexGenerateParseModeContent<GenerateContent: View, ParseContent: View>: View {
    let mode: IndexGenerateParseMode
    private let generateContent: GenerateContent
    private let parseContent: ParseContent

    init(
        mode: IndexGenerateParseMode,
        @ViewBuilder generate: () -> GenerateContent,
        @ViewBuilder parse: () -> ParseContent
    ) {
        self.mode = mode
        self.generateContent = generate()
        self.parseContent = parse()
    }

    var body: some View {
        IndexModeContent(id: mode) { currentMode in
            VStack(alignment: .leading, spacing: ToolMetrics.Spacing.base) {
                if currentMode == .generate {
                    generateContent
                } else {
                    parseContent
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}
