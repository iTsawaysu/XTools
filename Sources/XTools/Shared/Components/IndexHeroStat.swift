import SwiftUI

enum IndexHeroStatTone: Sendable {
    case accent
    case primary
    
    var valueColor: Color {
        switch self {
        case .accent: return ToolTheme.accentHover
        case .primary: return ToolTheme.textPrimary
        }
    }
}

struct IndexHeroStat: View {
 let caption: String?
 let value: String
 let tone: IndexHeroStatTone
 let copyable: Bool
 let design: Font.Design
    
 init(
        caption: String? = nil,
        value: String,
        tone: IndexHeroStatTone = .accent,
        copyable: Bool = true,
        design: Font.Design = .monospaced
    ) {
        self.caption = caption
        self.value = value
        self.tone = tone
        self.copyable = copyable
        self.design = design
    }

 var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                IndexHeroValueText(
                    value: value,
                    color: tone.valueColor,
                    design: design
                )
                
                if copyable && !value.isEmpty {
                    IndexCopyButton(text: value, iconOnly: true)
                }
            }
            if let caption {
                Text(caption)
                    .font(ToolTypography.monoCaption)
                    .foregroundStyle(ToolTheme.textSecondary)
                    .toolMotionTextSwap(id: caption)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 26)
    }
}

/// Deterministic two-layer value hand-off for the hero readout. SwiftUI's
/// identity transitions are unreliable inside this HStack (the old/new Text
/// can land in one frame), so the outgoing and incoming layers run their own
/// staggered progress values: the old value leaves first, the new one rises
/// after a short beat. A plain cross-fade would blend two different-length
/// strings into an unreadable jumble at this font size.
private struct IndexHeroValueText: View {
    let value: String
    let color: Color
    let design: Font.Design

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedValue: String
    @State private var outgoingValue: String?
    @State private var enterProgress: CGFloat = 1
    @State private var exitProgress: CGFloat = 1
    @State private var cleanupTask: Task<Void, Never>?

    init(value: String, color: Color, design: Font.Design) {
        self.value = value
        self.color = color
        self.design = design
        _displayedValue = State(initialValue: value)
    }

    var body: some View {
        ZStack {
            if let outgoingValue {
                valueText(outgoingValue)
                    .opacity(1 - exitProgress)
                    .offset(y: -ToolMotion.Distance.valueSwapRise * exitProgress)
            }
            valueText(displayedValue)
                .opacity(enterProgress)
                .offset(y: ToolMotion.Distance.valueSwapRise * (1 - enterProgress))
                .textSelection(.enabled)
                .arrowCursorOnHover()
        }
        .animation(
            ToolMotion.animation(ToolMotion.Preset.valueSwapExit, reduceMotion: reduceMotion),
            value: exitProgress
        )
        .animation(
            ToolMotion.animation(ToolMotion.Preset.valueSwapEnter, reduceMotion: reduceMotion),
            value: enterProgress
        )
        .onChange(of: value) { newValue in
            guard newValue != displayedValue else { return }
            cleanupTask?.cancel()

            guard !reduceMotion else {
                displayedValue = newValue
                outgoingValue = nil
                enterProgress = 1
                exitProgress = 1
                return
            }

            outgoingValue = displayedValue
            displayedValue = newValue
            withTransaction(ToolMotion.disabledTransaction) {
                enterProgress = 0
                exitProgress = 0
            }
            withAnimation(ToolMotion.Preset.valueSwapExit) {
                exitProgress = 1
            }
            withAnimation(ToolMotion.Preset.valueSwapEnter) {
                enterProgress = 1
            }
            cleanupTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 360_000_000)
                guard !Task.isCancelled else { return }
                outgoingValue = nil
            }
        }
        .onDisappear {
            cleanupTask?.cancel()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(displayedValue)
    }

    private func valueText(_ value: String) -> some View {
        Text(value)
            .font(ToolTypography.heroValue(design: design))
            .foregroundStyle(color)
    }
}
