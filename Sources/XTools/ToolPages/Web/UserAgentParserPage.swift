import XToolsCore
import SwiftUI
import XToolsDesign

@MainActor
final class UserAgentToolWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<UserAgentToolWorkspaceModel>(toolID: "useragent-parser") { _ in
        UserAgentToolWorkspaceModel()
    }

    @Published var input = ""
    @Published private(set) var result: UserAgentParser.Result?
    @Published private(set) var error: String?

    var browser: String { result?.browser ?? "" }
    var browserVersion: String { result?.browserVersion ?? "" }
    var os: String { result?.os ?? "" }
    var osVersion: String { result?.osVersion ?? "" }
    var device: String { result?.device ?? "" }

    var hasAnyContent: Bool {
        !input.isEmpty
            || result != nil
            || error != nil
    }

    func clear() {
        input = ""
        result = nil
        error = nil
    }

    func parse() {
        error = nil
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            result = nil
            return
        }

        guard let parsed = UserAgentParser.parse(trimmed) else {
            result = nil
            error = userAgentErrorMessage(for: UserAgentParser.validationIssue(trimmed))
            return
        }

        result = parsed
    }

    private func userAgentErrorMessage(for issue: UserAgentParser.ValidationIssue?) -> String {
        issue?.errorDescription ?? "User-Agent 结构无效。"
    }
}

struct IndexUserAgentParserPage: View {
    var body: some View {
        ToolWorkspaceHost(key: UserAgentToolWorkspaceModel.key) { workspace, _ in
            IndexUserAgentWorkspaceContent(workspace: workspace)
        }
    }
}

private struct IndexUserAgentWorkspaceContent: View {
    private struct ResultProjection {
        let browser: String
        let browserVersion: String
        let os: String
        let osVersion: String
        let device: String

        var updateID: [String] {
            [browser, browserVersion, os, osVersion, device]
        }
    }

    @ObservedObject var workspace: UserAgentToolWorkspaceModel

    private var resultProjection: ResultProjection? {
        guard !workspace.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let result = workspace.result else {
            return nil
        }

        return ResultProjection(
            browser: result.browser,
            browserVersion: result.browserVersion,
            os: result.os,
            osVersion: result.osVersion,
            device: result.device
        )
    }

    private var resultPresenceUpdateID: [String] {
        resultProjection?.updateID ?? []
    }

    private var rows: [IndexResultKVItem] {
        guard let projection = resultProjection else { return [] }
        return [
            IndexResultKVItem(key: "浏览器", value: projection.browser),
            IndexResultKVItem(key: "浏览器版本", value: projection.browserVersion),
            IndexResultKVItem(key: "操作系统", value: projection.os),
            IndexResultKVItem(key: "系统版本", value: projection.osVersion),
            IndexResultKVItem(key: "设备类型", value: projection.device)
        ]
    }

    var body: some View {
        IndexPage(
            "User-Agent 解析",
            subtitle: "本地尽力识别浏览器、操作系统与设备类型，仅供调试，不用于能力判断或安全决策。",
            workspaceSemantic: .longTextNaturalInput
        ) {
            IndexInputResultWorkbench(
                inputTitle: "输入",
                resultTitle: "解析结果"
            ) {
                HStack(spacing: ToolMetrics.Spacing.sm) {
                    Spacer(minLength: ToolMetrics.Spacing.sm)
                    IndexClearButton(
                        isDisabled: !workspace.hasAnyContent,
                        action: workspace.clear
                    )
                }
            } resultControls: {
                EmptyView()
            } input: {
                IndexWorkspaceTextArea(
                    placeholder: "粘贴 User-Agent 字符串…",
                    text: $workspace.input,
                    minHeight: 80,
                    embedsFlat: true,
                    workspaceSemantic: .longTextNaturalInput
                )
                .onChange(of: workspace.input) { _ in parse() }
                .indexWorkspaceDiagnostic(workspace.error)
            } result: {
                IndexResultSurface(
                    content: .kv(rows),
                    emptyText: "输入 User-Agent 后自动解析"
                )
            }
        }
    }

    private func parse() {
        workspace.parse()
    }
}
