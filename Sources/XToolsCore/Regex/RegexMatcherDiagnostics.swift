import Foundation
import ICU

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

        if hasLeadingQuantifierWithoutTarget(pattern) {
            return .invalidPattern("量词前缺少表达式。")
        }

        return .invalidPattern(
            "正则表达式格式无效。"
        )
    }

    static func hasVariableLengthLookbehind(_ pattern: String) -> Bool {
        let characters = Array(pattern)
        var index = 0

        while index < characters.count {
            if characters[index] == "\\" {
                index += 2
                continue
            }

            guard index + 3 < characters.count, characters[index] == "(", characters[index + 1] == "?" else {
                index += 1
                continue
            }

            let isPositiveLookbehind = characters[index + 2] == "<" && characters[index + 3] == "="
            let isNegativeLookbehind = characters[index + 2] == "<" && characters[index + 3] == "!"
            guard isPositiveLookbehind || isNegativeLookbehind else {
                index += 1
                continue
            }

            let bodyStart = index + 4
            guard let bodyEnd = closingParenthesisIndex(in: characters, startingAt: bodyStart) else {
                return false
            }

            let body = String(characters[bodyStart..<bodyEnd])
            if hasVariableLengthQuantifier(in: body) {
                return true
            }

            index = bodyEnd + 1
        }

        return false
    }

    static func closingParenthesisIndex(in characters: [Character], startingAt start: Int) -> Int? {
        var escaped = false
        var inClass = false
        var depth = 1
        var index = start

        while index < characters.count {
            let character = characters[index]
            if escaped {
                escaped = false
                index += 1
                continue
            }
            if character == "\\" {
                escaped = true
                index += 1
                continue
            }
            if character == "[" {
                inClass = true
                index += 1
                continue
            }
            if character == "]", inClass {
                inClass = false
                index += 1
                continue
            }
            if inClass {
                index += 1
                continue
            }
            if character == "(" {
                depth += 1
            } else if character == ")" {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }
            index += 1
        }

        return nil
    }

    static func hasVariableLengthQuantifier(in pattern: String) -> Bool {
        let characters = Array(pattern)
        var escaped = false
        var inClass = false
        var previous: Character?
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if escaped {
                escaped = false
                previous = character
                index += 1
                continue
            }
            if character == "\\" {
                escaped = true
                previous = character
                index += 1
                continue
            }
            if character == "[" {
                inClass = true
                previous = character
                index += 1
                continue
            }
            if character == "]", inClass {
                inClass = false
                previous = character
                index += 1
                continue
            }
            if inClass {
                previous = character
                index += 1
                continue
            }

            if character == "*" || character == "+" {
                return true
            }

            if character == "?", previous != "(" {
                return true
            }

            if character == "{", let closingBraceIndex = unescapedClosingBraceIndex(in: characters, startingAt: index + 1) {
                let contents = String(characters[(index + 1)..<closingBraceIndex])
                if quantifierContentsAreVariable(contents) {
                    return true
                }
                previous = "}"
                index = closingBraceIndex + 1
                continue
            }

            previous = character
            index += 1
        }

        return false
    }

    static func unescapedClosingBraceIndex(in characters: [Character], startingAt start: Int) -> Int? {
        var escaped = false
        var index = start

        while index < characters.count {
            let character = characters[index]
            if escaped {
                escaped = false
                index += 1
                continue
            }
            if character == "\\" {
                escaped = true
                index += 1
                continue
            }
            if character == "}" {
                return index
            }
            index += 1
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
        var escaped = false
        for character in pattern {
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            }
        }
        return escaped
    }

    static func hasUnclosedCharacterClass(_ pattern: String) -> Bool {
        var escaped = false
        var inClass = false

        for character in pattern {
            if escaped {
                escaped = false
                continue
            }
            if character == "\\" {
                escaped = true
                continue
            }
            if character == "[" {
                inClass = true
            } else if character == "]", inClass {
                inClass = false
            }
        }

        return inClass
    }

    static func hasUnclosedParenthesis(_ pattern: String) -> Bool {
        parenthesisBalance(pattern) > 0
    }

    static func hasUnmatchedClosingParenthesis(_ pattern: String) -> Bool {
        parenthesisBalance(pattern) < 0
    }

    static func parenthesisBalance(_ pattern: String) -> Int {
        var escaped = false
        var inClass = false
        var depth = 0

        for character in pattern {
            if escaped {
                escaped = false
                continue
            }
            if character == "\\" {
                escaped = true
                continue
            }
            if character == "[" {
                inClass = true
                continue
            }
            if character == "]", inClass {
                inClass = false
                continue
            }
            guard !inClass else { continue }

            if character == "(" {
                depth += 1
            } else if character == ")" {
                depth -= 1
                if depth < 0 { return depth }
            }
        }

        return depth
    }

    static func hasReversedQuantifierRange(_ pattern: String) -> Bool {
        let characters = Array(pattern)
        var escaped = false
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if escaped {
                escaped = false
                index += 1
                continue
            }
            if character == "\\" {
                escaped = true
                index += 1
                continue
            }
            guard character == "{" else {
                index += 1
                continue
            }

            var cursor = index + 1
            var lower = ""
            while cursor < characters.count, characters[cursor].isNumber {
                lower.append(characters[cursor])
                cursor += 1
            }
            guard cursor < characters.count, characters[cursor] == "," else {
                index += 1
                continue
            }
            cursor += 1
            var upper = ""
            while cursor < characters.count, characters[cursor].isNumber {
                upper.append(characters[cursor])
                cursor += 1
            }
            guard cursor < characters.count, characters[cursor] == "}",
                  let lowerValue = Int(lower),
                  let upperValue = Int(upper) else {
                index += 1
                continue
            }
            if lowerValue > upperValue {
                return true
            }
            index = cursor + 1
        }

        return false
    }

    static func hasMissingQuantifierLowerBound(_ pattern: String) -> Bool {
        let characters = Array(pattern)
        var escaped = false
        var inClass = false
        var index = 0

        while index + 1 < characters.count {
            let character = characters[index]
            if escaped {
                escaped = false
                index += 1
                continue
            }
            if character == "\\" {
                escaped = true
                index += 1
                continue
            }
            if character == "[" {
                inClass = true
                index += 1
                continue
            }
            if character == "]", inClass {
                inClass = false
                index += 1
                continue
            }
            guard !inClass else {
                index += 1
                continue
            }

            if character == "{", characters[index + 1] == "," {
                return true
            }

            index += 1
        }

        return false
    }

    static func hasInvalidCharacterClassRange(_ pattern: String) -> Bool {
        let characters = Array(pattern)
        var escaped = false
        var inClass = false
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if escaped {
                escaped = false
                index += 1
                continue
            }
            if character == "\\" {
                escaped = true
                index += 1
                continue
            }
            if character == "[" {
                inClass = true
                index += 1
                continue
            }
            if character == "]", inClass {
                inClass = false
                index += 1
                continue
            }

            if inClass,
               character == "-",
               index > 0,
               index + 1 < characters.count {
                let lower = characters[index - 1]
                let upper = characters[index + 1]
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

            index += 1
        }

        return false
    }

    static func hasLeadingQuantifierWithoutTarget(_ pattern: String) -> Bool {
        let characters = Array(pattern)
        var escaped = false
        var inClass = false
        var previousSignificant: Character?

        for character in characters {
            if escaped {
                escaped = false
                previousSignificant = character
                continue
            }
            if character == "\\" {
                escaped = true
                previousSignificant = character
                continue
            }
            if character == "[" {
                inClass = true
                previousSignificant = character
                continue
            }
            if character == "]", inClass {
                inClass = false
                previousSignificant = character
                continue
            }
            guard !inClass else {
                previousSignificant = character
                continue
            }

            if character == "*" || character == "+" || character == "?" {
                if previousSignificant == nil || previousSignificant == "(" || previousSignificant == "|" {
                    return true
                }
            }

            previousSignificant = character
        }

        return false
    }

}
