import AppKit
import SwiftUI
import Testing
import XToolsCore
@testable import XTools

@MainActor
@Suite(.serialized)
struct SourceControlPageLifecycleTests {
    @Test(arguments: [false, true])
    func hiddenUpdateCompletionWaitsForReentryAndPresentsOnlyOnce(fails: Bool) async throws {
        let directory = URL(fileURLWithPath: "/Users/sun/Downloads/tmp")
            .appendingPathComponent("xtools-source-control-lifecycle-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("repo/.git", isDirectory: true),
            withIntermediateDirectories: true
        )
        let preferences = ToolPreferenceStore(defaults: UserDefaults(suiteName: "SourceControlPageLifecycle.\(UUID())")!)
        let git = PageLifecycleGitClient(fails: fails)
        let workspace = SourceControlWorkspaceModel(
            preferences: preferences,
            scanner: SourceControlScanner(git: git),
            updater: SourceControlUpdateExecutor(git: git)
        )
        workspace.setPath(directory.path)
        let repository = ToolWorkspaceRepository(preferences: preferences)
        let injectedKey = ToolWorkspaceKey<SourceControlWorkspaceModel>(toolID: "source-control") { _ in workspace }
        #expect(repository.model(for: injectedKey) === workspace)
        let toastCenter = ToolToastCenter()
        func root(_ generation: Int) -> some View {
            IndexSourceControlPage()
                .environmentObject(repository)
                .environment(\.toolPageEntryGeneration, generation)
                .environment(\.toolToastCenter, toastCenter)
        }
        let host = NSHostingView(rootView: root(1))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 750), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer {
            workspace.cancel()
            if let sheet = window.attachedSheet { window.endSheet(sheet) }
            window.close()
            Task { await git.releasePull() }
        }
        try await waitUntil("initial scan") { !workspace.isScanning && workspace.repositories.count == 1 }
        workspace.update()
        try await waitUntil("pull started") { await git.hasStartedPull() }
        host.rootView = root(0)
        await settle(host)
        await git.releasePull()
        try await waitUntil("hidden update and refresh completed") {
            workspace.lastRunSummary != nil && !workspace.isUpdating && !workspace.isScanning
        }
        await settle(host)
        let completion = try #require(workspace.lastRunSummary)
        #expect(completion.failedCount == (fails ? 1 : 0))
        #expect(workspace.lastCompletion?.id == completion.id, "Hidden completion must remain unconsumed")
        #expect(toastCenter.messages.isEmpty)
        #expect(window.attachedSheet == nil)
        #expect(workspace.failureSummary.count == (fails ? 1 : 0))

        host.rootView = root(2)
        try await waitUntil("completion presented after reentry") {
            fails ? window.attachedSheet != nil : toastCenter.messages.count == 1
        }
        #expect(workspace.lastCompletion == nil)
        if fails {
            #expect(toastCenter.messages.isEmpty)
            #expect(workspace.failureSummary.first?.diagnostic.code == "pull-dirty-worktree")
        } else {
            let message = try #require(toastCenter.messages.first)
            #expect(message.text == "所有仓库均已是最新")
            toastCenter.pauseDismissal(for: message.id)
        }

        // The presentation has been consumed. Another visit must not replay it.
        host.rootView = root(0)
        await settle(host)
        try await waitUntil("sheet dismissed when parked") { window.attachedSheet == nil }
        host.rootView = root(3)
        await settle(host)
        #expect(window.attachedSheet == nil)
        #expect(toastCenter.messages.count == (fails ? 0 : 1))
        #expect(workspace.lastCompletion == nil)
    }

    private func settle(_ view: NSView) async {
        for _ in 0..<8 {
            view.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func waitUntil(_ phase: String, _ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<150 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        let satisfied = await condition()
        try #require(satisfied, "Timed out: \(phase)")
    }
}

private actor PageLifecycleGitClient: GitProcessClient {
    private let fails: Bool
    private var startedPull = false
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?

    init(fails: Bool) { self.fails = fails }
    func hasStartedPull() -> Bool { startedPull }
    func releasePull() {
        released = true
        continuation?.resume()
        continuation = nil
    }

    func run(_ request: GitCommandRequest, timeout: Duration) async throws -> GitProcessOutput {
        switch request.kind {
        case .repositoryRoot:
            return GitProcessOutput(exitCode: 0, standardOutput: request.repositoryPath + "\n")
        case .statusV2:
            return GitProcessOutput(exitCode: 0, standardOutput: "# branch.oid abc123\n# branch.head main\n# branch.upstream origin/main\n# branch.ab +0 -0\n")
        case .remote:
            return GitProcessOutput(exitCode: 0, standardOutput: "origin\thttps://git.example.test/repo.git (fetch)\n")
        case .pullFastForward:
            startedPull = true
            if !released { await withCheckedContinuation { continuation = $0 } }
            if fails {
                return GitProcessOutput(exitCode: 1, standardError: "error: Your local changes to the following files would be overwritten by merge")
            }
            return GitProcessOutput(exitCode: 0, standardOutput: "Already up to date.\n")
        default:
            return GitProcessOutput(exitCode: 1)
        }
    }
}
