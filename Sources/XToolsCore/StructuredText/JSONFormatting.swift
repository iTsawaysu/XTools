import Foundation

public enum JSONFormatting {
    public struct FormattingResult: Equatable {
        public let text: String
        public let warning: String?
        public let duplicateKeys: [String]
        public let exactTextIdentity: JSONExactTextIdentity

        public init(
            text: String,
            warning: String? = nil,
            duplicateKeys: [String] = [],
            exactTextIdentity: JSONExactTextIdentity? = nil
        ) {
            self.text = text
            self.warning = warning
            self.duplicateKeys = duplicateKeys
            self.exactTextIdentity = exactTextIdentity ?? JSONExactTextIdentity(text)
        }
    }

    public enum FormattingError: Error, LocalizedError, Equatable {
        case invalidJSON(FormatDiagnostic)

        public var errorDescription: String? {
            switch self {
            case .invalidJSON(let diagnostic):
                return diagnostic.workspaceMessage
            }
        }

        public var diagnostic: FormatDiagnostic {
            switch self {
            case .invalidJSON(let diagnostic):
                return diagnostic
            }
        }
    }

    public static func format(_ text: String, sortKeys: Bool, sortArrays: Bool = false, indentWidth: Int) throws -> String {
        try formatResult(text, sortKeys: sortKeys, sortArrays: sortArrays, indentWidth: indentWidth).text
    }

    public static func minify(_ text: String) throws -> String {
        try minifyResult(text).text
    }

    public static func formatResult(_ text: String, sortKeys: Bool, sortArrays: Bool = false, indentWidth: Int) throws -> FormattingResult {
        try formatResult(
            text,
            sortKeys: sortKeys,
            sortArrays: sortArrays,
            indentWidth: indentWidth,
            parserDidStart: nil
        )
    }

    static func formatResult(
        _ text: String,
        sortKeys: Bool,
        sortArrays: Bool = false,
        indentWidth: Int,
        parserDidStart: (@Sendable () -> Void)?
    ) throws -> FormattingResult {
        let document = try parseOrderedJSON(text, parserDidStart: parserDidStart)
        let duplicateKeys = uniqueDuplicateKeys(document.duplicateKeys)
        let rendered = render(
            document.value,
            sortKeys: sortKeys,
            sortArrays: sortArrays,
            indentWidth: max(0, indentWidth),
            level: 0
        )
        return FormattingResult(
            text: rendered,
            warning: duplicateKeyWarning(from: duplicateKeys),
            duplicateKeys: duplicateKeys,
            exactTextIdentity: JSONExactTextIdentity(rendered)
        )
    }

    public static func minifyResult(_ text: String, sortKeys: Bool = false, sortArrays: Bool = false) throws -> FormattingResult {
        let document = try parseOrderedJSON(text, parserDidStart: nil)
        let duplicateKeys = uniqueDuplicateKeys(document.duplicateKeys)
        let rendered = renderCompact(document.value, sortKeys: sortKeys, sortArrays: sortArrays)
        return FormattingResult(
            text: rendered,
            warning: duplicateKeyWarning(from: duplicateKeys),
            duplicateKeys: duplicateKeys,
            exactTextIdentity: JSONExactTextIdentity(rendered)
        )
    }

    public static func adjustIndentation(_ json: String, to spaces: Int) -> String {
        let targetSpaces = max(0, spaces)

        let lines = json.split(separator: "\n", omittingEmptySubsequences: false)
        let sourceIndentWidth = lines
            .map { $0.prefix(while: { $0 == " " }).count }
            .filter { $0 > 0 }
            .min()

        guard let sourceIndentWidth else {
            return json
        }

        return lines.map { line in
            let leadingSpaces = line.prefix(while: { $0 == " " }).count
            let indentLevel = leadingSpaces / sourceIndentWidth
            let newIndent = String(repeating: " ", count: indentLevel * targetSpaces)
            return newIndent + line.drop(while: { $0 == " " })
        }.joined(separator: "\n")
    }

    public static func escapeJSON(_ string: String) -> String {
        "\"\(escapeString(string))\""
    }

    public static func unescapeJSON(_ string: String) -> String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\""),
           let data = trimmed.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(String.self, from: data) {
            return decoded
        }
        let wrapped = "\"\(trimmed)\""
        if let data = wrapped.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(String.self, from: data) {
            return decoded
        }
        if (try? JSONSerialization.jsonObject(with: Data(string.utf8), options: [.fragmentsAllowed])) == nil {
            return trimmed
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\r", with: "\r")
                .replacingOccurrences(of: "\\t", with: "\t")
                .replacingOccurrences(of: "\\/", with: "/")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
        return string
    }

    private static func parseOrderedJSON(
        _ text: String,
        parserDidStart: (@Sendable () -> Void)?
    ) throws -> OrderedJSONDocument {
        parserDidStart?()
        var parser = OrderedJSONParser(text)
        return try parser.parse()
    }

    private static func duplicateKeyWarning(from keys: [String]) -> String? {
        guard !keys.isEmpty else {
            return nil
        }

        return "JSON 含重复 key。"
    }

    private static func uniqueDuplicateKeys(_ keys: [String]) -> [String] {
        var identities = Set<JSONExactTextIdentity>()
        return keys.filter { key in
            identities.insert(JSONExactTextIdentity(key)).inserted
        }
    }

    private static func render(
        _ value: OrderedJSONValue,
        sortKeys: Bool,
        sortArrays: Bool,
        indentWidth: Int,
        level: Int
    ) -> String {
        switch value {
        case .object(let pairs):
            guard !pairs.isEmpty else { return "{}" }
            let orderedPairs = orderedObjectPairs(pairs, sortKeys: sortKeys)
            let childIndent = String(repeating: " ", count: (level + 1) * indentWidth)
            let currentIndent = String(repeating: " ", count: level * indentWidth)
            let lines = orderedPairs.enumerated().map { index, pair in
                let comma = index == orderedPairs.count - 1 ? "" : ","
                return "\(childIndent)\"\(escapeString(pair.key))\": \(render(pair.value, sortKeys: sortKeys, sortArrays: sortArrays, indentWidth: indentWidth, level: level + 1))\(comma)"
            }
            return "{\n\(lines.joined(separator: "\n"))\n\(currentIndent)}"

        case .array(let values):
            guard !values.isEmpty else { return "[]" }
            let orderedValues = orderedArrayValues(
                values,
                sortKeys: sortKeys,
                sortArrays: sortArrays
            )
            let childIndent = String(repeating: " ", count: (level + 1) * indentWidth)
            let currentIndent = String(repeating: " ", count: level * indentWidth)
            let lines = orderedValues.enumerated().map { index, item in
                let comma = index == orderedValues.count - 1 ? "" : ","
                return "\(childIndent)\(render(item, sortKeys: sortKeys, sortArrays: sortArrays, indentWidth: indentWidth, level: level + 1))\(comma)"
            }
            return "[\n\(lines.joined(separator: "\n"))\n\(currentIndent)]"

        case .string(let string):
            return "\"\(escapeString(string))\""
        case .number(let number):
            return number
        case .bool(let value):
            return value ? "true" : "false"
        case .null:
            return "null"
        }
    }

    private static func renderCompact(_ value: OrderedJSONValue, sortKeys: Bool, sortArrays: Bool) -> String {
        switch value {
        case .object(let pairs):
            let orderedPairs = orderedObjectPairs(pairs, sortKeys: sortKeys)
            return "{" + orderedPairs.map { "\"\(escapeString($0.key))\":\(renderCompact($0.value, sortKeys: sortKeys, sortArrays: sortArrays))" }.joined(separator: ",") + "}"
        case .array(let values):
            guard sortArrays, values.count > 1 else {
                return "[" + values.map {
                    renderCompact($0, sortKeys: sortKeys, sortArrays: sortArrays)
                }.joined(separator: ",") + "]"
            }
            let orderedEntries = orderedArrayEntries(values, sortKeys: sortKeys, sortArrays: sortArrays)
            return "[" + orderedEntries.map(\.compactText).joined(separator: ",") + "]"
        case .string(let string):
            return "\"\(escapeString(string))\""
        case .number(let number):
            return number
        case .bool(let value):
            return value ? "true" : "false"
        case .null:
            return "null"
        }
    }

    private static func orderedObjectPairs(
        _ pairs: [(key: String, value: OrderedJSONValue)],
        sortKeys: Bool
    ) -> [(key: String, value: OrderedJSONValue)] {
        guard sortKeys else {
            return pairs
        }

        return pairs.enumerated()
            .map { offset, pair in
                (offset: offset, pair: pair, identity: JSONExactTextIdentity(pair.key))
            }
            .sorted { left, right in
                if left.identity == right.identity {
                    return left.offset < right.offset
                }
                return left.identity < right.identity
            }
            .map(\.pair)
    }

    private static func orderedArrayValues(
        _ values: [OrderedJSONValue],
        sortKeys: Bool,
        sortArrays: Bool
    ) -> [OrderedJSONValue] {
        guard sortArrays, values.count > 1 else {
            return values
        }

        return orderedArrayEntries(values, sortKeys: sortKeys, sortArrays: sortArrays)
            .map(\.value)
    }

    private static func orderedArrayEntries(
        _ values: [OrderedJSONValue],
        sortKeys: Bool,
        sortArrays: Bool
    ) -> [(value: OrderedJSONValue, compactText: String)] {
        return values.enumerated()
            .map { offset, value in
                let compact = renderCompact(value, sortKeys: sortKeys, sortArrays: sortArrays)
                return (
                    offset: offset,
                    value: value,
                    compactText: compact,
                    identity: JSONExactTextIdentity(compact)
                )
            }
            .sorted { left, right in
                if left.identity == right.identity {
                    return left.offset < right.offset
                }
                return left.identity < right.identity
            }
            .map { (value: $0.value, compactText: $0.compactText) }
    }

    private static func escapeString(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.utf8.count)

        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"":
                result.append("\\\"")
            case "\\":
                result.append("\\\\")
            case "\u{08}":
                result.append("\\b")
            case "\u{0C}":
                result.append("\\f")
            case "\n":
                result.append("\\n")
            case "\r":
                result.append("\\r")
            case "\t":
                result.append("\\t")
            case let scalar where scalar.value < 0x20:
                result.append(String(format: "\\u%04X", scalar.value))
            default:
                result.unicodeScalars.append(scalar)
            }
        }

        return result
    }
}

private enum OrderedJSONValue {
    case object([(key: String, value: OrderedJSONValue)])
    case array([OrderedJSONValue])
    case string(String)
    case number(String)
    case bool(Bool)
    case null
}

private struct OrderedJSONDocument {
    let value: OrderedJSONValue
    let duplicateKeys: [String]
}

private enum JSONParseContext {
    case root
    case array
    case objectValue
}

private enum JSONNumberComponent {
    case integer
    case fraction
    case exponent
}

private enum JSONNumberIssue {
    case invalid
    case leadingZero
    case leadingPlusSign
    case hexLiteral
    case missingIntegerAfterMinus
    case nonASCIIDigit(JSONNumberComponent)
    case invalidTrailingCharacter(Character)
    case missingFractionDigit
    case missingExponentDigit
}

private enum JSONStringIssue {
    case unterminated
    case unterminatedEscape
    case invalidEscape
    case invalidUnicodeEscape
    case missingLowSurrogate
    case invalidLowSurrogate
    case loneLowSurrogate
    case invalidUnicodeScalar
    case unescapedControlCharacter
}

private enum ContainerKind {
    case object
    case array
}

private struct OpenContainer {
    let kind: ContainerKind
    let startIndex: String.Index
    let key: String?
}

private enum JSONParseIssue {
    case trailingContent
    case unexpectedEnd
    case objectTrailingComma
    case objectRepeatedComma
    case objectKeyMustBeDoubleQuoted
    case objectNotClosed
    case arrayTrailingComma
    case arrayRepeatedComma
    case arrayNotClosed
    case singleQuotedString
    case commentNotAllowed
    case unsupportedLiteral(String)
    case missingColonAfterObjectKey
    case missingObjectValue
    case missingCommaOrClose
    case invalidNumber(JSONNumberIssue)
    case invalidString(JSONStringIssue)
    case incompleteLiteral(String)
    case unexpectedCharacter(Character)
    case exceededMaxDepth
    case containerNotClosed(kind: ContainerKind, startIndex: String.Index, key: String?)
}

private struct OrderedJSONParser {
    private let text: String
    private var index: String.Index
    private var duplicateKeys: [String] = []
    private var openContainers: [OpenContainer] = []
    private var depth: Int = 0
    private static let maxDepth: Int = 32

    init(_ text: String) {
        self.text = text
        self.index = text.startIndex
    }

    mutating func parse() throws -> OrderedJSONDocument {
        skipWhitespace()
        let value = try parseValue()
        skipWhitespace()
        guard index == text.endIndex else {
            throw error(.trailingContent)
        }
        return OrderedJSONDocument(value: value, duplicateKeys: duplicateKeys)
    }

    private mutating func parseValue() throws -> OrderedJSONValue {
        skipWhitespace()
        return try parseValue(context: .root, currentKey: nil)
    }

    private mutating func parseValue(context: JSONParseContext, currentKey: String? = nil) throws -> OrderedJSONValue {
        skipWhitespace()
        guard let char = peek() else {
            throw error(.unexpectedEnd)
        }

        switch char {
        case "{":
            depth += 1
            defer { depth -= 1 }
            guard depth <= Self.maxDepth else {
                throw error(.exceededMaxDepth)
            }
            return try parseObject(currentKey: currentKey)
        case "[":
            depth += 1
            defer { depth -= 1 }
            guard depth <= Self.maxDepth else {
                throw error(.exceededMaxDepth)
            }
            return try parseArray(currentKey: currentKey)
        case "\"":
            return .string(try parseString())
        case "t":
            try consumeLiteral("true")
            return .bool(true)
        case "f":
            try consumeLiteral("false")
            return .bool(false)
        case "n":
            try consumeLiteral("null")
            return .null
        case "+":
            throw error(.invalidNumber(.leadingPlusSign))
        case "-", "0"..."9":
            return .number(try parseNumber())
        case "'":
            throw error(.singleQuotedString)
        case "/":
            if isCommentStart() {
                throw error(.commentNotAllowed)
            }
            throw error(.unexpectedCharacter(char))
        case "N":
            if startsIdentifier("NaN") {
                throw error(.unsupportedLiteral("NaN"))
            }
            throw error(.unexpectedCharacter(char))
        case "I":
            if startsIdentifier("Infinity") {
                throw error(.unsupportedLiteral("Infinity"))
            }
            throw error(.unexpectedCharacter(char))
        case "]":
            throw error(context == .array ? .arrayNotClosed : .unexpectedCharacter(char))
        case "}":
            throw error(context == .objectValue ? .objectNotClosed : .unexpectedCharacter(char))
        default:
            if isNonASCIIDecimalDigit(char) {
                throw error(.invalidNumber(.nonASCIIDigit(.integer)))
            }
            throw error(.unexpectedCharacter(char))
        }
    }

    private mutating func parseObject(currentKey: String? = nil) throws -> OrderedJSONValue {
        let openIndex = index
        try consume("{")
        skipWhitespace()

        openContainers.append(OpenContainer(kind: .object, startIndex: openIndex, key: currentKey))
        defer { openContainers.removeLast() }

        var pairs: [(key: String, value: OrderedJSONValue)] = []
        var seenKeys = Set<JSONExactTextIdentity>()
        if consumeIfPresent("}") {
            return .object(pairs)
        }

        while true {
            skipWhitespace()
            guard let next = peek() else {
                throw error(.containerNotClosed(kind: .object, startIndex: openIndex, key: currentKey))
            }
            guard next == "\"" else {
                throw error(objectMemberStartIssue(for: next, afterComma: false))
            }
            let key = try parseString()
            let keyIdentity = JSONExactTextIdentity(key)
            if !seenKeys.insert(keyIdentity).inserted {
                duplicateKeys.append(key)
            }
            skipWhitespace()
            guard consumeIfPresent(":") else {
                throw error(.missingColonAfterObjectKey)
            }
            skipWhitespace()
            if peek() == nil || peek() == "}" || peek() == "," {
                throw error(.missingObjectValue)
            }
            let value = try parseValue(context: .objectValue, currentKey: key)
            pairs.append((key, value))
            skipWhitespace()

            if consumeIfPresent("}") {
                return .object(pairs)
            }
            guard consumeIfPresent(",") else {
                if peek() == nil {
                    throw error(.containerNotClosed(kind: .object, startIndex: openIndex, key: currentKey))
                }
                if isCommentStart() {
                    throw error(.commentNotAllowed)
                }
                throw error(.missingCommaOrClose)
            }

            skipWhitespace()
            guard let nextMember = peek() else {
                throw error(.containerNotClosed(kind: .object, startIndex: openIndex, key: currentKey))
            }
            if nextMember == "}" {
                throw error(.objectTrailingComma)
            }
            if nextMember != "\"" {
                throw error(objectMemberStartIssue(for: nextMember, afterComma: true))
            }
        }
    }

    private mutating func parseArray(currentKey: String? = nil) throws -> OrderedJSONValue {
        let openIndex = index
        try consume("[")
        skipWhitespace()

        openContainers.append(OpenContainer(kind: .array, startIndex: openIndex, key: currentKey))
        defer { openContainers.removeLast() }

        var values: [OrderedJSONValue] = []
        if consumeIfPresent("]") {
            return .array(values)
        }

        while true {
            values.append(try parseValue(context: .array, currentKey: currentKey))
            skipWhitespace()

            if consumeIfPresent("]") {
                return .array(values)
            }
            guard consumeIfPresent(",") else {
                if peek() == nil {
                    throw error(.containerNotClosed(kind: .array, startIndex: openIndex, key: currentKey))
                }
                if isCommentStart() {
                    throw error(.commentNotAllowed)
                }
                throw error(.missingCommaOrClose)
            }

            skipWhitespace()
            guard let nextValue = peek() else {
                throw error(.containerNotClosed(kind: .array, startIndex: openIndex, key: currentKey))
            }
            if nextValue == "]" {
                throw error(.arrayTrailingComma)
            }
            if nextValue == "," {
                throw error(.arrayRepeatedComma)
            }
        }
    }

    private mutating func parseString() throws -> String {
        try consume("\"")
        var result = ""

        while let char = advance() {
            switch char {
            case "\"":
                return result
            case "\\":
                result += try parseEscapedCharacter()
            default:
                guard !char.unicodeScalars.contains(where: { $0.value < 0x20 }) else {
                    throw error(.invalidString(.unescapedControlCharacter))
                }
                result.append(char)
            }
        }

        throw error(.invalidString(.unterminated))
    }

    private mutating func parseEscapedCharacter() throws -> String {
        guard let escape = advance() else {
            throw error(.invalidString(.unterminatedEscape))
        }

        switch escape {
        case "\"": return "\""
        case "\\": return "\\"
        case "/": return "/"
        case "b": return "\u{08}"
        case "f": return "\u{0C}"
        case "n": return "\n"
        case "r": return "\r"
        case "t": return "\t"
        case "u":
            return try parseUnicodeEscape()
        default:
            throw error(.invalidString(.invalidEscape))
        }
    }

    private mutating func parseUnicodeEscape() throws -> String {
        let first = try parseHexUnit()

        if (0xD800...0xDBFF).contains(first) {
            let savedIndex = index
            guard consumeIfPresent("\\"), consumeIfPresent("u") else {
                index = savedIndex
                throw error(.invalidString(.missingLowSurrogate))
            }

            let second = try parseHexUnit()
            guard (0xDC00...0xDFFF).contains(second) else {
                throw error(.invalidString(.invalidLowSurrogate))
            }

            let scalarValue = 0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00)
            guard let scalar = UnicodeScalar(scalarValue) else {
                throw error(.invalidString(.invalidUnicodeScalar))
            }
            return String(scalar)
        }

        if (0xDC00...0xDFFF).contains(first) {
            throw error(.invalidString(.loneLowSurrogate))
        }

        guard let scalar = UnicodeScalar(first) else {
            throw error(.invalidString(.invalidUnicodeEscape))
        }

        return String(scalar)
    }

    private mutating func parseHexUnit() throws -> Int {
        var hex = ""
        for _ in 0..<4 {
            guard let char = peek(), isJSONHexDigit(char) else {
                throw error(.invalidString(.invalidUnicodeEscape))
            }
            hex.append(advance()!)
        }

        guard let value = Int(hex, radix: 16) else {
            throw error(.invalidString(.invalidUnicodeEscape))
        }
        return value
    }

    private mutating func parseNumber() throws -> String {
        var result = ""

        let hasMinus = consumeIfPresent("-")
        if hasMinus {
            result += "-"
        }

        guard let first = peek() else {
            throw error(hasMinus ? .invalidNumber(.missingIntegerAfterMinus) : .invalidNumber(.invalid))
        }

        if first == "0" {
            result.append(advance()!)
            if let next = peek() {
                if isJSONDigit(next) {
                    throw error(.invalidNumber(.leadingZero))
                }
                if next == "x" || next == "X" {
                    throw error(.invalidNumber(.hexLiteral))
                }
                if isNonASCIIDecimalDigit(next) {
                    throw error(.invalidNumber(.nonASCIIDigit(.integer)))
                }
            }
        } else if isJSONNonZeroDigit(first) {
            while let char = peek(), isJSONDigit(char) {
                result.append(advance()!)
            }
            if let next = peek(), isNonASCIIDecimalDigit(next) {
                throw error(.invalidNumber(.nonASCIIDigit(.integer)))
            }
        } else if isNonASCIIDecimalDigit(first) {
            throw error(.invalidNumber(.nonASCIIDigit(.integer)))
        } else if hasMinus {
            throw error(.invalidNumber(.missingIntegerAfterMinus))
        } else {
            throw error(.invalidNumber(.invalid))
        }

        if consumeIfPresent(".") {
            result += "."
            if let next = peek(), isNonASCIIDecimalDigit(next) {
                throw error(.invalidNumber(.nonASCIIDigit(.fraction)))
            }
            guard let char = peek(), isJSONDigit(char) else {
                throw error(.invalidNumber(.missingFractionDigit))
            }
            while let char = peek(), isJSONDigit(char) {
                result.append(advance()!)
            }
            if let next = peek(), isNonASCIIDecimalDigit(next) {
                throw error(.invalidNumber(.nonASCIIDigit(.fraction)))
            }
        }

        if let char = peek(), char == "e" || char == "E" {
            result.append(advance()!)
            if let sign = peek(), sign == "+" || sign == "-" {
                result.append(advance()!)
            }
            if let next = peek(), isNonASCIIDecimalDigit(next) {
                throw error(.invalidNumber(.nonASCIIDigit(.exponent)))
            }
            guard let digit = peek(), isJSONDigit(digit) else {
                throw error(.invalidNumber(.missingExponentDigit))
            }
            while let char = peek(), isJSONDigit(char) {
                result.append(advance()!)
            }
            if let next = peek(), isNonASCIIDecimalDigit(next) {
                throw error(.invalidNumber(.nonASCIIDigit(.exponent)))
            }
        }

        if let next = peek(), isInvalidNumberTrailingCharacter(next) {
            throw error(.invalidNumber(.invalidTrailingCharacter(next)))
        }

        return result
    }

    private mutating func consumeLiteral(_ literal: String) throws {
        for expected in literal {
            guard peek() == expected else {
                throw error(.incompleteLiteral(literal))
            }
            _ = advance()
        }
    }

    private mutating func skipWhitespace() {
        while let char = peek(), char == " " || char == "\n" || char == "\r" || char == "\t" {
            _ = advance()
        }
    }

    private func peek() -> Character? {
        guard index < text.endIndex else {
            return nil
        }
        return text[index]
    }

    @discardableResult
    private mutating func advance() -> Character? {
        guard index < text.endIndex else {
            return nil
        }
        let char = text[index]
        index = text.index(after: index)
        return char
    }

    private mutating func consume(_ expected: Character) throws {
        guard peek() == expected else {
            switch expected {
            case "{":
                throw error(.unexpectedCharacter(peek() ?? expected))
            case "[":
                throw error(.unexpectedCharacter(peek() ?? expected))
            case "\"":
                throw error(.invalidString(.unterminated))
            default:
                throw error(.unexpectedCharacter(peek() ?? expected))
            }
        }
        _ = advance()
    }

    private mutating func consumeIfPresent(_ expected: Character) -> Bool {
        guard peek() == expected else {
            return false
        }
        _ = advance()
        return true
    }

    private func objectMemberStartIssue(for character: Character, afterComma: Bool) -> JSONParseIssue {
        switch character {
        case "}":
            return afterComma ? .objectTrailingComma : .objectNotClosed
        case ",":
            return .objectRepeatedComma
        case "'":
            return .singleQuotedString
        case "/":
            return isCommentStart() ? .commentNotAllowed : .unexpectedCharacter(character)
        default:
            return .objectKeyMustBeDoubleQuoted
        }
    }

    private func isCommentStart() -> Bool {
        peek() == "/" && (peek(offset: 1) == "/" || peek(offset: 1) == "*")
    }

    private func startsIdentifier(_ identifier: String) -> Bool {
        for (offset, character) in identifier.enumerated() {
            guard peek(offset: offset) == character else {
                return false
            }
        }
        return true
    }

    private func isJSONDigit(_ character: Character) -> Bool {
        ("0"..."9").contains(character)
    }

    private func isJSONNonZeroDigit(_ character: Character) -> Bool {
        ("1"..."9").contains(character)
    }

    private func isJSONHexDigit(_ character: Character) -> Bool {
        ("0"..."9").contains(character)
            || ("a"..."f").contains(character)
            || ("A"..."F").contains(character)
    }

    private func isUnicodeDecimalDigit(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) }
    }

    private func isNonASCIIDecimalDigit(_ character: Character) -> Bool {
        isUnicodeDecimalDigit(character) && !isJSONDigit(character)
    }

    private func isInvalidNumberTrailingCharacter(_ character: Character) -> Bool {
        if isJSONDigit(character) || isNonASCIIDecimalDigit(character) {
            return true
        }

        return character.isLetter || character == "_" || character == "."
    }

    private func peek(offset: Int) -> Character? {
        var cursor = index
        for _ in 0..<offset {
            guard cursor < text.endIndex else {
                return nil
            }
            cursor = text.index(after: cursor)
        }
        guard cursor < text.endIndex else {
            return nil
        }
        return text[cursor]
    }

    private func error(_ issue: JSONParseIssue) -> JSONFormatting.FormattingError {
        .invalidJSON(diagnostic(for: issue))
    }

    private func diagnostic(for issue: JSONParseIssue) -> FormatDiagnostic {
        let diagnosticIndex: String.Index
        switch issue {
        case .containerNotClosed(_, let startIndex, _):
            diagnosticIndex = startIndex
        default:
            diagnosticIndex = index
        }
        return FormatDiagnostic(
            formatName: "JSON",
            message: mappedJSONMessage(issue),
            input: text,
            index: diagnosticIndex
        )
    }

    private func mappedJSONMessage(_ issue: JSONParseIssue) -> String {
        switch issue {
        case .trailingContent:
            return "JSON 根值后还有额外内容"
        case .unexpectedEnd:
            return "输入在值还未完成时结束"
        case .objectTrailingComma:
            return "对象末尾多了逗号"
        case .objectRepeatedComma:
            return "对象成员之间多了逗号或缺少成员"
        case .objectKeyMustBeDoubleQuoted:
            return "对象键必须使用双引号包裹"
        case .objectNotClosed:
            return "对象没有完整闭合"
        case .arrayTrailingComma:
            return "数组末尾多了逗号"
        case .arrayRepeatedComma:
            return "数组元素之间多了逗号或缺少元素"
        case .arrayNotClosed:
            return "数组没有完整闭合"
        case .containerNotClosed(let kind, _, let key):
            if let key, !key.isEmpty {
                return "\(kind == .object ? "对象" : "数组")没有完整闭合（键名 \"\(key)\" 缺少匹配的 '\(kind == .object ? "}" : "]")'）"
            }
            return "\(kind == .object ? "对象" : "数组")没有完整闭合（缺少匹配的 '\(kind == .object ? "}" : "]")'）"
        case .exceededMaxDepth:
            return "JSON 嵌套层级过深，超过最大安全深度 (32 层)"
        case .singleQuotedString:
            return "JSON 字符串和对象键必须使用双引号"
        case .commentNotAllowed:
            return "JSON 不支持注释"
        case .unsupportedLiteral(let literal):
            return "JSON 不支持 \(literal)"
        case .missingColonAfterObjectKey:
            return "对象键后缺少冒号"
        case .missingObjectValue:
            return "对象键后缺少值"
        case .missingCommaOrClose:
            return "成员或元素之间缺少逗号"
        case .invalidString(.unterminated):
            return "字符串没有闭合"
        case .invalidString(.unterminatedEscape):
            return "转义序列没有写完整"
        case .invalidString(.invalidEscape):
            return "字符串中包含非法转义序列"
        case .invalidString(.invalidUnicodeEscape):
            return "Unicode 转义必须是 \\u 后跟 4 位十六进制数字"
        case .invalidString(.missingLowSurrogate):
            return "高位代理项后缺少低位代理项"
        case .invalidString(.invalidLowSurrogate):
            return "低位代理项不合法"
        case .invalidString(.loneLowSurrogate):
            return "低位代理项不能单独出现"
        case .invalidString(.invalidUnicodeScalar):
            return "Unicode 标量不合法"
        case .invalidNumber(.leadingZero):
            return "数字不能有前导零"
        case .invalidNumber(.leadingPlusSign):
            return "JSON 数字前不能写加号"
        case .invalidNumber(.hexLiteral):
            return "JSON 不支持十六进制数字"
        case .invalidNumber(.missingIntegerAfterMinus):
            return "负号后缺少数字"
        case .invalidNumber(.nonASCIIDigit(.integer)):
            return "JSON 数字只能使用半角 0 到 9"
        case .invalidNumber(.nonASCIIDigit(.fraction)):
            return "JSON 小数部分只能使用半角 0 到 9"
        case .invalidNumber(.nonASCIIDigit(.exponent)):
            return "JSON 指数部分只能使用半角 0 到 9"
        case .invalidNumber(.invalidTrailingCharacter(let character)):
            return "数字后面不能直接跟字符 \(character)"
        case .invalidNumber(.invalid):
            return "数字格式不合法"
        case .invalidNumber(.missingFractionDigit):
            return "小数点后缺少数字"
        case .invalidNumber(.missingExponentDigit):
            return "指数部分缺少数字"
        case .incompleteLiteral("true"):
            return "true 字面量没有写完整"
        case .incompleteLiteral("false"):
            return "false 字面量没有写完整"
        case .incompleteLiteral("null"):
            return "null 字面量没有写完整"
        case .invalidString(.unescapedControlCharacter):
            return "字符串中包含未转义的控制字符"
        case .unexpectedCharacter(let character):
            let value = String(character)
            if character.isLetter || character == "_" || character == "$" {
                return "值不能是未加引号的标识符 \(value)"
            }
            return "遇到不能作为 JSON 值开头的字符 \(value)"
        case .incompleteLiteral(let literal):
            return "\(literal) 字面量没有写完整"
        }
    }
}
