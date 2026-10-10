@testable import XTools
import Combine
import Foundation
import Testing

struct ToolPreferenceStoreTests {
    @MainActor
    @Test func scalarPreferencesUseDefaultsAndPersistNormalizedValues() {
        let defaults = Self.defaults()
        let store = ToolPreferenceStore(defaults: defaults)
        let boolKey = ToolPreferenceKey<Bool>.bool("test.bool.v1", default: true)
        let intKey = ToolPreferenceKey<Int>.integer("test.int.v1", default: 5, range: 1...10)
        let doubleKey = ToolPreferenceKey<Double>.double("test.double.v1", default: 0.5, range: 0.2...0.8)
        let stringKey = ToolPreferenceKey<String>.string(
            "test.string.v1",
            default: "visible",
            allowedValues: ["visible", "hidden"]
        )

        #expect(store.value(for: boolKey))
        #expect(store.value(for: intKey) == 5)
        #expect(store.value(for: doubleKey) == 0.5)
        #expect(store.value(for: stringKey) == "visible")

        store.set(false, for: boolKey)
        store.set(99, for: intKey)
        store.set(0.05, for: doubleKey)
        store.set("unknown", for: stringKey)

        let reloaded = ToolPreferenceStore(defaults: defaults)
        #expect(!reloaded.value(for: boolKey))
        #expect(reloaded.value(for: intKey) == 10)
        #expect(reloaded.value(for: doubleKey) == 0.2)
        #expect(reloaded.value(for: stringKey) == "visible")

        defaults.set("not-a-bool", forKey: boolKey.rawKey)
        defaults.set("not-an-int", forKey: intKey.rawKey)
        defaults.set("not-a-double", forKey: doubleKey.rawKey)
        #expect(ToolPreferenceStore(defaults: defaults).value(for: boolKey))
        #expect(ToolPreferenceStore(defaults: defaults).value(for: intKey) == 5)
        #expect(ToolPreferenceStore(defaults: defaults).value(for: doubleKey) == 0.5)
    }

    @MainActor
    @Test func rawRepresentablePreferenceRejectsUnknownStoredValues() {
        let defaults = Self.defaults()
        let store = ToolPreferenceStore(defaults: defaults)
        let key = ToolPreferenceKey<ExampleChoice>.rawRepresentable(
            "test.choice.v1",
            default: .alpha
        )

        store.set(.beta, for: key)
        #expect(ToolPreferenceStore(defaults: defaults).value(for: key) == .beta)

        defaults.set("future-case", forKey: key.rawKey)
        #expect(ToolPreferenceStore(defaults: defaults).value(for: key) == .alpha)
    }

    private static func defaults() -> UserDefaults {
        let suiteName = "ToolPreferenceStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

struct ToolWorkspaceRepositoryTests {
    @MainActor
    @Test func modelResolutionIsLazyStableAndSeparatedByToolAndSlot() {
        let defaults = Self.defaults()
        let preferences = ToolPreferenceStore(defaults: defaults)
        let repository = ToolWorkspaceRepository(preferences: preferences)
        var creationCount = 0
        let firstKey = ToolWorkspaceKey(
            toolID: .workspaceFirst,
            create: { _ in
                creationCount += 1
                return WorkspaceTestModel(value: "first")
            }
        )
        let secondToolKey = ToolWorkspaceKey(
            toolID: .workspaceSecond,
            create: { _ in
                creationCount += 1
                return WorkspaceTestModel(value: "second")
            }
        )
        let secondSlotKey = ToolWorkspaceKey(
            toolID: .workspaceFirst,
            slot: "secondary",
            create: { _ in
                creationCount += 1
                return WorkspaceTestModel(value: "secondary")
            }
        )

        #expect(creationCount == 0)

        let first = repository.model(for: firstKey)
        #expect(creationCount == 1)
        #expect(repository.model(for: firstKey) === first)
        #expect(creationCount == 1)

        let secondTool = repository.model(for: secondToolKey)
        let secondSlot = repository.model(for: secondSlotKey)
        #expect(creationCount == 3)
        #expect(secondTool !== first)
        #expect(secondSlot !== first)
        #expect(secondSlot !== secondTool)
    }

    @MainActor
    @Test func repositoryLifetimeOwnsAndThenReleasesResolvedModels() {
        weak var releasedModel: WorkspaceTestModel?

        do {
            let repository = ToolWorkspaceRepository(defaults: Self.defaults())
            let key = ToolWorkspaceKey(toolID: .workspaceFirst) { _ in
                WorkspaceTestModel(value: "owned")
            }
            let model = repository.model(for: key)
            releasedModel = model
            #expect(releasedModel != nil)
        }

        #expect(releasedModel == nil)
    }

    @MainActor
    @Test func keyFactoryReceivesTheRepositoryPreferenceStore() {
        let defaults = Self.defaults()
        let preferenceKey = ToolPreferenceKey<String>.string(
            "test.workspace.preference.v1",
            default: "default"
        )
        let preferences = ToolPreferenceStore(defaults: defaults)
        preferences.set("restored", for: preferenceKey)
        let repository = ToolWorkspaceRepository(preferences: preferences)
        let key = ToolWorkspaceKey(toolID: .workspaceFirst) { store in
            WorkspaceTestModel(value: store.value(for: preferenceKey))
        }

        #expect(repository.model(for: key).value == "restored")
    }

    private static func defaults() -> UserDefaults {
        let suiteName = "ToolWorkspaceRepositoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

@MainActor
private final class WorkspaceTestModel: ObservableObject {
    @Published var value: String

    init(value: String) {
        self.value = value
    }
}

private enum ExampleChoice: String, Equatable {
    case alpha
    case beta
}

private extension ToolID {
    static let workspaceFirst = ToolID(rawValue: "workspace-first")
    static let workspaceSecond = ToolID(rawValue: "workspace-second")
}
