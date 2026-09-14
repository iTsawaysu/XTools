import Foundation

public struct ChronometerLap: Equatable, Sendable {
    public let interval: TimeInterval
    public let split: TimeInterval

    public init(interval: TimeInterval, split: TimeInterval) {
        self.interval = max(0, interval)
        self.split = max(0, split)
    }
}

public struct ChronometerState: Equatable, Sendable {
    public private(set) var accumulated: TimeInterval
    public private(set) var runningSince: TimeInterval?
    public private(set) var laps: [ChronometerLap]

    public init(
        accumulated: TimeInterval = 0,
        runningSince: TimeInterval? = nil,
        laps: [ChronometerLap] = []
    ) {
        self.accumulated = max(0, accumulated)
        self.runningSince = runningSince
        self.laps = laps
    }

    public var isRunning: Bool {
        runningSince != nil
    }

    public var canRecordLap: Bool {
        isRunning
    }

    public var hasElapsed: Bool {
        isRunning || accumulated > 0 || !laps.isEmpty
    }

    public var canReset: Bool {
        !isRunning && hasElapsed
    }

    public func elapsed(at now: TimeInterval) -> TimeInterval {
        guard let runningSince else { return accumulated }
        return accumulated + max(0, now - runningSince)
    }

    public mutating func start(at now: TimeInterval) {
        guard runningSince == nil else { return }
        runningSince = now
    }

    public mutating func pause(at now: TimeInterval) {
        guard let runningSince else { return }
        accumulated += max(0, now - runningSince)
        self.runningSince = nil
    }

    public mutating func toggle(at now: TimeInterval) {
        if isRunning {
            pause(at: now)
        } else {
            start(at: now)
        }
    }

    @discardableResult
    public mutating func recordLap(at now: TimeInterval) -> ChronometerLap? {
        guard isRunning else { return nil }
        let split = elapsed(at: now)
        let previousSplit = laps.first?.split ?? 0
        let lap = ChronometerLap(
            interval: max(0, split - previousSplit),
            split: split
        )
        laps.insert(lap, at: 0)
        return lap
    }

    public mutating func reset() {
        accumulated = 0
        runningSince = nil
        laps = []
    }
}

public enum ChronometerFormatter {
    public static func format(_ interval: TimeInterval) -> String {
        let milliseconds = max(0, Int(interval * 1000))
        return String(
            format: "%02d:%02d.%02d",
            milliseconds / 60_000,
            (milliseconds % 60_000) / 1000,
            (milliseconds % 1000) / 10
        )
    }
}
