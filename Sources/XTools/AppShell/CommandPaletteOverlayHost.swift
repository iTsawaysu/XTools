import AppKit
import SwiftUI

/// Stable lightweight observer for presentation-only state. The first open
/// creates one retained palette tree; later sessions reset its local model while
/// its native row identities remain stable.
struct CommandPaletteOverlayHost: View {
    @ObservedObject var presentation: CommandPalettePresentationModel
    let registry: ToolRegistry
    let baseActions: [CommandActionEntry]
    let reduceMotion: Bool
    let usage: any PaletteUsageScoring
    let onSelectTool: (ToolID, String?) -> Void
    let onRunCommand: (CommandActionID) -> Void
    let onRequestFocus: () -> Void
    let onDismiss: () -> Void
    /// Explicit animated visibility progress. `presentation.shows` alone
    /// never paints the panel: progress only reaches 1 through the animated
    /// state change below, so a full-bright first frame (the intermittent
    /// white flash under load) is structurally impossible.
    @State private var presentationProgress: CGFloat = 0

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .modifier(CommandPalettePresentationMotionModifier(
                progress: presentationProgress,
                isPresented: presentation.shows,
                reduceMotion: reduceMotion,
                traceSession: presentation.shows
                    ? presentation.session
                    : max(0, presentation.session - 1),
                scrim: CommandPaletteScrim(onDismiss: onDismiss),
                palette: Group {
                    if presentation.hasPresented {
                        let presentationSession = presentation.session
                        CommandPaletteView(
                            presentation: presentation,
                            registry: registry,
                            actions: baseActions,
                            isPresented: presentation.shows,
                            reduceMotion: reduceMotion,
                            focusToken: presentation.focusToken,
                            presentationSession: presentationSession,
                            canRequestSearchFocus: {
                                presentation.shows
                                    && presentation.session == presentationSession
                            },
                            usage: usage,
                            onSelectTool: onSelectTool,
                            onRunCommand: onRunCommand,
                            onRequestFocus: onRequestFocus,
                            onDismiss: onDismiss
                        )
                        .transition(.identity)
                    }
                }
            ))
        // One directional arc per toggle, applied where the state changes:
        // withAnimation on the explicit progress makes the interpolation
        // ride the same transaction as the flip, so late or loaded runloop
        // turns can never render the target value unanimated (the white
        // flash), and rapid reversals retarget the in-flight progress.
        .onChange(of: presentation.shows) { shows in
            withToolAnimation(
                shows
                    ? ToolMotion.PaletteMotion.open
                    : ToolMotion.PaletteMotion.close,
                reduceMotion: reduceMotion
            ) {
                presentationProgress = shows ? 1 : 0
            }
        }
        .onAppear {
            CommandPaletteTrace.presentationShellMounted()
        }
    }
}

/// This lightweight shell exists before the first command-palette session.
/// Only its `progress` animates, so the first mount and every warm reopen share
/// the same interpolation path without mirroring presentation state locally.
private struct CommandPalettePresentationMotionModifier<
    Scrim: View,
    Palette: View
>: @MainActor AnimatableModifier {
    var progress: CGFloat
    let isPresented: Bool
    let reduceMotion: Bool
    let traceSession: Int
    let scrim: Scrim
    let palette: Palette

    var animatableData: CGFloat {
        get { progress }
        set {
            progress = newValue
            let geometry = CommandPaletteVisibilityGeometry.resolve(
                progress: newValue,
                reduceMotion: reduceMotion
            )
            CommandPaletteTrace.presentationProgress(
                session: traceSession,
                isPresented: isPresented,
                progress: newValue,
                reduceMotion: reduceMotion,
                geometry: geometry
            )
        }
    }

    func body(content: Content) -> some View {
        let geometry = CommandPaletteVisibilityGeometry.resolve(
            progress: progress,
            reduceMotion: reduceMotion
        )
        ZStack {
            content
                .zIndex(0)

            // The scrim rides the same single progress interpolation as the
            // panel with a 0.30 dim ceiling: one animatable owner keeps rapid
            // open/close reversals continuous instead of queueing a second
            // directional scrim animation beside the panel arc.
            scrim
                .opacity(geometry.opacity * 0.30)
                .allowsHitTesting(isPresented)
                .accessibilityHidden(!isPresented)
                .zIndex(1)

            palette
                .opacity(geometry.opacity)
                .offset(y: geometry.offsetY)
                .zIndex(2)
        }
    }
}

private struct CommandPaletteScrim: View {
    let onDismiss: () -> Void

    var body: some View {
        // The dim amount (0.30 ceiling) is applied by the presentation
        // motion modifier through the shared progress, so the scrim itself
        // stays a plain full-window black layer.
        Color.black
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(perform: onDismiss)
    }
}
