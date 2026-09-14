import Foundation
import Testing

struct StaticTypographySourceContractTests {
    @Test func typographyKeepsOneStaticSemanticTokenOwnerWithoutRuntimeScale() throws {
        let typography = try readSource("Sources/XTools/Shared/ToolTypography.swift")
        let root = try readSource("Sources/XTools/AppShell/RootView.swift")
        let preferences = try readSource("Sources/XTools/AppShell/ToolPreferenceStore.swift")
        let app = try readSource("Sources/XTools/XToolsApp.swift")
        let keycode = try readSource("Sources/XTools/ToolPages/Web/KeycodeInfoPage.swift")
        let emptyState = try readSource("Sources/XTools/Shared/Components/IndexEmptyState.swift")
        let controls = try readSource("Sources/XTools/ToolPages/Workbench/Controls/IndexControls.swift")

        contains(typography, "static let pageTitle = Font.system(size: 18, weight: .semibold)", "Page title must keep the standard 18-point semantic token")
        contains(typography, "static let pageSubtitle = Font.system(size: 12.5)", "Page subtitle must keep the standard 12.5-point semantic token")
        contains(typography, "static let sectionTitle = Font.system(size: 14, weight: .semibold)", "Section titles must keep the reviewed 14-point hierarchy")
        contains(typography, "static let compactBody = Font.system(size: 12)", "Compact readable body copy must remain centralized")
        doesNotContain(typography, "keyListenerPrompt", "The retired AppKit-drawn key prompt must not leave orphaned typography tokens")
        contains(typography, "static func controlLabel(weight: Font.Weight) -> Font", "Parameterized control labels must remain semantic static fonts")

        doesNotContain(typography, "ToolContentTextScale", "The removed content scale model must not survive in typography")
        doesNotContain(typography, "ToolFontToken", "Static typography must not keep a runtime token wrapper")
        doesNotContain(typography, "EnvironmentKey", "Typography must not install a scale environment key")
        doesNotContain(typography, "ViewModifier", "Typography must not install an environment-aware font modifier")
        doesNotContain(root, "contentTextScale", "Root state and environment must not retain content scaling")
        doesNotContain(preferences, "contentTextScale", "The preference owner must not read or write the orphaned scale key")
        doesNotContain(app, "TypographyCommands", "The View menu must release the removed typography commands and shortcuts")

        doesNotContain(keycode, "ToolContentTextScale", "The AppKit key listener must not receive a SwiftUI scale bridge")
        doesNotContain(keycode, "contentTextScale", "The key listener representable and NSView must be scale-free")

        contains(emptyState, "case .panel: return ToolMetrics.IconSize.display", "Panel empty-state glyphs must use the shared display icon-size token")
        contains(emptyState, "case .list, .output: return ToolMetrics.IconSize.large", "List and output empty-state glyphs must use the shared large icon-size token")
        doesNotContain(emptyState, ".system(size: 22", "Empty states must not keep raw ad-hoc glyph sizes")
        contains(emptyState, "density == .panel ? ToolTypography.sectionTitle : ToolTypography.bodyMedium", "Empty-state titles must stay on the shared type scale per density")

        occurrenceCount(controls, "ToolTypography.controlLabel(weight:", 2, "Page control labels must keep the centralized parameterized token")
    }
}
