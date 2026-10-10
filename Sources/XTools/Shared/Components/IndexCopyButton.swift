import SwiftUI

/// Shared copy action (F3 归位): the shared layer's hero stat and code viewer
/// surfaces consume this button, so it lives in Shared/Components rather than
/// the Workbench control family. Styling collaborators (IndexIconActionButtonStyle,
/// IndexSmallButtonStyle) stay in the Workbench controls file.
///
/// Copy variant on the same icon-only discipline: the tooltip keeps
/// announcing the copied state while it exists.
private struct IndexCopyButtonHelp: ViewModifier {
    let iconOnly: Bool
    let copied: Bool
    let title: String

    func body(content: Content) -> some View {
        if iconOnly {
            content.help(copied ? "已复制" : title)
        } else {
            content
        }
    }
}

// MARK: - IndexCopyButton

struct IndexCopyButton: View {
    let text: String
    var title = "复制"
    var iconOnly = false
    /// Text-only label (prototype v3 workbench/params rows render actions
    /// without leading glyphs).
    var showsIcon = true
    var framed = false
    /// Overrides the canonical copied toast for batch actions (全部复制).
    var successToast: String? = nil

    @State private var feedback = IndexEphemeralActionFeedbackState()
    @Environment(\.toolToastCenter) private var toastCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var copied: Bool { feedback.isPresented }

    var body: some View {
        Group {
            if iconOnly {
                copyButton.buttonStyle(IndexIconActionButtonStyle(
                    isActive: copied,
                    activeTint: ToolTheme.success,
                    activeBackground: ToolTheme.successSoft
                ))
            } else {
                copyButton.buttonStyle(IndexSmallButtonStyle(done: copied, framed: framed))
            }
        }
        .disabled(text.isEmpty)
        // Labeled buttons show their own title; only icon-only slots need the
        // tooltip to name the action.
        .modifier(IndexCopyButtonHelp(iconOnly: iconOnly, copied: copied, title: title))
        .accessibilityLabel(copied ? "已复制" : title)
        .task(id: feedback.generation) {
            let generation = feedback.generation
            guard feedback.isPresented else { return }

            do {
                try await Task.sleep(for: IndexEphemeralActionFeedbackState.holdDuration)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            feedback.finish(generation: generation)
        }
    }

    private var copyButton: some View {
        Button {
            guard !text.isEmpty else { return }
            guard IndexPasteboard.copyString(text) else {
                toastCenter?.show(ToolFeedbackCopy.clipboardWriteFailure, tone: .error)
                return
            }
            toastCenter?.show(successToast ?? ToolFeedbackCopy.copied, tone: .success)
            feedback.trigger()
        } label: {
            if iconOnly {
                // Reduce Motion cuts directly between the SF Symbols; otherwise
                // the Wave 2 tick draws the checkmark (no label/width change).
                Group {
                    if reduceMotion {
                        Image(systemName: copied ? "checkmark" : IndexActionSymbol.copy)
                    } else {
                        IndexCopyTickIconSlot(generation: feedback.generation)
                    }
                }
                .font(ToolTypography.buttonSmall)
                .frame(width: 16, height: 16)
            } else {
                Label {
                    // Zero-deformation copy feedback: the visible title never
                    // changes (Wave 2 复制确认 tick); only the accessibility
                    // label announces 已复制.
                    Text(title)
                } icon: {
                    if showsIcon {
                        Group {
                            if reduceMotion {
                                Image(systemName: copied ? "checkmark" : IndexActionSymbol.copy)
                            } else {
                                IndexCopyTickIconSlot(generation: feedback.generation)
                            }
                        }
                    }
                }
                .font(ToolTypography.buttonSmall)
            }
        }
    }
}

// MARK: - IndexCopyTickIconSlot (Wave 2 copy-confirmation tick)

/// Fixed icon slot for the shared copy button (Wave 2 candidate d1): the copy
/// glyph fades out while a checkmark stroke-draws in (`Shape.trim` mirrors the
/// prototype's stroke-dashoffset), the icon box settles 0.94→1 once, the state
/// dwells 1400ms, then both glyphs cross-fade back symmetrically. Repeat clicks
/// during the dwell only reset the dwell timer — the draw never replays while
/// active. Reduce Motion stays at the call site (plain symbol cut, no draw,
/// no scale).
private struct IndexCopyTickIconSlot: View {
    let generation: Int

    @State private var isDwelling = false
    @State private var checkDraw: CGFloat = 0
    @State private var boxScale: CGFloat = 1
    @State private var dwellTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Image(systemName: IndexActionSymbol.copy)
                .opacity(isDwelling ? 0 : 1)

            IndexCopyTickCheckGlyph()
                .trim(from: 0, to: checkDraw)
                .stroke(.foreground, style: IndexCopyTickCheckGlyph.strokeStyle)
                .opacity(isDwelling ? 1 : 0)
        }
        .scaleEffect(boxScale)
        .onChange(of: generation) { _ in
            guard generation > 0 else { return }
            if isDwelling {
                resetDwell()
            } else {
                startDwell()
            }
        }
        .onDisappear {
            dwellTask?.cancel()
        }
    }

    /// First copy of a cycle: park at the pre-draw frame (check undrawn, box
    /// at 0.94) for one committed render — the SwiftUI analogue of the
    /// prototype keyframe `from` values — then run the enter choreography.
    private func startDwell() {
        dwellTask?.cancel()
        withTransaction(ToolMotion.disabledTransaction) {
            checkDraw = 0
            boxScale = ToolMotion.CopyTick.boxFrom
        }
        runDwell {
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(ToolMotion.CopyTick.fade) { isDwelling = true }
            withAnimation(ToolMotion.CopyTick.drawCurve) { checkDraw = 1 }
            withAnimation(ToolMotion.CopyTick.boxSettle) { boxScale = 1 }
        }
    }

    /// Repeat click while the dwell is active: only the hold timer restarts;
    /// the draw and the box settle never replay.
    private func resetDwell() {
        runDwell {}
    }

    /// One task owns the dwell tail: run `open`, hold for
    /// `ToolMotion.CopyTick.hold`, then fade both glyphs back symmetrically.
    private func runDwell(_ open: @escaping @MainActor () async -> Void) {
        dwellTask?.cancel()
        dwellTask = Task { @MainActor in
            await open()
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .seconds(ToolMotion.CopyTick.hold))
            guard !Task.isCancelled else { return }
            withAnimation(ToolMotion.CopyTick.fadeBack) { isDwelling = false }
        }
    }
}

/// Checkmark stroke glyph (prototype 16-unit check path), normalized to the
/// icon slot so `.trim` can draw it as one continuous stroke.
private struct IndexCopyTickCheckGlyph: Shape {
    /// Prototype icon stroke: 1.5 units in the 16-unit glyph box, round caps.
    static let strokeStyle = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)

    func path(in rect: CGRect) -> Path {
        // Prototype check path `M3 8.6l3.2 3L13 4.4` in a 16×16 viewBox.
        let scaleX = rect.width / 16
        let scaleY = rect.height / 16
        var path = Path()
        path.move(to: CGPoint(x: 3 * scaleX, y: 8.6 * scaleY))
        path.addLine(to: CGPoint(x: 6.2 * scaleX, y: 11.6 * scaleY))
        path.addLine(to: CGPoint(x: 13 * scaleX, y: 4.4 * scaleY))
        return path
    }
}
