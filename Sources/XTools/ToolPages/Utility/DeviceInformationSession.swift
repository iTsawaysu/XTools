import SwiftUI

@MainActor
final class DeviceInformationSession: ObservableObject {
    @Published private(set) var snapshot: DeviceInformationSnapshot?

    private var lastEntryGeneration: Int?
    private var refreshTask: Task<Void, Never>?
    private let capture: @MainActor () async -> DeviceInformationSnapshot

    init(capture: @escaping @MainActor () async -> DeviceInformationSnapshot = MacDeviceInformationCollector.capture) {
        self.capture = capture
        refresh()
    }

    func enterPage(generation: Int) {
        guard generation > 0, generation != lastEntryGeneration else { return }
        let isReentry = lastEntryGeneration != nil
        lastEntryGeneration = generation
        if isReentry { refresh() }
    }

    func refresh() {
        guard refreshTask == nil else { return }
        refreshTask = Task { @MainActor [weak self, capture] in
            guard !Task.isCancelled else { return }
            let snapshot = await capture()
            guard let self, !Task.isCancelled else { return }
            self.snapshot = snapshot
            self.refreshTask = nil
        }
    }

    deinit {
        refreshTask?.cancel()
    }
}
