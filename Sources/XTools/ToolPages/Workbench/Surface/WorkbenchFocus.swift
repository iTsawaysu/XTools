import SwiftUI

// MARK: - 工作台焦点契约（阶段③ C3，design.md §4 / PRD 需求 5）

/// 工作台聚焦请求值：壳层把「聚焦第一个输入」作为环境值下发，组件族
/// （IndexTextInput / IndexTextArea / IndexControlledSegmentInput）在请求
/// 变化时走既有 `makeFirstResponder` 通道消费。两个恒等分量：
/// - `generation`：页面代际（`toolPageEntryGeneration`，ToolPageStage 每次
///   到达——含停靠回访——递增，0 = 停靠/失活）。页面出现自动聚焦由它驱动。
/// - `token`：页内主动请求序号（页面 `@State` 持有并递增）。「用作输入」
///   （Base64File）与 ⌘K「别名+空格」直达（Batch D 接入）复用同一 token，
///   不另开聚焦通道。
struct WorkbenchFocusRequest: Equatable {
    let generation: Int
    let token: Int
    /// 壳层直达请求序号（阶段③ Batch D：⌘K「别名+空格」直达回车、SmartPaste
    /// 建议点击、deeplink input）。0 = 本请求不含外部直达载荷；值变化即视为
    /// 一次新的外部请求（写文本 + 聚焦原子完成）。进入请求恒等比较，三族
    /// 消费端无需各自感知新分量。
    var entry: Int = 0
    /// 随本次外部直达请求预填进首位输入的文本（nil = 仅聚焦，不写内容）。
    var entryText: String? = nil

    /// 环境缺省：无活跃请求（generation 0 同时压住停靠页与未接入页面）。
    static let inactive = WorkbenchFocusRequest(generation: 0, token: 0)

    /// 补试预算（三个输入组件族共用）：首次即时 + 3 次 50ms 间隔，覆盖
    /// 窗口挂载与首次布局的就绪延迟（palette 焦点请求同一量级纪律）。
    static let maxFocusAttempts = 4
    /// 补试间隔（秒）。
    static let focusRetryInterval: TimeInterval = 0.05
}

private struct WorkbenchFocusRequestKey: EnvironmentKey {
    static let defaultValue = WorkbenchFocusRequest.inactive
}

private struct WorkbenchFocusTargetKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// 壳层下发的当前聚焦请求（WorkbenchSurface 注入，值 = 页面代际 + 页内 token）。
    var workbenchFocusRequest: WorkbenchFocusRequest {
        get { self[WorkbenchFocusRequestKey.self] }
        set { self[WorkbenchFocusRequestKey.self] = newValue }
    }

    /// 「本组件是页面首个聚焦输入」声明（由 `.workbenchFocusTarget()` 就近
    /// 注入，只被直接包裹的输入组件消费）。声明与请求正交：请求是壳层广播，
    /// 声明决定谁消费。
    var workbenchFocusTarget: Bool {
        get { self[WorkbenchFocusTargetKey.self] }
        set { self[WorkbenchFocusTargetKey.self] = newValue }
    }
}

extension View {
    /// 声明被包裹的输入为页面首个聚焦目标（焦点契约的页面侧标记）。
    /// 合同：每个页面至多一处声明，且必须包裹恰好一个输入组件。
    func workbenchFocusTarget() -> some View {
        environment(\.workbenchFocusTarget, true)
    }
}

// MARK: - 壳层直达载荷（阶段③ Batch D，design.md §7/§8）

/// 壳层向目标工具首位输入的一次性投递载荷：⌘K「别名+空格」直达回车（仅
/// 聚焦）、SmartPaste 建议/deeplink（聚焦 + 预填文本）。`id` 单调递增，是
/// 幂等消费的恒等门控；`toolID` 供 WorkbenchSurface 校验载荷归属，避免
/// 广播环境被无关页面误消费。文本只在投递对象显式动作（点击建议 / deeplink
/// 参数）时携带，驻留内存直至被新投递覆盖或随选择变化作废——不落盘、
/// 不持久化。
struct WorkbenchEntryPayload: Equatable {
    let id: Int
    let toolID: ToolID
    /// 预填文本（nil = 仅聚焦）。
    let text: String?
}

private struct WorkbenchEntryPayloadKey: EnvironmentKey {
    static let defaultValue: WorkbenchEntryPayload? = nil
}

extension EnvironmentValues {
    /// 壳层投递的直达载荷（RootView 注入；WorkbenchSurface 校验 toolID 后
    /// 合并进 `.workbenchFocusRequest`，输入组件族消费）。
    var workbenchEntryPayload: WorkbenchEntryPayload? {
        get { self[WorkbenchEntryPayloadKey.self] }
        set { self[WorkbenchEntryPayloadKey.self] = newValue }
    }
}
