@testable import XTools
import Foundation
import Testing
import XToolsCore

/// 大小写转换工作台护栏：小输入同步即时，大输入后台 + 防抖 + 过期结果丢弃。
/// 结构对齐 IndexConverterWorkspaceExecutionTests（同域同一套执行语义）。
struct CaseConverterToolWorkspaceTests {
    @MainActor
    @Test func defaultsReuseConverterFamilyBoundary() {
        #expect(CaseConverterToolWorkspaceModel.synchronousInputByteLimit == 4 * 1024)
        #expect(CaseConverterToolWorkspaceModel.backgroundDebounce == .milliseconds(120))
        #expect(
            CaseConverterToolWorkspaceModel.synchronousInputByteLimit
                == IndexConverterToolWorkspaceModel.defaultSynchronousInputByteLimit
        )
    }

    @MainActor
    @Test func shortInputRendersSynchronouslyExactlyOnce() {
        let counter = LockedStyleRendererRecorder()
        let model = makeModel(
            synchronousInputByteLimit: 64,
            renderer: { input in
                counter.record(input: input)
                return CaseConversion.styles(input)
            }
        )

        model.text = "hello world foo"

        #expect(counter.callCount == 1)
        #expect(counter.ranOnMainThreadValues == [true])
        #expect(model.styles.map(\.label) == [
            "camelCase", "PascalCase", "snake_case", "kebab-case",
            "CONSTANT", "Title Case", "UPPER", "lower"
        ])
        #expect(model.styles.first?.value == "helloWorldFoo")
        #expect(!model.isProcessing)
    }

    @MainActor
    @Test func synchronousBoundaryUsesUTF8ByteCount() {
        let counter = LockedStyleRendererRecorder()
        let model = makeModel(
            synchronousInputByteLimit: 4,
            renderer: { input in
                counter.record(input: input)
                return CaseConversion.styles(input)
            }
        )

        model.text = "éé"

        #expect(model.text.utf8.count == 4)
        #expect(counter.callCount == 1)
        #expect(!model.isProcessing)
    }

    @MainActor
    @Test func largeInputRendersOffMainThreadAndPublishesWhenCurrent() async {
        let counter = LockedStyleRendererRecorder()
        let model = makeModel(
            synchronousInputByteLimit: 4,
            backgroundDebounce: .zero,
            renderer: { input in
                counter.record(input: input, ranOnMainThread: Thread.isMainThread)
                return CaseConversion.styles(input)
            }
        )

        model.text = "ééé"

        #expect(model.text.utf8.count == 6)
        #expect(model.styles.isEmpty)
        #expect(model.isProcessing)

        await waitUntilAssert {
            model.styles.first?.value == "ééé"
        }

        #expect(counter.callCount == 1)
        #expect(counter.ranOnMainThreadValues == [false])
        #expect(!model.isProcessing)
    }

    @MainActor
    @Test func largeInputImmediatelyInvalidatesStaleRows() {
        let model = makeModel(
            synchronousInputByteLimit: 4,
            backgroundDebounce: .seconds(30),
            renderer: CaseConversion.styles
        )

        model.text = "tiny"
        #expect(model.styles.first?.value == "tiny")

        model.text = "larger"

        #expect(model.styles.isEmpty)
        #expect(model.isProcessing)
    }

    @MainActor
    @Test func staleBackgroundResultCannotReplaceNewerInput() async {
        let gate = CaseConversionExecutionGate()
        let model = makeModel(
            synchronousInputByteLimit: 2,
            backgroundDebounce: .zero,
            renderer: CaseConversion.styles,
            backgroundRenderer: { input in
                await gate.execute(input)
            }
        )

        model.text = "old"
        await gate.waitForRequest("old")

        model.text = "newer"
        await gate.waitForRequest("newer")

        await gate.resume("old", with: [
            ("camelCase", "stale"), ("lower", "stale")
        ])
        await Task.yield()

        #expect(model.styles.isEmpty)
        #expect(model.isProcessing)

        await gate.resume("newer", with: CaseConversion.styles("newer"))
        await waitUntilAssert { model.styles.first?.value == "newer" }

        #expect(!model.isProcessing)
    }

    @MainActor
    @Test func clearingTextDropsPendingWorkAndRows() async {
        let gate = CaseConversionExecutionGate()
        let model = makeModel(
            synchronousInputByteLimit: 2,
            backgroundDebounce: .zero,
            renderer: CaseConversion.styles,
            backgroundRenderer: { input in
                await gate.execute(input)
            }
        )

        model.text = "pending"
        await gate.waitForRequest("pending")

        model.text = ""

        #expect(model.text.isEmpty)
        #expect(model.styles.isEmpty)
        #expect(!model.isProcessing)

        await gate.resume("pending", with: CaseConversion.styles("pending"))
        await Task.yield()

        #expect(model.styles.isEmpty)
        #expect(!model.isProcessing)
    }

    // MARK: - Support

    @MainActor
    private func makeModel(
        synchronousInputByteLimit: Int,
        backgroundDebounce: Duration = .milliseconds(120),
        renderer: @escaping CaseConversionStyleRenderer,
        backgroundRenderer: CaseConversionBackgroundRenderer? = nil
    ) -> CaseConverterToolWorkspaceModel {
        CaseConverterToolWorkspaceModel(
            synchronousInputByteLimit: synchronousInputByteLimit,
            backgroundDebounce: backgroundDebounce,
            renderer: renderer,
            backgroundRenderer: backgroundRenderer
        )
    }
}

private final class LockedStyleRendererRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var inputs: [String] = []
    private var mainThreadValues: [Bool] = []

    var callCount: Int {
        lock.withLock { inputs.count }
    }

    var ranOnMainThreadValues: [Bool] {
        lock.withLock { mainThreadValues }
    }

    func record(input: String, ranOnMainThread: Bool = Thread.isMainThread) {
        lock.withLock {
            inputs.append(input)
            mainThreadValues.append(ranOnMainThread)
        }
    }
}

private typealias CaseConversionExecutionGate = TestKeyedAsyncGate<String, [CaseConversionStyleRow]>

