import AppKit
import SwiftUI

@MainActor
final class SystemAppearanceSource: ObservableObject {
    @Published private(set) var colorScheme: ColorScheme

    private let application: NSApplication
    private var appearanceObserver: NSKeyValueObservation?

    init(application: NSApplication = .shared) {
        self.application = application
        colorScheme = Self.colorScheme(for: application.effectiveAppearance)
        appearanceObserver = nil
        appearanceObserver = application.observe(
            \.effectiveAppearance,
            options: [.new]
        ) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    deinit {
        if let appearanceObserver {
            appearanceObserver.invalidate()
        }
    }

    func refresh() {
        update(Self.colorScheme(for: application.effectiveAppearance))
    }

    func refresh(using appearance: NSAppearance) {
        update(Self.colorScheme(for: appearance))
    }

    static func resolvedColorScheme(
        preference: AppThemePreference,
        systemColorScheme: ColorScheme
    ) -> ColorScheme {
        preference.colorScheme ?? systemColorScheme
    }

    private static func colorScheme(for appearance: NSAppearance) -> ColorScheme {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }

    private func update(_ newColorScheme: ColorScheme) {
        guard colorScheme != newColorScheme else { return }
        colorScheme = newColorScheme
    }
}

/// Keeps SwiftUI's environment synchronized with the same preference that
/// WindowAppearanceOwner applies to native controls. The explicit system
/// value is necessary because a prior preferredColorScheme override can stay
/// cached in a hosting view after the preference returns to system.
struct AppThemeEnvironment: ViewModifier {
    let preference: AppThemePreference
    @ObservedObject var systemAppearanceSource: SystemAppearanceSource

    func body(content: Content) -> some View {
        content.environment(
            \.colorScheme,
            SystemAppearanceSource.resolvedColorScheme(
                preference: preference,
                systemColorScheme: systemAppearanceSource.colorScheme
            )
        )
    }
}

extension View {
    func appThemeEnvironment(
        preference: AppThemePreference,
        source: SystemAppearanceSource
    ) -> some View {
        modifier(AppThemeEnvironment(preference: preference, systemAppearanceSource: source))
    }
}

/// Applies the app's appearance preference to the window that owns this view.
///
/// SwiftUI's `preferredColorScheme(nil)` changes the environment but does not
/// reliably remove an appearance override that was already installed on an
/// `NSWindow`. Keeping the ownership in one stable AppKit view makes the
/// system case explicit and also covers windows created later (such as a
/// settings sheet).
struct WindowAppearanceOwner: NSViewRepresentable {
    let preference: AppThemePreference

    func makeNSView(context: Context) -> WindowAppearanceOwnerView {
        WindowAppearanceOwnerView(preference: preference)
    }

    func updateNSView(_ nsView: WindowAppearanceOwnerView, context: Context) {
        nsView.preference = preference
    }
}

@MainActor
final class WindowAppearanceOwnerView: NSView {
    var preference: AppThemePreference {
        didSet {
            applyAppearanceIfNeeded()
        }
    }

    init(preference: AppThemePreference) {
        self.preference = preference
        super.init(frame: .zero)
        isHidden = true
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
    }

    required init?(coder: NSCoder) {
        preference = .system
        super.init(coder: coder)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyAppearanceIfNeeded()
    }

    private func applyAppearanceIfNeeded() {
        guard let window else { return }

        trace("before preference=\(preference.rawValue)", window: window)

        switch preference {
        case .system:
            // Clearing the property is essential: assigning nil to the
            // SwiftUI environment alone does not undo NSWindow.appearance.
            if window.appearance != nil {
                window.appearance = nil
            }
        case .light:
            apply(.aqua, to: window)
        case .dark:
            apply(.darkAqua, to: window)
        }

        trace("after preference=\(preference.rawValue)", window: window)
    }

    private func apply(_ name: NSAppearance.Name, to window: NSWindow) {
        guard window.appearance?.name != name else { return }
        window.appearance = NSAppearance(named: name)
    }

    private func trace(_ phase: String, window: NSWindow) {
#if DEBUG
        guard ProcessInfo.processInfo.environment["TOOLS_APPEARANCE_TRACE"] == "1" else { return }

        let windowAppearance = window.appearance?.name.rawValue ?? "nil"
        let windowEffective = window.effectiveAppearance.name.rawValue
        let applicationAppearance = NSApp.appearance?.name.rawValue ?? "nil"
        let applicationEffective = NSApp.effectiveAppearance.name.rawValue
        let viewChain = sequence(first: self as NSView, next: \.superview)
            .map {
                let appearance = $0.appearance?.name.rawValue ?? "nil"
                return "\(type(of: $0))(appearance=\(appearance),effective=\($0.effectiveAppearance.name.rawValue))"
            }
            .joined(separator: " <- ")

        NSLog(
            "[XTools appearance] %@ window=%@ effective=%@ app=%@ appEffective=%@ chain=%@",
            phase,
            windowAppearance,
            windowEffective,
            applicationAppearance,
            applicationEffective,
            viewChain
        )
#else
        _ = phase
        _ = window
#endif
    }
}
