@testable import XTools
import AppKit
import Testing

struct XToolsAppDelegateTests {
    @MainActor
    @Test func settingsNotificationRequestsPresentationWhenMainWindowExists() {
        let window = makeWindow()
        defer { window.close() }

        let delegate = XToolsAppDelegate()
        prepare(delegate)
        defer { tearDown(delegate) }

        let recorder = PresentationRecorder()
        let observer = NotificationCenter.default.addObserver(
            forName: .presentXToolsPreferences,
            object: nil,
            queue: .main
        ) { _ in
            recorder.markPresented()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        NotificationCenter.default.post(name: .openXToolsPreferences, object: nil)

        #expect(recorder.didPresentPreferences)
    }

    @MainActor
    @Test func reopenWithoutWindowsRequestsANewMainWindow() {
        let delegate = XToolsAppDelegate()
        delegate.windowProvider = { [] }
        let recorder = PresentationRecorder()
        delegate.openWindowFallback = { recorder.markPresented() }
        prepare(delegate)
        defer { tearDown(delegate) }

        let reopened = delegate.applicationShouldHandleReopen(
            NSApplication.shared,
            hasVisibleWindows: false
        )

        #expect(reopened)
        #expect(recorder.didPresentPreferences)
    }

    @MainActor
    @Test func preferencesWithoutWindowSetsPendingFlagAndRequestsWindow() {
        let delegate = XToolsAppDelegate()
        delegate.windowProvider = { [] }
        let recorder = PresentationRecorder()
        delegate.openWindowFallback = { recorder.markPresented() }
        prepare(delegate)
        defer { tearDown(delegate) }

        NotificationCenter.default.post(name: .openXToolsPreferences, object: nil)

        #expect(PendingPreferencesPresentation.isPending)
        #expect(recorder.didPresentPreferences)
    }

    @MainActor
    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = "Tools"
        window.orderFront(nil)
        return window
    }

    @MainActor
    private func prepare(_ delegate: XToolsAppDelegate) {
        delegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
    }

    @MainActor
    private func tearDown(_ delegate: XToolsAppDelegate) {
        NotificationCenter.default.removeObserver(delegate)
        PendingPreferencesPresentation.isPending = false
    }
}

private final class PresentationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var presented = false

    func markPresented() {
        lock.lock()
        presented = true
        lock.unlock()
    }

    var didPresentPreferences: Bool {
        lock.lock()
        defer { lock.unlock() }
        return presented
    }
}
