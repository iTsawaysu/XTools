import Foundation
import Testing

struct IndexBadgeSourceContractTests {
    @Test func badgeHoverTracksPointerWhileSelectionKeepsOneSharedHighlightState() throws {
        let badge = try readSource("Sources/XTools/Shared/Components/IndexBadge.swift")

        contains(badge, "public struct IndexBadge: View", "Chips, badges, and tags must consolidate into the single shared IndexBadge component")
        contains(badge, "private var isHighlighted: Bool", "Badge feedback must derive one visual state from hover and selection")
        contains(badge, "isSelected || isHovering", "Hover and selection must both project into the shared highlight state")
        contains(badge, "if isSelected {\n            return ToolTheme.selectionFill\n        }", "Actual selection must keep the selection-level fill instead of a weaker generic fill")
        contains(badge, "isHovering && action != nil", "Pointer hover may only lift the background for actionable badges")
        contains(badge, "return ToolTheme.hoverFill", "Actionable badge hover must use the shared hover fill")
        contains(badge, "return effectiveTone.softFill", "Non-highlighted badges must fall back to the tone-driven soft fill")
        contains(badge, "isHighlighted && tone == .neutral", "Hover and selection must lift neutral badges into the accent hierarchy")
        contains(badge, "return .accent", "Highlighted neutral badges must project into the shared accent tone")
        contains(badge, ".foregroundStyle(effectiveTone.tint)", "Badge foreground must derive from one shared tone owner")
        contains(badge, "return ToolTheme.selectionStroke", "Actual selection must keep a stable selection-level outline")
        contains(badge, "strokeBorder(border, lineWidth: 1)", "Badges must keep one stroke weight, clearing the border instead of thinning it")
        contains(badge, "isCapsule ? ToolTypography.tagMicro : ToolTypography.monoValueSmall", "Badge typography must stay on the shared type scale for capsule tags and mono values")
        contains(badge, "Button(action: action) {", "Selectable badges must render through one shared action button")
        contains(badge, ".buttonStyle(.plain)", "Badge chrome must own the visuals instead of the native button style")
        contains(badge, ".onHover { isHovering = $0 }", "Pointer hover must assign the current hit state directly")
        contains(badge, ".help(help ?? \"\")", "Actionable badges must remain discoverable through the shared help modifier")

        doesNotContain(badge, ".toolAnimation(", "Badge hover and selection changes must settle immediately without owning an animation transaction")
        doesNotContain(badge, "withAnimation(", "Badge state changes must not keep a hand-rolled animation path")
        doesNotContain(badge, "value: isHovering", "Badge hover must not own a separate animation transaction")
        doesNotContain(badge, "value: isHighlighted", "Pointer hover must not animate the shared highlight state and leave a visible trail")
    }

    @Test func presetAndFilterPagesReuseTheSharedChipContract() throws {
        let regex = try readSource("Sources/XTools/ToolPages/Development/RegexTesterPage.swift")
        contains(regex, "Menu {", "Regex presets must use a compact native action menu in the panel header")
        contains(regex, ".buttonStyle(IndexSmallButtonStyle())", "Regex preset menu must fit the panel-header control height")
        doesNotContain(regex, "IndexOptionMenu(", "Regex presets must not place a full-height option selector in the panel header")
        doesNotContain(regex, "IndexBadge(", "Regex presets must not consume the wider chip row")

        let callSites = [
            "Sources/XTools/ToolPages/Development/CrontabGeneratorPage.swift",
            "Sources/XTools/ToolPages/Time/DateCalculatorPage.swift",
            "Sources/XTools/ToolPages/Utility/EmojiPickerPage.swift",
            "Sources/XTools/ToolPages/Web/HTTPStatusCodesPage.swift"
        ]

        for path in callSites {
            let source = try readSource(path)
            contains(source, "IndexBadge(", "\(path) must keep shared chip geometry and feedback through the consolidated badge")
        }
    }
}
