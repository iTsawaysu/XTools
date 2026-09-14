import XToolsCore
import Foundation

typealias IndexResultPresencePhase = ResultPresencePhase
typealias IndexResultPresenceMotionPolicy = ResultPresenceMotionPolicy
typealias IndexResultPresenceFirstAppearancePolicy = ResultPresenceFirstAppearancePolicy
typealias IndexResultPresenceAction = ResultPresenceAction
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
