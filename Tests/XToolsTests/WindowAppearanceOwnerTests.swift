@testable import XTools
import AppKit
import SwiftUI
import Testing

struct WindowAppearanceOwnerTests {
    @MainActor
    @Test func systemAppearanceSourceMapsNativeAppearanceAndCanBeInjected() {
        let source = SystemAppearanceSource()
        guard let darkAppearance = NSAppearance(named: .darkAqua),
              let lightAppearance = NSAppearance(named: .aqua) else {
            Issue.record("Unable to create standard NSAppearance values")
            return
        }

        source.refresh(using: darkAppearance)
        #expect(source.colorScheme == .dark)
        source.refresh(using: lightAppearance)
        #expect(source.colorScheme == .light)
        #expect(SystemAppearanceSource.resolvedColorScheme(
            preference: .system,
            systemColorScheme: source.colorScheme
        ) == .light)
        #expect(SystemAppearanceSource.resolvedColorScheme(
            preference: .light,
            systemColorScheme: .dark
        ) == .light)
        #expect(SystemAppearanceSource.resolvedColorScheme(
            preference: .dark,
            systemColorScheme: .light
        ) == .dark)
    }

    @MainActor
    @Test func systemAppearanceSourceRefreshesFromApplicationKVO() async {
        let source = SystemAppearanceSource()
        let previousAppearance = NSApp.appearance
        defer { NSApp.appearance = previousAppearance }

        let targetName: NSAppearance.Name = source.colorScheme == .dark ? .aqua : .darkAqua
        let expected: ColorScheme = targetName == .darkAqua ? .dark : .light
        NSApp.appearance = NSAppearance(named: targetName)
        await Self.wait(until: { source.colorScheme == expected })
        #expect(source.colorScheme == expected)
    }

    @MainActor
    @Test func hostingViewEnvironmentFollowsSystemAndKeepsFixedPreference() async {
        let source = SystemAppearanceSource()
        guard let lightAppearance = NSAppearance(named: .aqua),
              let darkAppearance = NSAppearance(named: .darkAqua) else {
            Issue.record("Unable to create standard NSAppearance values")
            return
        }
        source.refresh(using: lightAppearance)

        let recorder = ColorSchemeRecorder()
        let window = Self.window()
        let hostingView = NSHostingView(
            rootView: Self.probe(recorder: recorder, preference: .dark, source: source)
        )
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        await Self.wait(until: { recorder.value == .dark })
        #expect(recorder.value == .dark)

        hostingView.rootView = Self.probe(recorder: recorder, preference: .system, source: source)
        hostingView.layoutSubtreeIfNeeded()
        await Self.wait(until: { recorder.value == .light })
        #expect(recorder.value == .light)

        source.refresh(using: darkAppearance)
        await Self.wait(until: { recorder.value == .dark })
        #expect(recorder.value == .dark)

        hostingView.rootView = Self.probe(recorder: recorder, preference: .light, source: source)
        hostingView.layoutSubtreeIfNeeded()
        await Self.wait(until: { recorder.value == .light })
        source.refresh(using: lightAppearance)
        try? await Task.sleep(for: .milliseconds(10))
        source.refresh(using: darkAppearance)
        hostingView.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(10))
        #expect(recorder.value == .light)
    }

    @MainActor
    @Test func systemPreferenceClearsAnExistingWindowOverride() {
        let window = Self.window()
        window.appearance = NSAppearance(named: .darkAqua)
        let owner = WindowAppearanceOwnerView(preference: .system)
        window.contentView?.addSubview(owner)

        #expect(window.appearance == nil)
    }

    @MainActor
    @Test func latestPreferenceIsAppliedWhenTheOwnerIsMounted() {
        let window = Self.window()
        let owner = WindowAppearanceOwnerView(preference: .dark)
        owner.preference = .light
        window.contentView?.addSubview(owner)

        #expect(window.appearance?.name == .aqua)
    }

    @MainActor
    @Test func ownersControlOnlyTheirOwnWindows() {
        let lightWindow = Self.window()
        let darkWindow = Self.window()
        lightWindow.contentView?.addSubview(WindowAppearanceOwnerView(preference: .light))
        darkWindow.contentView?.addSubview(WindowAppearanceOwnerView(preference: .dark))

        #expect(lightWindow.appearance?.name == .aqua)
        #expect(darkWindow.appearance?.name == .darkAqua)
    }

    @MainActor
    @Test func rootHostingViewUsesTheWindowAppearanceOwnerForThemeChanges() {
        let suiteName = "WindowAppearanceOwnerTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(AppThemePreference.dark.rawValue, forKey: "dt.theme")
        let window = Self.window()
        let hostingView = NSHostingView(rootView: RootView(defaults: defaults))
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()

        #expect(window.appearance?.name == .darkAqua)

        defaults.set(AppThemePreference.system.rawValue, forKey: "dt.theme")
        hostingView.rootView = RootView(defaults: defaults)
        hostingView.layoutSubtreeIfNeeded()

        #expect(window.appearance == nil)
    }

    @MainActor
    private static func window() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
    }

    @MainActor
    private static func wait(until condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @MainActor
    private static func probe(
        recorder: ColorSchemeRecorder,
        preference: AppThemePreference,
        source: SystemAppearanceSource
    ) -> some View {
        ColorSchemeProbe(recorder: recorder)
            .appThemeEnvironment(preference: preference, source: source)
    }
}

@MainActor
private final class ColorSchemeRecorder: ObservableObject {
    var value: ColorScheme?
}

@MainActor
private struct ColorSchemeProbe: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var recorder: ColorSchemeRecorder

    var body: some View {
        Color.clear
            .onAppear { recorder.value = colorScheme }
            .task(id: colorScheme) {
                recorder.value = colorScheme
            }
    }
}
