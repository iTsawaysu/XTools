@testable import XTools
import CoreGraphics
import Testing

struct PaletteIconFlightCoordinatorTests {
    @MainActor
    @Test func finishingCurrentFlightPreservesTheNextPendingLaunch() throws {
        let coordinator = PaletteIconFlightCoordinator()
        let currentLaunch = PendingPaletteFlight(
            toolID: ToolID(rawValue: "current"),
            systemImage: "circle",
            from: CGPoint(x: 10, y: 20)
        )
        let pending = PendingPaletteFlight(
            toolID: ToolID(rawValue: "next"),
            systemImage: "square",
            from: CGPoint(x: 50, y: 60)
        )

        coordinator.beginLaunch(currentLaunch)
        coordinator.resolvePendingFlight(to: CGPoint(x: 30, y: 40))
        let current = try #require(coordinator.flight)
        coordinator.beginLaunch(pending)
        coordinator.finish(flight: current)

        #expect(coordinator.flight == nil)

        coordinator.resolvePendingFlight(to: CGPoint(x: 70, y: 80))
        let next = try #require(coordinator.flight)
        #expect(next.id == "next")
        #expect(next.from == pending.from)
        #expect(next.to == CGPoint(x: 70, y: 80))
        #expect(next.token == current.token + 1)
    }

    @MainActor
    @Test func staleCompletionCannotClearTheNewerFlight() throws {
        let coordinator = PaletteIconFlightCoordinator()
        coordinator.beginLaunch(PendingPaletteFlight(
            toolID: ToolID(rawValue: "old"),
            systemImage: "circle",
            from: .zero
        ))
        coordinator.resolvePendingFlight(to: CGPoint(x: 1, y: 1))
        let old = try #require(coordinator.flight)

        coordinator.beginLaunch(PendingPaletteFlight(
            toolID: ToolID(rawValue: "current"),
            systemImage: "square",
            from: .zero
        ))
        coordinator.resolvePendingFlight(to: CGPoint(x: 2, y: 2))
        let current = try #require(coordinator.flight)

        coordinator.finish(flight: old)

        #expect(coordinator.flight == current)
    }
}
