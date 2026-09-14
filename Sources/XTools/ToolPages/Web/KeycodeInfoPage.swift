import XToolsCore
import SwiftUI

@MainActor
final class KeycodeToolWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<KeycodeToolWorkspaceModel>(toolID: "keycode-info") { _ in
        KeycodeToolWorkspaceModel()
    }

    @Published var snapshot: KeyboardEventSnapshot?
}

struct IndexKeycodePage: View {
    var body: some View {
        ToolWorkspaceHost(key: KeycodeToolWorkspaceModel.key) { workspace, _ in
            IndexKeycodeWorkspaceContent(workspace: workspace)
        }
    }
}

private struct IndexKeycodeWorkspaceContent: View {
    @ObservedObject var workspace: KeycodeToolWorkspaceModel
    @State private var isListening = false
    @State private var focusRequestToken = 0

    private let captureCardHeight: CGFloat = 152

    private func resultRows(for snapshot: KeyboardEventSnapshot) -> [(String, String, Color?)] {
        [
            ("事件类型", eventTypeDisplay(snapshot.kind), nil),
            ("event.key", webKeyDisplay(snapshot.webKey), nil),
            ("event.code", snapshot.webCode, nil),
            ("event.location", snapshot.location.displayText, nil),
            ("修饰键", snapshot.modifiers.displayText, nil),
            ("重复事件", snapshot.isRepeat ? "是" : "否", nil),
            ("macOS keyCode", "\(snapshot.keyCode)", nil)
        ]
    }

    private var captureAccessibilitySummary: String {
        guard let snapshot = workspace.snapshot else {
            return "暂无按键结果"
        }
        return "最近事件：\(eventTypeDisplay(snapshot.kind))，\(snapshot.displayKey)，event.code \(snapshot.webCode)"
    }

    private var latestEventResult: some View {
        IndexWorkspaceResultSurface(workspaceSemantic: .naturalHeightShortResultPanel) {
            IndexResultPresence(
                value: workspace.snapshot,
                updateID: workspace.snapshot
            ) { snapshot in
                IndexKVSurface {
                    VStack(spacing: 1) {
                        ForEach(Array(resultRows(for: snapshot).enumerated()), id: \.offset) { _, row in
                            resultRow(row)
                        }
                    }
                }
            } empty: {
                IndexKV(
                    rows: [],
                    emptyText: "等待按键…",
                    copyable: true,
                    valueLineBreakMode: .byCharWrapping,
                    valueMotion: .immediate
                )
            }
        }
    }

    private func resultRow(_ row: (String, String, Color?)) -> some View {
        IndexKVRow(
            key: row.0,
            value: row.1,
            color: row.2,
            copyable: true,
            valueLineBreakMode: .byCharWrapping,
            valueMotion: .immediate
        )
    }

    private func eventTypeDisplay(_ kind: KeyboardEventKind) -> String {
        "\(kind.rawValue) · \(kind.displayName)"
    }

    var body: some View {
        IndexPage(
            "键盘事件",
            subtitle: "根据本机按键事件推导对应的 Web KeyboardEvent 字段。",
            workspaceSemantic: .fixedInputWorkspace
        ) {
            captureCard

            IndexPanel("最近事件") {
                latestEventResult
            }
        }
        .onAppear {
            focusRequestToken &+= 1
        }
    }

    private var captureCard: some View {
        ZStack {
            KeyCaptureRepresentable(
                isListening: $isListening,
                focusRequestToken: focusRequestToken,
                accessibilitySummary: captureAccessibilitySummary,
                onEvent: handleEvent
            )

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(isListening ? ToolTheme.success : ToolTheme.textSecondary)
                        .frame(width: 8, height: 8)
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(isListening ? "正在监听" : "监听已暂停")
                            .font(ToolTypography.bodyMedium)
                            .foregroundStyle(ToolTheme.textPrimary)
                        Text(isListening ? "按下任意键；Esc 结束监听" : "点击此区域继续监听")
                            .font(ToolTypography.caption)
                            .foregroundStyle(ToolTheme.textSecondary)
                    }

                    Spacer(minLength: 12)

                    if isListening {
                        IndexBadge("Esc 停止", tone: .neutral)
                    }
                }

                Text(workspace.snapshot?.displayKey ?? "按下任意键")
                    .font(ToolTypography.heroValue)
                    .foregroundStyle(workspace.snapshot == nil ? ToolTheme.textSecondary : ToolTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .frame(maxWidth: .infinity, alignment: .center)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        IndexBadge("Control", tone: workspace.snapshot?.modifiers.control == true ? .accent : .neutral)
                        IndexBadge("Shift", tone: workspace.snapshot?.modifiers.shift == true ? .accent : .neutral)
                        IndexBadge("Option", tone: workspace.snapshot?.modifiers.option == true ? .accent : .neutral)
                        IndexBadge("Command", tone: workspace.snapshot?.modifiers.command == true ? .accent : .neutral)
                        IndexBadge("Caps Lock", tone: workspace.snapshot?.modifiers.capsLock == true ? .accent : .neutral)
                        IndexBadge("Fn", tone: workspace.snapshot?.modifiers.function == true ? .accent : .neutral)
                    }

                    IndexFlowLayout(spacing: 6, lineSpacing: 6) {
                        IndexBadge("Control", tone: workspace.snapshot?.modifiers.control == true ? .accent : .neutral)
                        IndexBadge("Shift", tone: workspace.snapshot?.modifiers.shift == true ? .accent : .neutral)
                        IndexBadge("Option", tone: workspace.snapshot?.modifiers.option == true ? .accent : .neutral)
                        IndexBadge("Command", tone: workspace.snapshot?.modifiers.command == true ? .accent : .neutral)
                        IndexBadge("Caps Lock", tone: workspace.snapshot?.modifiers.capsLock == true ? .accent : .neutral)
                        IndexBadge("Fn", tone: workspace.snapshot?.modifiers.function == true ? .accent : .neutral)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(ToolMetrics.Spacing.base)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .frame(height: captureCardHeight)
        .background(ToolTheme.editorBackground, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                .strokeBorder(isListening ? ToolTheme.focusRing : ToolTheme.strongBorder, lineWidth: isListening ? 1.5 : 0.5)
        }
        .toolAnimation(ToolMotion.Preset.controlFeedback, value: isListening)
    }

    

    private func handleEvent(_ input: KeyboardEventInput) {
        workspace.snapshot = KeycodeMapper.snapshot(for: input)
    }

    private func webKeyDisplay(_ key: String) -> String {
        key == " " ? "\" \"（空格）" : key
    }
}

fileprivate struct KeyCaptureRepresentable: NSViewRepresentable {
    @Binding var isListening: Bool
    let focusRequestToken: Int
    let accessibilitySummary: String
    let onEvent: (KeyboardEventInput) -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.isListening = $isListening
        view.onEvent = onEvent
        view.accessibilitySummary = accessibilitySummary
        view.configureAccessibility()
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.isListening = $isListening
        nsView.onEvent = onEvent
        nsView.accessibilitySummary = accessibilitySummary
        nsView.configureAccessibility()
        nsView.requestInitialFocus(token: focusRequestToken)
    }
}

fileprivate final class KeyCaptureNSView: NSView {
    private enum InitialFocusAttempt {
        case focused
        case deferredUntilWindowIsKey
        case blockedByActiveTextInput
    }

    var isListening: Binding<Bool>?
    var onEvent: ((KeyboardEventInput) -> Void)?
    var accessibilitySummary = "暂无按键结果"

    private let initialFocusRetryDelays: [TimeInterval] = [0.05, ToolMotion.Duration.fast + 0.05]
    private var processedInitialFocusToken = 0
    private var initialFocusRequestGeneration = 0
    private var pendingInitialFocusGeneration: Int?

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureAccessibility()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureAccessibility()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )

        guard let window else {
            cancelInitialFocusRequests()
            updateListening(false)
            return
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            updateListening(true)
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            updateListening(false)
        }
        return resigned
    }

    override func mouseDown(with event: NSEvent) {
        cancelInitialFocusRequests()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        onEvent?(input(from: event, kind: .keyDown))

        if event.keyCode == 0x35 {
            cancelInitialFocusRequests()
            window?.makeFirstResponder(nil)
        }
    }

    override func flagsChanged(with event: NSEvent) {
        onEvent?(input(from: event, kind: .modifierFlagsChanged))
    }

    override func accessibilityPerformPress() -> Bool {
        cancelInitialFocusRequests()
        window?.makeFirstResponder(self)
        return window?.firstResponder === self
    }

    func requestInitialFocus(token: Int) {
        guard token > 0, processedInitialFocusToken != token else { return }
        processedInitialFocusToken = token
        initialFocusRequestGeneration &+= 1
        let generation = initialFocusRequestGeneration
        pendingInitialFocusGeneration = generation

        for (index, delay) in initialFocusRetryDelays.enumerated() {
            let isFinalAttempt = index == initialFocusRetryDelays.count - 1
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self,
                      self.pendingInitialFocusGeneration == generation else { return }

                let outcome = self.attemptInitialFocus()
                if isFinalAttempt, outcome != .deferredUntilWindowIsKey {
                    self.pendingInitialFocusGeneration = nil
                }
            }
        }
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard pendingInitialFocusGeneration != nil else { return }

        switch attemptInitialFocus() {
        case .focused, .blockedByActiveTextInput:
            pendingInitialFocusGeneration = nil
        case .deferredUntilWindowIsKey:
            break
        }
    }

    func configureAccessibility() {
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("键盘事件捕获")
        setAccessibilityHelp("按下按键查看事件；按 Escape 停止监听，点击此区域恢复监听。")
        let state = isListening?.wrappedValue == true ? "正在监听" : "未监听"
        let accessibilityValue = "\(state)。\(accessibilitySummary)"
        setAccessibilityValue(accessibilityValue)
    }

    private func updateListening(_ value: Bool) {
        if isListening?.wrappedValue != value {
            isListening?.wrappedValue = value
        }
        configureAccessibility()
    }

    private func cancelInitialFocusRequests() {
        initialFocusRequestGeneration &+= 1
        pendingInitialFocusGeneration = nil
    }

    private func attemptInitialFocus() -> InitialFocusAttempt {
        guard let window, window.isKeyWindow else {
            return .deferredUntilWindowIsKey
        }

        if let responderView = window.firstResponder as? NSView,
           responderView !== self,
           responderView.window === window,
           responderView is NSTextView || responderView is NSTextField {
            return .blockedByActiveTextInput
        }

        return window.makeFirstResponder(self) ? .focused : .blockedByActiveTextInput
    }

    private func input(from event: NSEvent, kind: KeyboardEventKind) -> KeyboardEventInput {
        KeyboardEventInput(
            kind: kind,
            keyCode: event.keyCode,
            characters: event.characters,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifiers: KeyboardModifierState(
                control: event.modifierFlags.contains(.control),
                shift: event.modifierFlags.contains(.shift),
                option: event.modifierFlags.contains(.option),
                command: event.modifierFlags.contains(.command),
                capsLock: event.modifierFlags.contains(.capsLock),
                function: event.modifierFlags.contains(.function)
            ),
            isRepeat: event.isARepeat
        )
    }
}
