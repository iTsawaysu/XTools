import AppKit
import SwiftUI
import Testing
import XToolsCore
@testable import XTools

@MainActor
@Suite(.serialized)
struct PageExactByteRegressionTests {
    @Test func converterRefreshesForCanonicalEquivalentUTF8AndRequestKeysRemainDistinct() {
        let workspace = IndexConverterToolWorkspaceModel(initialMode: "enc", convert: { input, _ in
            Data(input.utf8).base64EncodedString()
        })
        workspace.input = "é"
        #expect(workspace.output == "w6k=")
        workspace.input = "e\u{301}"
        #expect(workspace.output == "ZcyB")
        #expect(Set([
            IndexConverterRequest(input: "é", mode: "enc"),
            IndexConverterRequest(input: "e\u{301}", mode: "enc")
        ]).count == 2)
    }

    @Test func statisticsAndHashRefreshForChangedUTF8() async throws {
        let statistics = TextStatisticsWorkspaceModel(
            analysisOperation: { input, shouldCancel in try TextStatistics.analyze(input, shouldCancel: shouldCancel) },
            debounce: .zero
        )
        let hash = HashTextToolWorkspaceModel(
            preferences: preferences(),
            digestOperation: { bytes, shouldCancel in try? HashDigestPipeline.compute(bytes, shouldCancel: shouldCancel) },
            debounce: .zero,
            realtimeUTF8ByteLimit: 64
        )
        statistics.text = "é"
        hash.input = "é"
        try await waitUntil { !statistics.isAnalyzing && !hash.isComputing }
        #expect(statistics.stats.bytes == 2)
        let previous = hash.digests
        statistics.text = "e\u{301}"
        hash.input = "e\u{301}"
        #expect(hash.digests.isEmpty)
        try await waitUntil { !statistics.isAnalyzing && !hash.isComputing }
        #expect(statistics.stats.bytes == 3)
        #expect(hash.digests != previous)
        let sha256 = try #require(hash.digests.first { $0.algorithm == .sha256 })
        #expect(sha256.bytes.map { String(format: "%02x", $0) }.joined() == "bf12767b0f2a56b2190075bae8169f656e3ce8d6357d4aff184bc6c7ea48f9f6")
    }

    @Test func caseAndMaskingPreserveChangedSourceAndReplacementBytes() {
        let cases = CaseConverterToolWorkspaceModel()
        cases.text = "é"
        cases.text = "e\u{301}"
        #expect(cases.styles.last?.value.utf8.elementsEqual([0x65, 0xCC, 0x81]) == true)

        let mask = StringObfuscatorToolWorkspaceModel(preferences: preferences())
        mask.keepFirst = 1
        mask.keepLast = 0
        mask.input = "éabc"
        mask.input = "e\u{301}abc"
        #expect(mask.output.utf8.elementsEqual("e\u{301}***".utf8))
        mask.keepFirst = 0
        mask.setReplacementCharacter("é")
        mask.setReplacementCharacter("e\u{301}")
        #expect(mask.output.utf8.elementsEqual(String(repeating: "e\u{301}", count: 4).utf8))
    }

    @Test func dockerEditMarksPriorResultStaleWithoutAutomaticallyExecuting() async throws {
        let workspace = DockerConversionToolWorkspaceModel(preferences: preferences())
        workspace.input = "docker run -e NAME=é alpine"
        workspace.execution.schedule(snapshot: workspace.input, delay: .zero) { input in
            IndexDockerWorkspaceContent.binding(for: .init(input: input, direction: .runToCompose))
        }
        try await waitUntil { !workspace.execution.isRunning }
        try #require(!workspace.output.isEmpty)
        #expect(workspace.execution.isOutputFresh)
        let output = workspace.output
        workspace.input = "docker run -e NAME=e\u{301} alpine"
        #expect(!workspace.execution.isOutputFresh)
        #expect(!workspace.execution.isRunning)
        #expect(workspace.output.utf8.elementsEqual(output.utf8))
    }

    @Test func dockerComposeResourceLimitKeepsItsTypedDiagnostic() {
        let nested = String(repeating: "[", count: 65) + "0" + String(repeating: "]", count: 65)
        let binding = IndexDockerWorkspaceContent.binding(for: .init(
            input: "x-extra: \(nested)\nservices: {app: {image: alpine}}",
            direction: .composeToRun
        ))
        #expect(binding.output.isEmpty)
        #expect(binding.diagnostic?.message.contains("64 层") == true)
        #expect(binding.error == binding.diagnostic?.workspaceMessage)
        #expect(binding.error != "docker-compose YAML 格式无效。")
    }

    @Test func regexIdentityAndNestedCaptureColorsFollowExactNativeRanges() throws {
        #expect(RegexWorkspaceInput(pattern: "^é$", flags: "g", text: "é") != RegexWorkspaceInput(pattern: "^é$", flags: "g", text: "e\u{301}"))
        let report = try RegexMatcher.analyze(pattern: "((a))(b)", in: "ab", flags: "g")
        let ranges = RegexHighlightProjection.make(report: report, sourceText: "ab", selectedMatchIndex: nil).styledRanges
        #expect(ranges == [
            .init(range: NSRange(location: 0, length: 2), style: .match),
            .init(range: NSRange(location: 0, length: 1), style: .capture(0)),
            .init(range: NSRange(location: 0, length: 1), style: .capture(1)),
            .init(range: NSRange(location: 1, length: 1), style: .capture(2))
        ])
        let splitCluster = try RegexMatcher.analyze(pattern: ".", in: "e\u{301}", flags: "g")
        let splitRanges = RegexHighlightProjection.make(report: splitCluster, sourceText: "e\u{301}", selectedMatchIndex: nil).styledRanges
        #expect(splitRanges.map(\.range) == [NSRange(location: 0, length: 1), NSRange(location: 1, length: 1)])
    }

    @Test func readOnlySurfacePublishesExactNativeBytesWithoutReplacingEditor() async throws {
        let model = ExactReadOnlyProbe()
        let host = NSHostingView(rootView: ExactReadOnlyHost(model: model))
        let window = makeWindow(host)
        defer { window.close() }
        await settle(host)
        let editor = try #require(descendant(NSTextView.self, in: host))
        for text in ["e\u{301}", "é"] {
            model.text = text
            await settle(host)
            #expect(descendant(NSTextView.self, in: host) === editor)
            #expect(editor.string.utf8.elementsEqual(text.utf8))
            editor.setSelectedRange(NSRange(location: 0, length: (text as NSString).length))
            #expect((editor.string as NSString).substring(with: editor.selectedRange()).utf8.elementsEqual(text.utf8))
        }
    }

    @Test func hostedJWTRefreshesPayloadAndSecretWhenOnlyUTF8Changes() async throws {
        let repository = ToolWorkspaceRepository(preferences: preferences())
        let workspace = repository.model(for: JWTToolWorkspaceModel.key)
        workspace.session.mode = .generate
        workspace.session.generatePayload = "{\"name\":\"é\"}"
        workspace.session.generateSecret = String(repeating: "é", count: 16)
        let host = NSHostingView(rootView: IndexJWTPage().environmentObject(repository))
        let window = makeWindow(host)
        defer { window.close() }
        await settle(host)
        try #require(!workspace.session.generatedToken.isEmpty)
        let first = workspace.session.generatedToken
        workspace.session.generatePayload = "{\"name\":\"e\u{301}\"}"
        try await waitUntil { workspace.session.generatedToken != first }
        let second = workspace.session.generatedToken
        workspace.session.generateSecret = String(repeating: "e\u{301}", count: 16)
        try await waitUntil { workspace.session.generatedToken != second }
        #expect(!workspace.session.generatedToken.isEmpty)
        // Independent Python stdlib JSON bytes + HMAC-SHA256 vector.
        #expect(workspace.session.generatedToken == "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJuYW1lIjoiZcyBIn0.5tAocJUDSFsNVOZr8GgcK7Fmj6EcGunbUQWQ2Yxim0Y")
    }

    private func preferences() -> ToolPreferenceStore {
        ToolPreferenceStore(defaults: UserDefaults(suiteName: "PageExactByteRegressionTests.\(UUID())")!)
    }

    private func makeWindow<V: View>(_ host: NSHostingView<V>) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        return window
    }

    private func settle<V: View>(_ host: NSHostingView<V>) async {
        for _ in 0..<8 {
            host.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        return view.subviews.lazy.compactMap { descendant(type, in: $0) }.first
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition())
    }
}

@MainActor
private final class ExactReadOnlyProbe: ObservableObject {
    @Published var text = "é"
}

private struct ExactReadOnlyHost: View {
    @ObservedObject var model: ExactReadOnlyProbe
    var body: some View {
        IndexReadOnlyTextSurface(text: model.text, placeholder: "", fillsHeight: true)
    }
}
