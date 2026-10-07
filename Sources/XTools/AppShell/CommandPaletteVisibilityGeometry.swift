import AppKit
import SwiftUI

struct CommandPaletteVisibilityGeometry: Equatable {
    let opacity: Double
    let offsetY: CGFloat

    /// Presentation mapping (MOTION cmdkIn/cmdkOut): the panel rises from
    /// `riseDistance` below while fading in; close reverses the same
    /// continuous function on the exit arc. One shared mapping keeps rapid
    /// open/close reversals continuous — the presentation never hard-switches
    /// geometry mid-flight. Deliberately opacity+translation only: a scale
    /// channel would resample the retained native-view subtree (~45 NSViews)
    /// on every interpolated frame and quantize the open arc into brightness
    /// steps.
    static func resolve(
        progress: CGFloat,
        reduceMotion: Bool
    ) -> Self {
        let progress = min(max(progress, 0), 1)
        return Self(
            opacity: Double(progress),
            offsetY: reduceMotion
                ? 0
                : ToolMotion.PaletteMotion.riseDistance * (1 - progress)
        )
    }
}
