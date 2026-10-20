import Testing
import XToolsCore
@testable import XTools

@MainActor
struct RegexToolWorkspaceTests {
    @Test func applyingPresetReplacesPatternFlagsAndExampleText() throws {
        let workspace = RegexToolWorkspaceModel()
        let preset = try #require(RegexMatcher.presets.first { $0.id == "duplicate-word" })

        workspace.applyPreset(preset)

        #expect(workspace.pattern == preset.pattern)
        #expect(workspace.flags == "gi")
        #expect(workspace.text == preset.exampleText)
        #expect(workspace.activePreset?.id == preset.id)
    }
}
