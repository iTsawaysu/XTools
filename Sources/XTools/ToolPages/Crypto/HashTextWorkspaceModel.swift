import Combine
import XToolsCore
import Foundation

/// A nil result means the request was cancelled before a coherent batch was ready.
typealias HashDigestOperation = @Sendable (
    _ bytes: [UInt8],
    _ shouldCancel: @escaping @Sendable () -> Bool
) -> [HashDigestPipeline.DigestItem]?

@MainActor
final class HashTextToolWorkspaceModel: ObservableObject {
    static let realtimeUTF8ByteLimit = 64 * 1_024

    static let key = ToolWorkspaceKey<HashTextToolWorkspaceModel>(toolID: "hash-text") { preferences in
        HashTextToolWorkspaceModel(preferences: preferences)
    }

    @Published var input = "" {
        didSet {
            guard input != oldValue else { return }
            inputDidChange()
        }
    }

    @Published var encoding: String {
        didSet {
            preferences.set(encoding, for: SensitiveToolPreferenceKeys.hashDigestEncoding)
        }
    }

    /// Raw bytes remain independent of the selected display encoding so format
    /// switches do not repeat expensive digest work.
    @Published private(set) var digests: [HashDigestPipeline.DigestItem] = []
    @Published private(set) var isComputing = false
    @Published private(set) var usesExplicitComputation = false

    private let preferences: ToolPreferenceStore
    private let execution: SupersedingExecutionSession
    private let digestOperation: HashDigestOperation
    private let debounce: Duration
    private let realtimeUTF8ByteLimit: Int

    convenience init(preferences: ToolPreferenceStore) {
        self.init(
            preferences: preferences,
            digestOperation: Self.defaultDigestOperation,
            debounce: .milliseconds(180),
            realtimeUTF8ByteLimit: Self.realtimeUTF8ByteLimit
        )
    }

    init(
        preferences: ToolPreferenceStore,
        digestOperation: @escaping HashDigestOperation,
        debounce: Duration,
        realtimeUTF8ByteLimit: Int
    ) {
        self.preferences = preferences
        self.digestOperation = digestOperation
        execution = SupersedingExecutionSession(cancelInFlight: true)
        self.debounce = debounce
        self.realtimeUTF8ByteLimit = max(0, realtimeUTF8ByteLimit)
        encoding = preferences.value(for: SensitiveToolPreferenceKeys.hashDigestEncoding)
    }

    func computeExplicitly() {
        guard usesExplicitComputation, !input.isEmpty, !isComputing else { return }

        let snapshot = input

        digests = []
        isComputing = true
        runDigests(snapshot: snapshot, debounce: .zero)
    }

    private func inputDidChange() {
        let snapshot = input
        usesExplicitComputation = snapshot.utf8.count > realtimeUTF8ByteLimit
        digests = []
        execution.invalidate()

        guard !snapshot.isEmpty else {
            usesExplicitComputation = false
            isComputing = false
            return
        }
        guard !usesExplicitComputation else {
            isComputing = false
            return
        }

        isComputing = true
        runDigests(snapshot: snapshot, debounce: debounce)
    }

    private func runDigests(snapshot: String, debounce: Duration) {
        let digestOperation = self.digestOperation
        execution.schedule(
            debounce: debounce,
            operation: { shouldCancel in
                guard let digests = digestOperation(Array(snapshot.utf8), shouldCancel) else {
                    throw CancellationError()
                }
                return digests
            },
            publish: { [weak self] _, completedDigests in
                guard let self, !self.input.isEmpty else { return }
                self.digests = completedDigests
                self.isComputing = false
            }
        )
    }

    nonisolated private static let defaultDigestOperation: HashDigestOperation = { bytes, shouldCancel in
        try? HashDigestPipeline.compute(bytes, shouldCancel: shouldCancel)
    }
}
