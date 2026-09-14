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
        .help("清空生成和解析模式中的所有内容")
        .accessibilityLabel("清空所有内容")
    }
}

struct IndexGenerateParseModeContent<GenerateContent: View, ParseContent: View>: View {
    let mode: IndexGenerateParseMode
    private let generateContent: GenerateContent
    private let parseContent: ParseContent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        ZStack(alignment: .topLeading) {
            if mode == .generate {
                // Generate sits before parse in the mode order, so it enters
                // from the leading edge (backward) when the user steps back to it.
                modeBranch(generateContent, direction: .backward)
            } else {
                // Parse follows generate, so it enters from the trailing edge
                // (forward) when the user advances to it.
                modeBranch(parseContent, direction: .forward)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .animation(
            ToolMotion.animation(ToolMotion.Preset.orderedContent, reduceMotion: reduceMotion),
            value: mode
        )
    }

    private func modeBranch<Content: View>(_ content: Content, direction: ToolMotion.OrderedDirection) -> some View {
        VStack(alignment: .leading, spacing: ToolMetrics.Spacing.base) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .toolTransition(ToolMotion.Transition.orderedContent(direction), reduceMotion: reduceMotion)
    }
}
