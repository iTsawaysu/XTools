import Foundation
import Testing

struct BasicAuthResultActionSourceContractTests {
    @Test func iconOnlyCopyAndIconButtonsShareOneFixedActionSlot() throws {
        let controls = try readSource("Sources/XTools/ToolPages/Workbench/Controls/IndexControls.swift")
        let iconStyle = sourceSlice(
            controls,
            from: "struct IndexIconActionButtonStyle: ButtonStyle",
            to: "// MARK: - IndexCopyButton"
        )
        let copyButton = sourceSlice(
            controls,
            from: "struct IndexCopyButton: View",
            to: "// MARK: - IndexMotionLabel"
        )
        let iconButton = sourceSlice(
            controls,
            from: "struct IndexIconButton: View",
            to: "// MARK: - IndexSegmentedControl"
        )

        contains(iconStyle, "return Color.clear", "Compact icon actions must not render a persistent elevated container")
        contains(iconStyle, "ToolTheme.hoverFill", "Compact icon actions must expose pointer feedback")
        contains(iconStyle, "ToolTheme.activeFill", "Compact icon actions must expose pressed feedback")
        contains(iconStyle, ".scaleEffect(configuration.isPressed ? ToolMotion.Scale.pressed : 1)", "Compact icon actions must share restrained pressed feedback")
        contains(iconStyle, "ToolMotion.Preset.controlFeedback", "Compact icon feedback must honor shared motion and Reduce Motion")
        contains(iconStyle, "value: [hovering, configuration.isPressed, isActive]", "Compact icon feedback must use one stable visual-state animation owner")

        contains(copyButton, "copyButton.buttonStyle(IndexIconActionButtonStyle(", "Icon-only copy must use the shared icon action slot")
        contains(copyButton, "copyButton.buttonStyle(IndexSmallButtonStyle(done: copied, framed: framed))", "Labeled copy actions must retain their existing bordered button style")
        contains(copyButton, ".toolMotionSuccessSwap(id: copied)", "Icon-only copy must retain checkmark feedback")
        contains(iconButton, ".buttonStyle(IndexIconActionButtonStyle(", "General icon buttons must use the same action slot as icon-only copy")
    }

    @Test func basicAuthParsedActionsUseAlignedIconSlotsWithoutWeakeningPasswordGate() throws {
        let page = try readSource("Sources/XTools/ToolPages/Web/BasicAuthGeneratorPage.swift")
        let usernameRow = sourceSlice(page, from: "private func parsedUsernameRow", to: "private func parsedPasswordRow")
        let passwordRow = sourceSlice(page, from: "private func parsedPasswordRow", to: "private func parsedResultRow")

        contains(usernameRow, "IndexCopyButton(text: value, title: \"复制\", iconOnly: true)", "Username copy must use the shared fixed icon slot")
        contains(passwordRow, "IndexCopyButton(text: value, title: \"复制\", iconOnly: true)", "Revealed-password copy must use the shared fixed icon slot")
        contains(passwordRow, "if showsParsedPassword", "Password copy must remain gated by explicit reveal")
        contains(passwordRow, "IndexIconButton(", "Password reveal must keep the shared icon action control")
        doesNotContain(page, "IndexCopyButton(text: value, title: \"\")", "Parsed credential copy actions must not expose an empty accessibility label")
    }
}
