import Foundation
import Testing

@Suite struct CursorSourceContractTests {
    @Test func iBeamCursorIsOnlyInstalledBySharedTextSurfaces() throws {
        let root = TestMarkdownCaseSupport.repositoryRoot()
            .appendingPathComponent("Sources/XTools")
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil
        )
        var imperativeBeamFiles: [String] = []
        var cursorRectBeamFiles: [String] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let source = try String(contentsOf: url, encoding: .utf8)
            if source.contains("NSCursor.iBeam.set()") {
                imperativeBeamFiles.append(url.lastPathComponent)
            }
            if source.contains("addCursorRect(bounds, cursor: .iBeam)") {
                cursorRectBeamFiles.append(url.lastPathComponent)
            }
        }
        #expect(imperativeBeamFiles == ["IBeamCursor.swift"])
        #expect(cursorRectBeamFiles == ["AppKitTextFieldGeometry.swift"])
    }

    @Test func pageStageClearsCursorBeforeMountingTheNextPage() throws {
        let source = try TestMarkdownCaseSupport.readSource(
            "Sources/XTools/AppShell/ToolPageStage.swift"
        )
        #expect(source.contains("NSCursor.arrow.set()"))
        #expect(source.components(separatedBy: "NSCursor.arrow.set()").count >= 3)
    }
}
