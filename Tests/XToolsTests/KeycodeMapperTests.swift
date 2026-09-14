import XToolsCore
import Testing

struct KeycodeMapperTests {
    @Test func specialKeyNameTakesPrecedenceOverCharacters() {
        // 0x24 是 Return，即便带了字符也应显示友好名。
        #expect(KeycodeMapper.keyName(keyCode: 0x24, charactersIgnoringModifiers: "\r") == "Return")
    }

    @Test func spaceShowsAsSpaceWord() {
        // 0x31 也在 specialKeyNames 里（Space），命中表优先。
        #expect(KeycodeMapper.keyName(keyCode: 0x31, charactersIgnoringModifiers: " ") == "Space")
    }

    @Test func spaceCharacterOnUnmappedKeyStillShowsSpace() {
        // 未在表中的键码，若字符是空格，走「空格 → Space」分支。
        #expect(KeycodeMapper.keyName(keyCode: 0xFF, charactersIgnoringModifiers: " ") == "Space")
    }

    @Test func printableCharacterFallsThrough() {
        #expect(KeycodeMapper.keyName(keyCode: 0x00, charactersIgnoringModifiers: "a") == "a")
    }

    @Test func emptyCharactersOnUnmappedKeyShowsDash() {
        #expect(KeycodeMapper.keyName(keyCode: 0xFF, charactersIgnoringModifiers: "") == "—")
        #expect(KeycodeMapper.keyName(keyCode: 0xFF, charactersIgnoringModifiers: nil) == "—")
    }

    @Test func asciiCodeReturnsScalarValueBelow128() {
        #expect(KeycodeMapper.asciiCode(charactersIgnoringModifiers: "A") == "65")
        #expect(KeycodeMapper.asciiCode(charactersIgnoringModifiers: "a") == "97")
    }

    @Test func asciiCodeReturnsDashForNonASCIIOrEmpty() {
        #expect(KeycodeMapper.asciiCode(charactersIgnoringModifiers: "中") == "—")
        #expect(KeycodeMapper.asciiCode(charactersIgnoringModifiers: "") == "—")
        #expect(KeycodeMapper.asciiCode(charactersIgnoringModifiers: nil) == "—")
    }

    @Test func jsKeyCodeMapsKnownVirtualKeys() {
        // 0x00 → 65 (A)，0x24 → 13 (Enter)，0x7E → 38 (↑)。
        #expect(KeycodeMapper.jsKeyCode(keyCode: 0x00) == "65")
        #expect(KeycodeMapper.jsKeyCode(keyCode: 0x24) == "13")
        #expect(KeycodeMapper.jsKeyCode(keyCode: 0x7E) == "38")
    }

    @Test func jsKeyCodeReturnsDashForUnmappedKey() {
        #expect(KeycodeMapper.jsKeyCode(keyCode: 0xFF) == "—")
    }

    @Test func webKeyUsesStandardSpecialNamesAndPrintableCharacters() {
        #expect(KeycodeMapper.webKey(keyCode: 0x24, characters: "\r") == "Enter")
        #expect(KeycodeMapper.webKey(keyCode: 0x7B, characters: nil) == "ArrowLeft")
        #expect(KeycodeMapper.webKey(keyCode: 0x00, characters: "A") == "A")
        #expect(KeycodeMapper.webKey(keyCode: 0xFF, characters: nil) == "—")
    }

    @Test func webCodeMapsPhysicalKeyLocation() {
        #expect(KeycodeMapper.webCode(keyCode: 0x00) == "KeyA")
        #expect(KeycodeMapper.webCode(keyCode: 0x12) == "Digit1")
        #expect(KeycodeMapper.webCode(keyCode: 0x7B) == "ArrowLeft")
        #expect(KeycodeMapper.webCode(keyCode: 0xFF) == "—")
    }

    @Test func modifiersJoinInFixedOrder() {
        #expect(KeycodeMapper.modifiers(control: true, shift: true, option: true, command: true) == "Ctrl + Shift + Alt + Meta")
        #expect(KeycodeMapper.modifiers(control: false, shift: true, option: false, command: true) == "Shift + Meta")
    }

    @Test func modifiersReturnsNoneWhenEmpty() {
        #expect(KeycodeMapper.modifiers(control: false, shift: false, option: false, command: false) == "无")
    }

    @Test func snapshotProjectsKeyDownIntoNativeAndWebFields() {
        let input = KeyboardEventInput(
            kind: .keyDown,
            keyCode: 0x00,
            characters: "A",
            charactersIgnoringModifiers: "a",
            modifiers: .init(shift: true),
            isRepeat: true
        )

        let snapshot = KeycodeMapper.snapshot(for: input)

        #expect(snapshot.kind == .keyDown)
        #expect(snapshot.kind.displayName == "按键按下")
        #expect(snapshot.nativeKeyName == "a")
        #expect(snapshot.webKey == "A")
        #expect(snapshot.webCode == "KeyA")
        #expect(snapshot.location == .standard)
        #expect(snapshot.modifiers.displayText == "Shift")
        #expect(snapshot.legacyKeyCode == "65")
        #expect(snapshot.asciiCode == "97")
        #expect(snapshot.isRepeat)
    }

    @Test func modifierSnapshotSupportsRightCommandAndFlagsChanged() {
        let snapshot = KeycodeMapper.snapshot(for: KeyboardEventInput(
            kind: .modifierFlagsChanged,
            keyCode: 0x36,
            characters: nil,
            charactersIgnoringModifiers: nil,
            modifiers: .init(command: true),
            isRepeat: false
        ))

        #expect(snapshot.kind == .modifierFlagsChanged)
        #expect(snapshot.kind.displayName == "修饰键变化")
        #expect(snapshot.nativeKeyName == "Command (右)")
        #expect(snapshot.webKey == "Meta")
        #expect(snapshot.webCode == "MetaRight")
        #expect(snapshot.location == .right)
        #expect(snapshot.location.displayText == "2（右侧）")
        #expect(snapshot.modifiers.displayText == "Meta")
    }

    @Test func modifierStateIncludesCapsLockAndFunctionInStableOrder() {
        let modifiers = KeyboardModifierState(
            control: true,
            shift: true,
            option: true,
            command: true,
            capsLock: true,
            function: true
        )

        #expect(modifiers.displayText == "Ctrl + Shift + Alt + Meta + Caps Lock + Fn")
        #expect(KeyboardModifierState().displayText == "无")
    }

    @Test func locationDistinguishesLeftRightAndNumpad() {
        #expect(KeycodeMapper.location(keyCode: 0x3B) == .left)
        #expect(KeycodeMapper.location(keyCode: 0x36) == .right)
        #expect(KeycodeMapper.location(keyCode: 0x52) == .numpad)
        #expect(KeycodeMapper.location(keyCode: 0x00) == .standard)
    }

    @Test func webCodeCoversStableInternationalAndExtendedMacKeys() {
        #expect(KeycodeMapper.webCode(keyCode: 0x0A) == "IntlBackslash")
        #expect(KeycodeMapper.webCode(keyCode: 0x5D) == "IntlYen")
        #expect(KeycodeMapper.webCode(keyCode: 0x5E) == "IntlRo")
        #expect(KeycodeMapper.webCode(keyCode: 0x5F) == "NumpadComma")
        #expect(KeycodeMapper.keyName(keyCode: 0x3F, charactersIgnoringModifiers: nil) == "Fn")
        #expect(KeycodeMapper.webKey(keyCode: 0x3F, characters: nil) == "Fn")
        #expect(KeycodeMapper.webCode(keyCode: 0x3F) == "—")
        #expect(KeycodeMapper.webCode(keyCode: 0x69) == "F13")
        #expect(KeycodeMapper.webCode(keyCode: 0x6B) == "F14")
        #expect(KeycodeMapper.webCode(keyCode: 0x71) == "F15")
        #expect(KeycodeMapper.webCode(keyCode: 0x6A) == "F16")
        #expect(KeycodeMapper.webCode(keyCode: 0x40) == "F17")
        #expect(KeycodeMapper.webCode(keyCode: 0x4F) == "F18")
        #expect(KeycodeMapper.webCode(keyCode: 0x50) == "F19")
        #expect(KeycodeMapper.webCode(keyCode: 0x5A) == "F20")
    }

}
