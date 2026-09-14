import Foundation

struct IndexEphemeralActionFeedbackState: Equatable {
    static let holdDuration: Duration = .milliseconds(1_200)

    private(set) var isPresented = false
    private(set) var generation = 0

    mutating func trigger() {
        generation &+= 1
        isPresented = true
    }

    @discardableResult
    mutating func finish(generation: Int) -> Bool {
        guard isPresented, generation == self.generation else { return false }
        isPresented = false
        return true
    }
}
