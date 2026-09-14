import Foundation

public enum KeyboardEventKind: String, Equatable, Sendable {
    case keyDown
    case modifierFlagsChanged

    public var displayName: String {
        switch self {
        case .keyDown:
            return "按键按下"
        case .modifierFlagsChanged:
            return "修饰键变化"
        }
    }
}

public struct KeyboardModifierState: Equatable, Sendable {
    public let control: Bool
    public let shift: Bool
    public let option: Bool
    public let command: Bool
    public let capsLock: Bool
    public let function: Bool

    public init(
        control: Bool = false,
        shift: Bool = false,
        option: Bool = false,
        command: Bool = false,
        capsLock: Bool = false,
        function: Bool = false
    ) {
        self.control = control
        self.shift = shift
        self.option = option
        self.command = command
        self.capsLock = capsLock
        self.function = function
    }

    public var displayText: String {
        var parts: [String] = []
        if control { parts.append("Ctrl") }
        if shift { parts.append("Shift") }
        if option { parts.append("Alt") }
        if command { parts.append("Meta") }
        if capsLock { parts.append("Caps Lock") }
        if function { parts.append("Fn") }
        return parts.isEmpty ? "无" : parts.joined(separator: " + ")
    }
}

public enum KeyboardEventLocation: Int, Equatable, Sendable {
    case standard = 0
    case left = 1
    case right = 2
    case numpad = 3

    public var displayText: String {
        switch self {
        case .standard:
            return "0（标准）"
        case .left:
            return "1（左侧）"
        case .right:
            return "2（右侧）"
        case .numpad:
            return "3（小键盘）"
        }
    }
}

public struct KeyboardEventInput: Equatable, Sendable {
    public let kind: KeyboardEventKind
    public let keyCode: UInt16
    public let characters: String?
    public let charactersIgnoringModifiers: String?
    public let modifiers: KeyboardModifierState
    public let isRepeat: Bool

    public init(
        kind: KeyboardEventKind,
        keyCode: UInt16,
        characters: String?,
        charactersIgnoringModifiers: String?,
        modifiers: KeyboardModifierState,
        isRepeat: Bool
    ) {
        self.kind = kind
        self.keyCode = keyCode
        self.characters = characters
        self.charactersIgnoringModifiers = charactersIgnoringModifiers
        self.modifiers = modifiers
        self.isRepeat = isRepeat
    }
}

public struct KeyboardEventSnapshot: Equatable, Sendable {
    public let kind: KeyboardEventKind
    public let keyCode: UInt16
    public let nativeKeyName: String
    public let webKey: String
    public let webCode: String
    public let location: KeyboardEventLocation
    public let modifiers: KeyboardModifierState
    public let legacyKeyCode: String
    public let asciiCode: String
    public let isRepeat: Bool

    public init(
        kind: KeyboardEventKind,
        keyCode: UInt16,
        nativeKeyName: String,
        webKey: String,
        webCode: String,
        location: KeyboardEventLocation,
        modifiers: KeyboardModifierState,
        legacyKeyCode: String,
        asciiCode: String,
        isRepeat: Bool
    ) {
        self.kind = kind
        self.keyCode = keyCode
        self.nativeKeyName = nativeKeyName
        self.webKey = webKey
        self.webCode = webCode
        self.location = location
        self.modifiers = modifiers
        self.legacyKeyCode = legacyKeyCode
        self.asciiCode = asciiCode
        self.isRepeat = isRepeat
    }

    public var displayKey: String {
        if nativeKeyName != "—" {
            return nativeKeyName
        }
        if webCode != "—" {
            return webCode
        }
        return "未知按键"
    }
}

public enum KeycodeMapper {
    public static func snapshot(for input: KeyboardEventInput) -> KeyboardEventSnapshot {
        KeyboardEventSnapshot(
            kind: input.kind,
            keyCode: input.keyCode,
            nativeKeyName: keyName(
                keyCode: input.keyCode,
                charactersIgnoringModifiers: input.charactersIgnoringModifiers
            ),
            webKey: webKey(keyCode: input.keyCode, characters: input.characters),
            webCode: webCode(keyCode: input.keyCode),
            location: location(keyCode: input.keyCode),
            modifiers: input.modifiers,
            legacyKeyCode: jsKeyCode(keyCode: input.keyCode),
            asciiCode: asciiCode(charactersIgnoringModifiers: input.charactersIgnoringModifiers),
            isRepeat: input.isRepeat
        )
    }

    /// 按键的友好名称：非打印键查 `specialKeyNames`；空格显示 "Space"；
    /// 否则用忽略修饰键的字符，空则 "—"。
    public static func keyName(keyCode: UInt16, charactersIgnoringModifiers characters: String?) -> String {
        if let name = specialKeyNames[keyCode] { return name }
        let chars = characters ?? ""
        if chars == " " { return "Space" }
        return chars.isEmpty ? "—" : chars
    }

    public static func asciiCode(charactersIgnoringModifiers characters: String?) -> String {
        guard let scalar = (characters ?? "").unicodeScalars.first else { return "—" }
        return scalar.value < 128 ? "\(scalar.value)" : "—"
    }

    public static func jsKeyCode(keyCode: UInt16) -> String {
        jsKeyCodeMap[keyCode].map { "\($0)" } ?? "—"
    }

    public static func webKey(keyCode: UInt16, characters: String?) -> String {
        if let name = webKeyNames[keyCode] { return name }
        let chars = characters ?? ""
        return chars.isEmpty ? "—" : chars
    }

    public static func webCode(keyCode: UInt16) -> String {
        webCodeMap[keyCode] ?? "—"
    }

    public static func location(keyCode: UInt16) -> KeyboardEventLocation {
        switch keyCode {
        case 0x37, 0x38, 0x3A, 0x3B:
            return .left
        case 0x36, 0x3C, 0x3D, 0x3E:
            return .right
        case 0x34, 0x41, 0x43, 0x45, 0x47, 0x4B, 0x4C, 0x4E, 0x51,
             0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5B, 0x5C, 0x5F:
            return .numpad
        default:
            return .standard
        }
    }

    public static func modifiers(control: Bool, shift: Bool, option: Bool, command: Bool) -> String {
        KeyboardModifierState(
            control: control,
            shift: shift,
            option: option,
            command: command
        ).displayText
    }
}
