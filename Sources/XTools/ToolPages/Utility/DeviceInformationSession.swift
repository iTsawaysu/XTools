import SwiftUI

@MainActor
final class DeviceInformationSession: ObservableObject {
    @Published private(set) var snapshot: DeviceInformationSnapshot

    private let capture: @MainActor () -> DeviceInformationSnapshot

    init(
        capture: @escaping @MainActor () -> DeviceInformationSnapshot = {
            MacDeviceInformationCollector.capture()
        }
    ) {
        self.capture = capture
        self.snapshot = capture()
    }

    func refresh() {
        snapshot = capture()
    }
}
