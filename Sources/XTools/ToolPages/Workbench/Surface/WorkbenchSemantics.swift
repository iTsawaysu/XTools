import Foundation

// MARK: - 新壳行为契约转发（design.md §1 / §7 保留能力 3）

/// 统一壳 `WorkbenchSurface` 的滚动归属翻译层：包装既有
/// `IndexWorkspaceSemantic` → `IndexWorkspaceBehaviorContract` 四布尔，不新建
/// 语义体系（workbench-audit ⑤-3 是硬保留能力）。
///
/// 宿主用法：
/// 1. 页面照旧向 `IndexPage(workspaceSemantic:)` 声明工作区语义；
/// 2. 壳内容按需用本类型转发四布尔，选择输入/输出面的呈现方式
///    （输入随内容增高 / 输出内部滚动 / 长 token 换行 / 自然高度面板）；
/// 3. 语义翻译层 `IndexWorkspaceSurfaces` 继续服务，本类型只做命名收口，
///    保证阶段②迁移不改变任何页面的滚动归属。
///
/// 四布尔含义见 `IndexWorkspaceBehaviorContract` 逐字段注释；新壳调用点
/// 不得绕过本类型直接 switch `IndexWorkspaceSemantic`。
struct WorkbenchSemantics: Equatable {
    /// 被转发的工作区语义（唯一事实来源）。
    let semantic: IndexWorkspaceSemantic

    init(_ semantic: IndexWorkspaceSemantic) {
        self.semantic = semantic
    }

    /// 行为契约本体（四布尔 + 可组合转发给语义翻译层）。
    var behavior: IndexWorkspaceBehaviorContract {
        semantic.behavior
    }

    /// 输入随内容自然增高（否则固定高度）。
    var inputExpandsWithContent: Bool {
        behavior.inputExpandsWithContent
    }

    /// 输出面在自身内部滚动（否则交给页面级滚动）。
    var outputScrollsInternally: Bool {
        behavior.outputScrollsInternally
    }

    /// 超长 token 按可用宽度逐字符换行（否则保留控件默认）。
    var wrapsLongTokensToAvailableWidth: Bool {
        behavior.wrapsLongTokensToAvailableWidth
    }

    /// 结果面板按内容自然高度呈现（否则填充可用空间）。
    var usesNaturalHeightSurface: Bool {
        behavior.usesNaturalHeightSurface
    }
}
