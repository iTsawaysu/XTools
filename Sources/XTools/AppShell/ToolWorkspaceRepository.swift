import SwiftUI

/// Implemented by workspace models that pin large binary payloads so the shell
/// can drop them when the user leaves the tool.
@MainActor
protocol ToolWorkspacePayloadEvicting: AnyObject {
    func evictHeavyPayloads()
}

@MainActor
struct ToolWorkspaceKey<Model: ObservableObject> {
    let toolID: ToolID
    let slot: String
    fileprivate let create: @MainActor (ToolPreferenceStore) -> Model

    init(
        toolID: ToolID,
        slot: String = "main",
        create: @escaping @MainActor (ToolPreferenceStore) -> Model
    ) {
        self.toolID = toolID
        self.slot = slot
        self.create = create
    }
}

@MainActor
final class ToolWorkspaceRepository: ObservableObject {
    private struct StorageKey: Hashable {
        let toolID: ToolID
        let slot: String
    }

    private let preferences: ToolPreferenceStore
    private var instances: [StorageKey: AnyObject] = [:]

    init(preferences: ToolPreferenceStore) {
        self.preferences = preferences
    }

    convenience init(defaults: UserDefaults = .standard) {
        self.init(preferences: ToolPreferenceStore(defaults: defaults))
    }

    func model<Model: ObservableObject>(for key: ToolWorkspaceKey<Model>) -> Model {
        let storageKey = StorageKey(toolID: key.toolID, slot: key.slot)
        if let existing = instances[storageKey] {
            guard let model = existing as? Model else {
                preconditionFailure("Tool workspace key was reused with a different model type.")
            }
            return model
        }

        let model = key.create(preferences)
        instances[storageKey] = model
        return model
    }

    /// Drops heavy payloads for every retained model of `toolID`. Models that do
    /// not conform to `ToolWorkspacePayloadEvicting` are left unchanged.
    func evictHeavyPayloads(for toolID: ToolID) {
        for (key, object) in instances where key.toolID == toolID {
            (object as? ToolWorkspacePayloadEvicting)?.evictHeavyPayloads()
        }
    }
}

@MainActor
struct ToolWorkspaceHost<Model: ObservableObject, Content: View>: View {
    @EnvironmentObject private var repository: ToolWorkspaceRepository

    private let key: ToolWorkspaceKey<Model>
    private let content: (Model, ObservedObject<Model>.Wrapper) -> Content

    init(
        key: ToolWorkspaceKey<Model>,
        @ViewBuilder content: @escaping (Model, ObservedObject<Model>.Wrapper) -> Content
    ) {
        self.key = key
        self.content = content
    }

    var body: some View {
        ToolWorkspaceObservedHost(
            model: repository.model(for: key),
            content: content
        )
    }
}

@MainActor
private struct ToolWorkspaceObservedHost<Model: ObservableObject, Content: View>: View {
    @ObservedObject var model: Model
    let content: (Model, ObservedObject<Model>.Wrapper) -> Content

    var body: some View {
        content(model, $model)
    }
}
