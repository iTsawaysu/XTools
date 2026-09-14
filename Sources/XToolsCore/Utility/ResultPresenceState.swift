import Foundation

public enum ResultPresencePhase: Equatable, Sendable {
    case empty, appearing, presented, exiting
}

public enum ResultPresenceMotionPolicy: Equatable, Sendable {
    case animated
    case immediate
}

public enum ResultPresenceFirstAppearancePolicy: Equatable, Sendable {
    case animated
    case immediate
}

public enum ResultPresenceAction: Equatable, Sendable {
    case none
    case appear(generation: Int, fadesIn: Bool)
    case update
    case exit(generation: Int)
    case settle
}

public enum ResultPresenceCompletion: Equatable, Sendable {
    case appearance(generation: Int)
    case exit(generation: Int)

    public var generation: Int {
        switch self {
        case let .appearance(generation), let .exit(generation):
            generation
        }
    }
}

/// Animation timing stays outside this module (product motion tokens).
/// Value is not constrained to Sendable so SwiftUI hosts can store non-Sendable
/// snapshots while still testing the machine from Core.
public struct ResultPresenceState<Value> {
    public private(set) var phase: ResultPresencePhase
    public private(set) var snapshot: Value?
    public private(set) var generation = 0
    private var hasPresentedValue: Bool

    public init(initialValue: Value?) {
        snapshot = initialValue
        phase = initialValue == nil ? .empty : .presented
        hasPresentedValue = initialValue != nil
    }

    public mutating func update(
        to target: Value?,
        reduceMotion: Bool,
        firstAppearance: ResultPresenceFirstAppearancePolicy = .animated
    ) -> ResultPresenceAction {
        if reduceMotion {
            let alreadySettled = (target == nil && phase == .empty)
                || (target != nil && phase == .presented)
            snapshot = target

            if alreadySettled {
                return target == nil ? .none : .update
            }

            generation += 1
            phase = target == nil ? .empty : .presented
            hasPresentedValue = target != nil || hasPresentedValue
            return .settle
        }

        if let target {
            switch phase {
            case .empty:
                generation += 1
                snapshot = target

                if !hasPresentedValue, firstAppearance == .immediate {
                    phase = .presented
                    hasPresentedValue = true
                    return .settle
                }

                phase = .appearing
                hasPresentedValue = true
                return .appear(generation: generation, fadesIn: true)
            case .exiting:
                generation += 1
                snapshot = target
                phase = .appearing
                hasPresentedValue = true
                return .appear(generation: generation, fadesIn: false)
            case .appearing, .presented:
                snapshot = target
                hasPresentedValue = true
                return .update
            }
        }

        switch phase {
        case .empty, .exiting:
            return .none
        case .appearing, .presented:
            generation += 1
            phase = .exiting
            return .exit(generation: generation)
        }
    }

    @discardableResult
    public mutating func finish(_ completion: ResultPresenceCompletion) -> Bool {
        guard completion.generation == generation else { return false }

        switch completion {
        case .appearance:
            guard phase == .appearing else { return false }
            phase = .presented
        case .exit:
            guard phase == .exiting else { return false }
            phase = .empty
            snapshot = nil
        }

        return true
    }
}
