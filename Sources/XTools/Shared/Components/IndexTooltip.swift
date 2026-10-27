import SwiftUI

// MARK: - Tooltip 生命周期

/// 停靠页仍留在视图树里（透明、不可点、AX 隐藏）。SwiftUI 的
/// `allowsHitTesting(false)` 只挡点击，AppKit 的 tooltip 跟踪仍会命中透明
/// 页——鼠标扫过时弹出上一个页面的提示。
///
/// `ToolPageStage` 对非当前页把 `toolInteractionIsLive` 置 false，
/// `indexTooltip` 据此不注册 `.help`。分支切换只改变修饰符链，不改变页面
/// 自身的视图身份：`@State` / `@StateObject` 仍按原位置保留
/// （`ToolPageStageLifecycleTests` 的“停靠页复用同一 StateObject”不受影响）。
private struct ToolInteractionIsLiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var toolInteractionIsLive: Bool {
        get { self[ToolInteractionIsLiveKey.self] }
        set { self[ToolInteractionIsLiveKey.self] = newValue }
    }
}

extension View {
    /// 唯一的 tooltip 入口。
    ///
    /// 视觉气泡只在控件没有可见文字时才注册：图标按钮需要它说明动作，
    /// 文字按钮本身已经把动作写在脸上，再弹一条同义气泡只是噪音。
    /// AX 提示始终发布——读屏用户看不到按钮旁的上下文，需要它。
    ///
    /// - Parameters:
    ///   - text: 提示文案；空串或纯空白视为没有提示。
    ///   - wantsVisibleBubble: 是否允许鼠标悬停气泡，仅图标控件传 true。
    @ViewBuilder
    func indexTooltip(_ text: String?, wantsVisibleBubble: Bool = true) -> some View {
        modifier(IndexTooltipModifier(text: text, wantsVisibleBubble: wantsVisibleBubble))
    }
}

private struct IndexTooltipModifier: ViewModifier {
    let text: String?
    let wantsVisibleBubble: Bool
    @Environment(\.toolInteractionIsLive) private var isLive

    private var resolved: String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : text
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if let resolved {
            if wantsVisibleBubble && isLive {
                content.help(resolved).accessibilityHint(resolved)
            } else {
                // 停靠页不发气泡；文字控件也不发。AX 提示继续发布。
                content.accessibilityHint(resolved)
            }
        } else {
            content
        }
    }
}
