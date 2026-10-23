import CoreGraphics
import Testing
@testable import XTools

/// 统一壳诊断单轨聚合契约（design.md §4 / §9）：壳消费
/// `IndexWorkspaceDiagnosticPreferenceKey` 的优先级合并与
/// `IndexWorkspaceDiagnosticPresentationState` 的播报门控（壳私有持有的
/// 诊断三件套就是这两个共享类型 + toastCenter，本套锚定其聚合行为，
/// 模式对齐既有 WorkspacePayload 状态测试）。参数注入轨不进入新壳，
/// 因此聚合语义只此一处。
@Suite
struct WorkbenchSurfaceDiagnosticTests {
    private func payload(
        _ text: String,
        tone: ToolFeedbackTone,
        maxWidth: CGFloat = 460
    ) -> IndexWorkspaceDiagnosticPayload {
        IndexWorkspaceDiagnosticPayload(text: text, tone: tone, maxWidth: maxWidth)
    }

    private func reduce(
        _ first: IndexWorkspaceDiagnosticPayload?,
        _ second: IndexWorkspaceDiagnosticPayload?
    ) -> IndexWorkspaceDiagnosticPayload? {
        var value = first
        IndexWorkspaceDiagnosticPreferenceKey.reduce(value: &value) { second }
        return value
    }

    // MARK: - preference 聚合（tone 优先级合并）

    @Test func reduceKeepsErrorOverWarningRegardlessOfTraversalOrder() {
        let error = payload("时间格式无法解析", tone: .error)
        let warning = payload("世纪写法不唯一", tone: .warning)

        #expect(reduce(error, warning) == error)
        #expect(reduce(warning, error) == error)
    }

    @Test func reduceLetsLowerSeverityNeverReplaceHigherSeverity() {
        let error = payload("输入不是合法 Base64", tone: .error)
        let info = payload("已切换到解码方向", tone: .info)
        let success = payload("转换完成", tone: .success)

        #expect(reduce(error, info) == error)
        #expect(reduce(error, success) == error)
        #expect(reduce(nil, info) == info)
    }

    @Test func reduceNeverReplacesWithNil() {
        let warning = payload("仅预览前 5000 个字符", tone: .warning)
        #expect(reduce(warning, nil) == warning)
        #expect(reduce(nil, nil) == nil)
    }

    // MARK: - 播报门控（变化才播报 toast）

    @Test func updateAnnouncesAbsentToPresentTransition() {
        var state = IndexWorkspaceDiagnosticPresentationState()
        #expect(state.current == nil)

        let announcement = state.update(to: payload("时间格式无法解析", tone: .error))
        #expect(announcement?.text == "时间格式无法解析")
        #expect(state.current?.tone == .error)
    }

    @Test func updateSuppressesIdenticalPayloads() {
        var state = IndexWorkspaceDiagnosticPresentationState()
        let diagnostic = payload("时间格式无法解析", tone: .error)
        _ = state.update(to: diagnostic)

        #expect(state.update(to: diagnostic) == nil)
        #expect(state.current == diagnostic)
    }

    @Test func updateReAnnouncesSameSeverityTextChanges() {
        var state = IndexWorkspaceDiagnosticPresentationState()
        _ = state.update(to: payload("第 3 行语法错误", tone: .error))

        // 「变化才播报」（workbench-audit ⑤-1）：同 severity 换文案属于
        // 变化，会再播报一条 toast；只有完全相同的 payload 才静默。
        let replacement = payload("第 7 行语法错误", tone: .error)
        #expect(state.update(to: replacement) == replacement)
        #expect(state.current == replacement)
    }

    @Test func updateAnnouncesSeverityEscalation() {
        var state = IndexWorkspaceDiagnosticPresentationState()
        _ = state.update(to: payload("世纪写法不唯一", tone: .warning))

        let escalated = payload("时间格式无法解析", tone: .error)
        #expect(state.update(to: escalated) == escalated)
        #expect(state.current?.tone == .error)
    }

    @Test func updateSuppressesSeverityDeEscalationButKeepsNewText() {
        var state = IndexWorkspaceDiagnosticPresentationState()
        _ = state.update(to: payload("时间格式无法解析", tone: .error))

        let softened = payload("世纪写法不唯一", tone: .warning)
        #expect(state.update(to: softened) == nil)
        // 降级不播报，但当前诊断跟随最新文案。
        #expect(state.current == softened)
    }

    @Test func clearingResetsTheAnnouncementGate() {
        var state = IndexWorkspaceDiagnosticPresentationState()
        _ = state.update(to: payload("时间格式无法解析", tone: .error))

        #expect(state.update(to: nil) == nil)
        #expect(state.current == nil)

        // 清除后新诊断（即使severity更低）重新播报一次。
        let next = payload("世纪写法不唯一", tone: .warning)
        #expect(state.update(to: next) == next)
        #expect(state.current == next)
    }
}
