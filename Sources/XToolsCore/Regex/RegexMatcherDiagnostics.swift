import Foundation
import ICU

/// 正则模式单趟扫描光标:把各判定函数原先各自复制的
/// 「转义载体 → 反斜杠 → 字符组开 → 字符组关 → 组内跳过」前奏收敛成一个状态机。
/// 每个字符位置恰好产生一个事件;早退条件、跨位置取字符与整体跳转
/// 仍由各判定函数自持,以保证判定结果与旧实现逐字节一致。
///
/// 兼容旧实现的「不追踪字符组」扫描:`{`、`}`、`(` 这类目标字符永远不会
/// 以标记事件出现,因此同时消费 `.plain` 与 `.inClass` 两种事件,
/// 就等价于旧版「除转义载体外一律参与判定」的类无关扫描。
private struct PatternCursor {
    enum Event {
        /// 被反斜杠吞掉的载体字符。
        case escaped(Character)
        /// 反斜杠本身。
        case backslash
        /// 进入(或嵌套重入)字符组的 "["。
        case classOpen
        /// 关闭字符组的 "]"。
        case classClose
        /// 字符组内的普通字符。
        case inClass(Character)
        /// 字符组外的普通字符(含不在字符组内的 "]")。
        case plain(Character)

        /// 事件对应的原文首字符,供追踪「上一个字符」的判定复用。
        var character: Character {
            switch self {
            case .escaped(let character), .inClass(let character), .plain(let character):
                return character
            case .backslash:
                return "\\"
            case .classOpen:
                return "["
            case .classClose:
                return "]"
            }
        }
    }

    let characters: [Character]
    private(set) var index: Int
    private(set) var escaped = false
    private(set) var inClass = false

    init(_ characters: [Character], startingAt index: Int = 0) {
        self.characters = characters
        self.index = index
    }

    /// 推进一步;扫描结束返回 nil。结尾悬空的单独 "\" 不产生额外事件,
    /// 其存在可通过 `escaped` 终值判定。
    mutating func next() -> (event: Event, index: Int)? {
        guard index < characters.count else {
            return nil
        }

        let position = index
        let character = characters[position]
        index += 1

        if escaped {
            escaped = false
            return (.escaped(character), position)
        }
        if character == "\\" {
            escaped = true
            return (.backslash, position)
        }
        if character == "[" {
            inClass = true
            return (.classOpen, position)
        }
        if character == "]", inClass {
            inClass = false
            return (.classClose, position)
        }
        if inClass {
            return (.inClass(character), position)
        }
        return (.plain(character), position)
    }

    /// 消费完整个 `{...}`、`(?...)` 等结构后整体跳转;转义与字符组状态保持不变。
    mutating func jump(to index: Int) {
        self.index = index
    }
}

extension RegexMatcher {
    static func classifyPatternError(for pattern: String) -> MatcherError {
        if hasVariableLengthLookbehind(pattern) {
            return .compatibilityBoundary(
                "当前正则引擎不支持变长后顾。"
            )
        }

        if hasDanglingEscape(pattern) {
            return .invalidPattern("转义序列不完整。")
        }

        if hasUnclosedCharacterClass(pattern) {
            return .invalidPattern("字符组未闭合。")
        }

        if hasUnmatchedClosingParenthesis(pattern) {
            return .invalidPattern("右括号缺少对应的左括号。")
        }

        if hasUnclosedParenthesis(pattern) {
            return .invalidPattern("括号未闭合。")
        }

        if hasMissingQuantifierLowerBound(pattern) {
            return .invalidPattern("量词写法不完整。")
        }

        if hasReversedQuantifierRange(pattern) {
            return .invalidPattern("量词范围无效。")
        }

        if hasInvalidCharacterClassRange(pattern) {
            return .invalidPattern("字符组范围顺序无效。")
        }

        if hasUnsupportedGroupSyntax(pattern) {
            return .invalidPattern("正则引擎不支持 (?P<...) 分组写法，命名分组应写成 (?<名称>...)。")
        }

        if hasUnclosedQuantifierBrace(pattern) {
            return .invalidPattern("量词缺少右花括号。")
        }

        if hasLeadingQuantifierWithoutTarget(pattern) {
            return .invalidPattern("量词前缺少表达式。")
        }

        return .invalidPattern(
            "正则表达式格式无效。"
        )
    }

    /// ICU 只接受 `(?<名称>...)` 形式的命名分组；Python/PCRE 的 `(?P<名称>...)`
    /// 会编译失败，但它并不是「量词位置」问题，需要单独说明。
    static func hasUnsupportedGroupSyntax(_ pattern: String) -> Bool {
        pattern.contains("(?P<")
    }

    /// `a{` 这类缺少右花括号的量词在旧实现里只会落到笼统的「格式无效」。
    static func hasUnclosedQuantifierBrace(_ pattern: String) -> Bool {
        let characters = Array(pattern)
        var cursor = PatternCursor(characters)

        while let step = cursor.next() {
            guard case .plain("{") = step.event,
                  unescapedClosingBraceIndex(in: characters, startingAt: step.index + 1) == nil
            else {
                continue
            }
            return true
        }

        return false
    }

    static func hasVariableLengthLookbehind(_ pattern: String) -> Bool {
        let characters = Array(pattern)
        var cursor = PatternCursor(characters)

        while let step = cursor.next() {
            // 旧实现不追踪字符组:`(` 只要不是转义载体就参与判定,组内组外 alike。
            let isOpenParenthesis: Bool
            switch step.event {
            case .plain("("), .inClass("("):
                isOpenParenthesis = true
            default:
                isOpenParenthesis = false
            }

            guard isOpenParenthesis,
                  step.index + 3 < characters.count,
                  characters[step.index + 1] == "?" else {
                continue
            }

            let isPositiveLookbehind = characters[step.index + 2] == "<" && characters[step.index + 3] == "="
            let isNegativeLookbehind = characters[step.index + 2] == "<" && characters[step.index + 3] == "!"
            guard isPositiveLookbehind || isNegativeLookbehind else {
                continue
            }

            let bodyStart = step.index + 4
            guard let bodyEnd = closingParenthesisIndex(in: characters, startingAt: bodyStart) else {
                return false
            }

            let body = String(characters[bodyStart..<bodyEnd])
            if hasVariableLengthQuantifier(in: body) {
                return true
            }

            cursor.jump(to: bodyEnd + 1)
        }

        return false
    }

    static func closingParenthesisIndex(in characters: [Character], startingAt start: Int) -> Int? {
        var cursor = PatternCursor(characters, startingAt: start)
        var depth = 1

        while let step = cursor.next() {
            switch step.event {
            case .plain("("):
                depth += 1
            case .plain(")"):
                depth -= 1
                if depth == 0 {
                    return step.index
                }
            default:
                break
            }
        }

        return nil
    }

    static func hasVariableLengthQuantifier(in pattern: String) -> Bool {
        let characters = Array(pattern)
        var cursor = PatternCursor(characters)
        var previous: Character?

        while let step = cursor.next() {
            guard case .plain(let character) = step.event else {
                previous = step.event.character
                continue
            }

            if character == "*" || character == "+" {
                return true
            }

            if character == "?", previous != "(" {
                return true
            }

            if character == "{",
               let closingBraceIndex = unescapedClosingBraceIndex(in: characters, startingAt: step.index + 1) {
                let contents = String(characters[(step.index + 1)..<closingBraceIndex])
                if quantifierContentsAreVariable(contents) {
                    return true
                }
                previous = "}"
                cursor.jump(to: closingBraceIndex + 1)
                continue
            }

            previous = character
        }

        return false
    }

    static func unescapedClosingBraceIndex(in characters: [Character], startingAt start: Int) -> Int? {
        var cursor = PatternCursor(characters, startingAt: start)

        while let step = cursor.next() {
            switch step.event {
            case .plain("}"), .inClass("}"):
                return step.index
            default:
                break
            }
        }

        return nil
    }

    static func quantifierContentsAreVariable(_ contents: String) -> Bool {
        let parts = contents.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }

        guard let lowerBound = Int(parts[0]), !parts[0].isEmpty else {
            return true
        }
        guard !parts[1].isEmpty, let upperBound = Int(parts[1]) else {
            return true
        }
        return lowerBound != upperBound
    }

    static func hasDanglingEscape(_ pattern: String) -> Bool {
        var cursor = PatternCursor(Array(pattern))
        while cursor.next() != nil {}
        return cursor.escaped
    }

    static func hasUnclosedCharacterClass(_ pattern: String) -> Bool {
        var cursor = PatternCursor(Array(pattern))
        while cursor.next() != nil {}
        return cursor.inClass
    }

    static func hasUnclosedParenthesis(_ pattern: String) -> Bool {
        parenthesisBalance(pattern) > 0
    }

    static func hasUnmatchedClosingParenthesis(_ pattern: String) -> Bool {
        parenthesisBalance(pattern) < 0
    }

    static func parenthesisBalance(_ pattern: String) -> Int {
        var cursor = PatternCursor(Array(pattern))
        var depth = 0

        while let step = cursor.next() {
            switch step.event {
            case .plain("("):
                depth += 1
            case .plain(")"):
                depth -= 1
                if depth < 0 {
                    return depth
                }
            default:
                break
            }
        }

        return depth
    }

    static func hasReversedQuantifierRange(_ pattern: String) -> Bool {
        let characters = Array(pattern)
        var cursor = PatternCursor(characters)

        while let step = cursor.next() {
            // 旧实现不追踪字符组:组内的 `{3,1}` 同样参与判定。
            let isQuantifierOpen: Bool
            switch step.event {
            case .plain("{"), .inClass("{"):
                isQuantifierOpen = true
            default:
                isQuantifierOpen = false
            }
            guard isQuantifierOpen else {
                continue
            }

            var index = step.index + 1
            var lower = ""
            while index < characters.count, characters[index].isNumber {
                lower.append(characters[index])
                index += 1
            }
            guard index < characters.count, characters[index] == "," else {
                continue
            }
            index += 1
            var upper = ""
            while index < characters.count, characters[index].isNumber {
                upper.append(characters[index])
                index += 1
            }
            guard index < characters.count, characters[index] == "}",
                  let lowerValue = Int(lower),
                  let upperValue = Int(upper) else {
                continue
            }
            if lowerValue > upperValue {
                return true
            }
            cursor.jump(to: index + 1)
        }

        return false
    }

    static func hasMissingQuantifierLowerBound(_ pattern: String) -> Bool {
        let characters = Array(pattern)
        var cursor = PatternCursor(characters)

        while let step = cursor.next() {
            // 旧实现的循环条件是 `index + 1 < count`,最后一个字符不参与判定。
            guard case .plain("{") = step.event,
                  step.index + 1 < characters.count,
                  characters[step.index + 1] == "," else {
                continue
            }
            return true
        }

        return false
    }

    static func hasInvalidCharacterClassRange(_ pattern: String) -> Bool {
        let characters = Array(pattern)
        var cursor = PatternCursor(characters)

        while let step = cursor.next() {
            guard case .inClass("-") = step.event,
                  step.index > 0,
                  step.index + 1 < characters.count else {
                continue
            }

            let lower = characters[step.index - 1]
            let upper = characters[step.index + 1]
            if lower != "[",
               upper != "]",
               lower != "\\",
               upper != "\\",
               lower.isASCII,
               upper.isASCII,
               lower > upper {
                return true
            }
        }

        return false
    }

    static func hasLeadingQuantifierWithoutTarget(_ pattern: String) -> Bool {
        var cursor = PatternCursor(Array(pattern))
        var previousSignificant: Character?

        while let step = cursor.next() {
            guard case .plain(let character) = step.event else {
                previousSignificant = step.event.character
                continue
            }

            if character == "*" || character == "+" || character == "?" {
                if previousSignificant == nil || previousSignificant == "|" {
                    return true
                }
                // `(?` 是分组或标志前缀（如 (?i)、(?<名称>...)），不是量词；
                // 而 `(*`、`(+` 仍然是缺少左侧表达式的量词。
                if previousSignificant == "(", character != "?" {
                    return true
                }
            }

            previousSignificant = character
        }

        return false
    }

    /// 提取命名分组名;与上面的判定共用同一个扫描光标。
    static func namedCaptureNames(in pattern: String) -> [String] {
        let characters = Array(pattern)
        var names: [String] = []
        var cursor = PatternCursor(characters)

        while let step = cursor.next() {
            guard case .plain("(") = step.event,
                  step.index + 3 < characters.count,
                  characters[step.index + 1] == "?",
                  characters[step.index + 2] == "<" else {
                continue
            }

            let firstNameCharacter = characters[step.index + 3]
            if firstNameCharacter == "=" || firstNameCharacter == "!" {
                continue
            }

            var nameCharacters: [Character] = []
            var nameIndex = step.index + 3
            while nameIndex < characters.count, characters[nameIndex] != ">" {
                nameCharacters.append(characters[nameIndex])
                nameIndex += 1
            }

            if nameIndex < characters.count, !nameCharacters.isEmpty {
                let name = String(nameCharacters)
                if !names.contains(name) {
                    names.append(name)
                }
                cursor.jump(to: nameIndex)
            }
        }

        return names
    }

}
