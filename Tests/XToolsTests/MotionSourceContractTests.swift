import Foundation
import Testing

@Suite struct MotionSourceContractTests {
    private let newComponentFiles = [
        "ToolButton.swift",
        "ToolFieldSurface.swift",
        "ToolBadge.swift",
        "ToolMenu.swift",
        "ToolSearchField.swift",
        "ToolFeedbackSurface.swift"
    ]

    @Test func newComponentsUseOnlySemanticMotionPresets() throws {
        for file in newComponentFiles {
            let source = try TestMarkdownCaseSupport.readSource(
                "Sources/XTools/Shared/Components/\(file)"
            )
            #expect(!source.contains("withAnimation("), "\(file) 不得直接 withAnimation")
            #expect(!source.contains(".animation("), "\(file) 不得直接 .animation")
            #expect(!source.contains("Animation."), "\(file) 不得直接构造 Animation")
            #expect(!source.contains(".spring("), "\(file) 不得直接写 spring")
            #expect(!source.contains(".timingCurve("), "\(file) 不得直接写 timingCurve")
        }
    }

    @Test func animationGateRequiresExplicitReduceMotion() throws {
        let source = try TestMarkdownCaseSupport.readSource(
            "Sources/XTools/Shared/ToolMotion.swift"
        )
        #expect(!source.contains("reduceMotion: Bool? = nil"))
        #expect(source.contains("reduceMotion: Bool,"))
    }

    @Test func sourcesContainNoRawAnimationConstructors() throws {
        let root = TestMarkdownCaseSupport.repositoryRoot()
            .appendingPathComponent("Sources/XTools")
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil
        )
        var checked = 0
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            guard url.lastPathComponent != "ToolMotion.swift" else { continue }
            let source = try String(contentsOf: url, encoding: .utf8)
            #expect(!source.contains("withAnimation("))
            #expect(!source.contains("Animation."))
            #expect(!source.contains(".spring("))
            #expect(!source.contains(".timingCurve("))
            checked += 1
        }
        #expect(checked > 200)
    }

}
