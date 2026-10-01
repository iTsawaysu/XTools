import AppKit
import SwiftUI

/// ENV-gated forensic autopilot for the command palette (never active in
/// normal launches). `XTOOLS_PALETTE_AUTOPILOT=<scenario>` drives the palette
/// through the app's real presentation and input paths so an external 60fps
/// capture (capstream3) can exercise the true user arc: open, field-editor
/// typing, backspace clearing, and Escape closing.
///
/// Open/close go through the same `RootViewModel.toggleCommandPalette` entry
/// the ⌘K menu item and the toolbar button share, wrapped in the same
/// `ToolMotion.Preset.modal` transaction as
/// `RootView.toggleCommandPaletteAnimated`. The ⌘K menu shortcut itself cannot
/// be driven from a background-launched process: synthesized key events
/// (`NSApp.postEvent`, `mainMenu.performKeyEquivalent`, `CGEvent.postToPid`)
/// all reach the menu — which claims the equivalent — but the SwiftUI command
/// action stays a no-op because `@FocusedObject` never resolves while the app
/// cannot come frontmost. Typing, clearing, and Escape still ride real
/// NSEvents through `NSApp.sendEvent` → key window → field editor, the exact
/// dispatch path user keystrokes take.
///
/// Scenarios:
///   toggle      — repeated open / esc close cycles
///   clearsearch — open, type a short garbage query, clear it, close
///   open        — slow open/close dwell cycles
/// `XTOOLS_PALETTE_AUTOPILOT_CYCLES` bounds the repeat count (default 10).
@MainActor
enum CommandPaletteAutopilot {
    private static weak var viewModel: RootViewModel?

    /// The configured scenario — non-nil only when the env var exists **and**
    /// is non-empty. Both attach and start gate on this so an empty value can
    /// never half-activate the autopilot (e.g. attach without start).
    private static var configuredScenario: String? {
        guard let value = ProcessInfo.processInfo.environment["XTOOLS_PALETTE_AUTOPILOT"],
              !value.isEmpty
        else { return nil }
        return value
    }

    /// Called from `RootView.onAppear`: the palette entry lives on the root
    /// view model, which only exists once the scene mounts.
    static func attachIfRequested(_ model: RootViewModel) {
        guard configuredScenario != nil else { return }
        viewModel = model
        log("viewModel attached")
    }

    static func startIfRequested() {
        guard let scenario = configuredScenario else { return }
        let cycles = Int(ProcessInfo.processInfo.environment["XTOOLS_PALETTE_AUTOPILOT_CYCLES"] ?? "") ?? 10
        log("autopilot start scenario=\(scenario) cycles=\(cycles)")
        Task { @MainActor in
            prepareWindow()
            try? await Task.sleep(for: .seconds(1.5))
            switch scenario {
            case "toggle": await toggle(cycles: cycles)
            case "clearsearch": await clearSearch(cycles: cycles)
            case "open": await openSlow(cycles: cycles)
            default: log("autopilot unknown scenario=\(scenario)")
            }
            log("autopilot done")
        }
    }

    /// Park the main window at a deterministic frame so the external capture
    /// region is stable, then bring the app forward.
    private static func prepareWindow() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        let frame = CGRect(x: 300, y: 200, width: 1200, height: 800)
        if let window = NSApp.windows.first(where: { $0.title == "Tools" }) ?? NSApp.keyWindow ?? NSApp.windows.first {
            window.setFrame(frame, display: true)
            window.makeKeyAndOrderFront(nil)
            log(String(format: "autopilot window frame %.0f,%.0f %.0fx%.0f isActive=%@", frame.origin.x, frame.origin.y, frame.width, frame.height, NSApp.isActive ? "true" : "false"))
        }
    }

    private static func toggle(cycles: Int) async {
        for cycle in 0..<cycles {
            log("cycle=\(cycle) cmdK")
            openToggle()
            try? await Task.sleep(for: .seconds(0.9))
            log("cycle=\(cycle) esc")
            postEscape()
            try? await Task.sleep(for: .seconds(0.9))
        }
    }

    private static func clearSearch(cycles: Int) async {
        for cycle in 0..<cycles {
            log("cycle=\(cycle) cmdK")
            openToggle()
            try? await Task.sleep(for: .seconds(0.8))
            log("cycle=\(cycle) type")
            for ch in "zxq" {
                postCharacter(ch)
                try? await Task.sleep(for: .seconds(0.06))
            }
            try? await Task.sleep(for: .seconds(0.7))
            log("cycle=\(cycle) clear")
            for _ in 0..<3 {
                postBackspace()
                try? await Task.sleep(for: .seconds(0.06))
            }
            try? await Task.sleep(for: .seconds(0.7))
            log("cycle=\(cycle) esc")
            postEscape()
            try? await Task.sleep(for: .seconds(0.7))
        }
    }

    private static func openSlow(cycles: Int) async {
        for cycle in 0..<cycles {
            log("cycle=\(cycle) cmdK")
            openToggle()
            try? await Task.sleep(for: .seconds(1.4))
            log("cycle=\(cycle) esc")
            postEscape()
            try? await Task.sleep(for: .seconds(0.6))
        }
    }

    // MARK: - Presentation entry (shared with user triggers)

    /// The exact presentation entry the ⌘K menu item and the toolbar button
    /// share (`RootView.toggleCommandPaletteAnimated`).
    ///
    /// The scenario task can start before `RootView.onAppear` attaches the
    /// view model (attach race). Until then, skip the beat — the cycle loop
    /// naturally retries the next beat, so no busy wait is needed.
    private static func openToggle() {
        guard viewModel != nil else {
            if !didLogAttachWait {
                didLogAttachWait = true
                log("viewModel not attached yet; skipping beats until attach")
            }
            return
        }
        if didLogAttachWait {
            didLogAttachWait = false
            log("viewModel attached; resuming scenario")
        }
        withToolAnimation(ToolMotion.Preset.modal) {
            viewModel?.toggleCommandPalette()
        }
        log("cmdK toggle dispatched")
    }

    private static var didLogAttachWait = false

    // MARK: - Key event synthesis

    private static func keyEvent(
        _ type: NSEvent.EventType,
        keyCode: UInt16,
        characters: String,
        charactersIgnoringModifiers: String,
        modifiers: NSEvent.ModifierFlags
    ) -> NSEvent? {
        NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: NSApp.keyWindow?.windowNumber ?? 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            isARepeat: false,
            keyCode: keyCode
        )
    }

    private static func post(_ event: NSEvent?) {
        guard let event else {
            // Synthesis can fail (e.g. no key window yet); skip this beat
            // instead of crashing the forensic driver.
            log("key event synthesis failed; beat skipped")
            return
        }
        NSApp.postEvent(event, atStart: false)
    }

    private static func postEscape() {
        post(keyEvent(.keyDown, keyCode: 53, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", modifiers: []))
        post(keyEvent(.keyUp, keyCode: 53, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", modifiers: []))
    }

    private static func postCharacter(_ ch: Character) {
        let s = String(ch)
        let code = Self.keyCodeMap[ch] ?? 0
        post(keyEvent(.keyDown, keyCode: code, characters: s, charactersIgnoringModifiers: s, modifiers: []))
        post(keyEvent(.keyUp, keyCode: code, characters: s, charactersIgnoringModifiers: s, modifiers: []))
    }

    private static func postBackspace() {
        post(keyEvent(.keyDown, keyCode: 51, characters: "\u{7f}", charactersIgnoringModifiers: "\u{7f}", modifiers: []))
        post(keyEvent(.keyUp, keyCode: 51, characters: "\u{7f}", charactersIgnoringModifiers: "\u{7f}", modifiers: []))
    }

    private static let keyCodeMap: [Character: UInt16] = [
        "z": 6, "x": 7, "q": 12, "k": 40,
    ]

    private static func log(_ line: String) {
        FileHandle.standardError.write(Data("AUTOPILOT t=\(String(format: "%.4f", Date().timeIntervalSince1970)) \(line)\n".utf8))
    }
}
