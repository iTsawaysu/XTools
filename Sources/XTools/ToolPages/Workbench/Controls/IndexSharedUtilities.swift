import AppKit
import SwiftUI

// MARK: - IndexDebouncer

/// Trailing debounce for expensive transforms; cancels pending work on re-trigger and deinit.
@MainActor
final class IndexDebouncer: ObservableObject {
    /// 键盘/输入类防抖的统一档位：连续输入合并为一次重算，同时把「停止
    /// 输入 → 结果刷新」保持在可感知延迟以下。此前 180ms / 200ms / 250ms
    /// 散落在 HashText / StringObfuscator / IntegerBase / Crontab /
    /// HTMLToMarkdown 各处，收口到这一个常量防止继续发散。水印的
    /// 90/650ms 双轨有 ADR-0018 依据，不属此档位。
    static let keystrokeDebounce: Duration = .milliseconds(200)

    private var task: Task<Void, Never>?

    func schedule(_ delay: Duration = IndexDebouncer.keystrokeDebounce, _ action: @escaping @MainActor () -> Void) {
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

private struct PageAvailableHeightKey: EnvironmentKey {
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

