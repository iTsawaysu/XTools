import SwiftUI

@MainActor
final class DeviceInformationSession: ObservableObject {
    @Published private(set) var snapshot: DeviceInformationSnapshot

    private var lastEntryGeneration: Int?
    private let capture: @MainActor () -> DeviceInformationSnapshot

    init(
        capture: @escaping @MainActor () -> DeviceInformationSnapshot = {
            MacDeviceInformationCollector.capture()
        }
    ) {
        self.capture = capture
        self.snapshot = capture()
    }

    func enterPage(generation: Int) {
        guard generation > 0, generation != lastEntryGeneration else { return }
        let isReentry = lastEntryGeneration != nil
        lastEntryGeneration = generation
        if isReentry { refresh() }
    }

    func refresh() {
        snapshot = capture()
    }
}
