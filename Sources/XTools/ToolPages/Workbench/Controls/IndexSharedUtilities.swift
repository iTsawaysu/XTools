import AppKit
import SwiftUI

// MARK: - IndexDebouncer

/// Trailing debounce for expensive transforms; cancels pending work on re-trigger and deinit.
@MainActor
final class IndexDebouncer: ObservableObject {
    private var task: Task<Void, Never>?

    func schedule(_ delay: Duration = .milliseconds(200), _ action: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
}

// MARK: - Environment Key

struct PageAvailableHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 600
}

extension EnvironmentValues {
    var pageAvailableHeight: CGFloat {
        get { self[PageAvailableHeightKey.self] }
        set { self[PageAvailableHeightKey.self] = newValue }
    }
}

// MARK: - Helper Functions

func indexWrappingAttributedText(_ value: String, lineBreakMode: NSLineBreakMode) -> AttributedString {
    indexWrappingAttributedText(AttributedString(value), lineBreakMode: lineBreakMode)
}

func indexWrappingAttributedText(_ value: AttributedString, lineBreakMode: NSLineBreakMode) -> AttributedString {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineBreakMode = lineBreakMode

    let attributed = NSMutableAttributedString(attributedString: NSAttributedString(value))
    attributed.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: attributed.length))
    return AttributedString(attributed)
}

