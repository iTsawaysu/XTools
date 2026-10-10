import Foundation
import Testing

struct SourceControlSourceContractTests {
    @Test func pageReusesNativeShellControls() throws {
        let page = try sourceControlReadSource("Sources/XTools/ToolPages/Development/SourceControlPage.swift")
        #expect(page.contains("IndexPage(\"源码管理\""))
        #expect(page.contains("IndexPanel(\"同步范围\""))
        // 细线进度与整行点选是本页的准入交互，钉进源契约防止回退。
        #expect(page.contains("IndexProgressHairline("))
        #expect(page.contains(".contentShape(Rectangle())"))
        #expect(page.contains("contextMenu {"), "行右键菜单是准入交互")
        // 模型已从页面文件抽离；禁用项沿用拆分前「模型+视图」整文件口径。
        let workspaceModel = try sourceControlReadSource("Sources/XTools/ToolPages/Development/SourceControlWorkspaceModel.swift")
        for source in [page, workspaceModel] {
            #expect(!source.contains("UserDefaults"))
            #expect(!source.contains("Keychain"))
            #expect(!source.contains("buttonStyle(.plain)"))
            #expect(!source.contains("localizedDescription"))
        }
    }

    @Test func registryContainsOneSourceControlTool() throws {
        let registry = try sourceControlReadSource("Sources/XTools/ToolRegistry/ToolRegistry.swift")
        #expect(registry.components(separatedBy: "id: \"source-control\"").count == 2)
        #expect(registry.components(separatedBy: "title: \"源码管理\"").count == 2)
    }

    @Test func coreStaysLocalOnly() throws {
        let root = try sourceControlPackageRoot()
        let directory = root.appendingPathComponent("Sources/XToolsCore/SourceControl")
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        let source = try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
        #expect(!source.contains("UserDefaults"))
        #expect(!source.contains("Keychain"))
        #expect(!source.contains("print("))
    }
}

private func sourceControlReadSource(_ relativePath: String) throws -> String {
    let root = try sourceControlPackageRoot()
    return try String(contentsOfFile: root.appendingPathComponent(relativePath).path, encoding: .utf8)
}

private func sourceControlPackageRoot() throws -> URL {
    let fileURL = URL(fileURLWithPath: #filePath)
    var root = fileURL
    for _ in 0..<3 { root.deleteLastPathComponent() }
    return root
}
