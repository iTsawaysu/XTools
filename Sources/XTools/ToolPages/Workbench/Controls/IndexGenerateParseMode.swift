import SwiftUI
import XToolsDesign

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
