import XToolsCore
import Foundation

typealias IndexResultPresenceMotionPolicy = ResultPresenceMotionPolicy
typealias IndexResultPresenceFirstAppearancePolicy = ResultPresenceFirstAppearancePolicy
typealias IndexResultPresenceCompletion = ResultPresenceCompletion
typealias IndexResultPresenceState = ResultPresenceState

extension IndexResultPresenceCompletion {
    var duration: TimeInterval {
        switch self {
        case .appearance:
            ToolMotion.ResultPresence.appearanceDuration
        case .exit:
            ToolMotion.ResultPresence.exitDuration
        }
    }
}
