import XToolsCore
import SwiftUI

@MainActor
final class UserAgentToolWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<UserAgentToolWorkspaceModel>(toolID: "useragent-parser") { _ in
        UserAgentToolWorkspaceModel()
    }

    @Published var input = ""
    @Published private(set) var browser = ""
    @Published private(set) var browserVersion = ""
    @Published private(set) var os = ""
    @Published private(set) var osVersion = ""
    @Published private(set) var device = ""
    @Published private(set) var error: String?

    var hasAnyContent: Bool {
        !input.isEmpty
            || !browser.isEmpty
            || !browserVersion.isEmpty
            || !os.isEmpty
            || !osVersion.isEmpty
            || !device.isEmpty
            || error != nil
    }

    func clear() {
        input = ""
        clearResult()
        error = nil
    }

    func parse() {
        error = nil
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            clearResult()
            return
        }

        guard let result = UserAgentParser.parse(trimmed) else {
            clearResult()
            error = userAgentErrorMessage(for: UserAgentParser.validationIssue(trimmed))
            return
        }

        browser = result.browser
        browserVersion = result.browserVersion
        os = result.os
        osVersion = result.osVersion
        device = result.device
    }

    private func clearResult() {
        browser = ""
        browserVersion = ""
        os = ""
        osVersion = ""
        device = ""
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
              !workspace.browser.isEmpty else {
            return nil
        }

        return ResultProjection(
            browser: workspace.browser,
            browserVersion: workspace.browserVersion,
            os: workspace.os,
            osVersion: workspace.osVersion,
            device: workspace.device
        )
    }

    private var resultPresenceUpdateID: [String] {
        resultProjection?.updateID ?? []
    }

    var body: some View {
        IndexPage("User-Agent 解析", subtitle: "本地尽力识别浏览器、操作系统与设备类型，仅供调试，不用于能力判断或安全决策。", layout: .scroll) {
            IndexPanel("输入") {
                IndexWorkspaceTextArea(
                    placeholder: "粘贴 User-Agent 字符串…",
                    text: $workspace.input,
                    minHeight: 80,
                    workspaceSemantic: .longTextNaturalInput
                )
                    .onChange(of: workspace.input) { _ in parse() }
                    .indexWorkspaceDiagnostic(workspace.error)
            } accessory: {
                IndexClearButton(
                    isDisabled: !workspace.hasAnyContent,
                    action: workspace.clear
                )
            }

            IndexPanel("解析结果") {
                VStack(alignment: .leading, spacing: 12) {
                    IndexWorkspaceResultSurface {
                        IndexResultPresence(
                            value: resultProjection,
                            updateID: resultPresenceUpdateID
                        ) { result in
                            VStack(alignment: .leading, spacing: 16) {
                                IndexKVRow(key: "浏览器", value: result.browser, valueLineBreakMode: .byCharWrapping, valueMotion: .immediate)
                                IndexKVRow(key: "浏览器版本", value: result.browserVersion, valueLineBreakMode: .byCharWrapping, valueMotion: .immediate)
                                IndexKVRow(key: "操作系统", value: result.os, valueLineBreakMode: .byCharWrapping, valueMotion: .immediate)
                                IndexKVRow(key: "系统版本", value: result.osVersion, valueLineBreakMode: .byCharWrapping, valueMotion: .immediate)
                                IndexKVRow(key: "设备类型", value: result.device, valueLineBreakMode: .byCharWrapping, valueMotion: .immediate)
                            }
                            .padding(ToolMetrics.Spacing.sm)
                        } empty: {
                            IndexEmptyState(
                                title: IndexEmptyStateCopy.noParsedResult,
                                systemImage: "globe",
                                message: IndexEmptyStateCopy.autoShow("User-Agent"),
                                density: .list
                            )
                            .frame(minHeight: 70)
                        }
                    }
                }
            }
        }
    }

    private func parse() {
        workspace.parse()
    }
}
