import Foundation

public enum MathExpressionEvaluator {
    public enum LiveEvaluation: Equatable {
        case empty
        case incomplete
        case valid(String)
        case invalid(MathError)
    }

    public static func evaluate(_ expression: String) throws -> String {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MathError.emptyExpression
        }

        let tokens = try Lexer.tokenize(trimmed)
        var parser = TokenParser(tokens: tokens)
        let value = try parser.parse()
        guard value.isFinite else {
            throw MathError.nonFiniteResult
        }

        return format(value)
    }

    private static let decimalNotationLowerBound = 1e-9
    private static let decimalNotationUpperBound = 1e16
    private static let maximumSignificantDigits = 15
    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    private static func format(_ value: Double) -> String {
        if value == 0 {
            return "0"
        }

        let magnitude = abs(value)
        if magnitude < decimalNotationLowerBound || magnitude >= decimalNotationUpperBound {
            return String(
                format: "%.15g",
                locale: posixLocale,
                value
            )
            .lowercased()
        }

        if value == value.rounded() {
            return String(Int64(value))
        }

        let formatter = NumberFormatter()
        formatter.locale = posixLocale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.usesSignificantDigits = true
        formatter.minimumSignificantDigits = 1
        formatter.maximumSignificantDigits = maximumSignificantDigits
        formatter.maximumFractionDigits = 340
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    public static func evaluateLiveInput(_ expression: String) -> LiveEvaluation {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .empty
        }

        if isStructurallyIncomplete(trimmed) {
            return .incomplete
        }

        do {
            return .valid(try evaluate(trimmed))
        } catch let error as MathError {
            if isLiveInputIncomplete(error, expression: trimmed) {
                return .incomplete
            }
            return .invalid(error)
        } catch {
            return .invalid(.unexpectedToken)
        }
    }

    public enum MathError: LocalizedError, Equatable {
        case unexpectedCharacter(Character)
        case invalidNumber(String)
        case unknownIdentifier(String)
        case unexpectedToken
        case unexpectedEnd
        case divisionByZero
        case mismatchedParentheses
        case emptyExpression
        case wrongArgumentCount(String, Int)
        case minimumArgumentCount(String, Int)
        case domainError(DomainIssue)
        case nonFiniteResult

        public enum DomainIssue: Equatable, Sendable {
            case nonNegative(String)
            case unitInterval(String)
            case positive(String)
        }

        public var errorDescription: String? {
            switch self {
            case .unexpectedCharacter:
                return "表达式包含不支持的字符。"
            case .invalidNumber:
                return "表达式中的数字格式无效。"
            case .unknownIdentifier:
                return "表达式包含不支持的函数或常量。"
            case .unexpectedToken:
                return "运算符或参数分隔符的位置无效。"
            case .unexpectedEnd:
                return "表达式尚未完成。"
            case .divisionByZero:
                return "除数不能为零。"
            case .mismatchedParentheses:
                return "表达式中的括号不匹配。"
            case .emptyExpression:
                return "表达式为空。"
            case .wrongArgumentCount(let function, let count):
                return "函数 \(function) 需要 \(count) 个参数。"
            case .minimumArgumentCount(let function, let count):
                return "函数 \(function) 至少需要 \(count) 个参数。"
            case .domainError(let issue):
                switch issue {
                case .nonNegative(let function):
                    return "函数 \(function) 的参数不能小于零。"
                case .unitInterval(let function):
                    return "函数 \(function) 的参数必须在 -1 到 1 之间。"
                case .positive(let function):
                    return "函数 \(function) 的参数必须大于零。"
                }
            case .nonFiniteResult:
                return "计算结果超出可表示的有限数值范围。"
            }
        }
    }

    private static func isStructurallyIncomplete(_ expression: String) -> Bool {
        guard let last = expression.last else { return false }
        guard "+-*/%^,(".contains(last) else { return false }

        guard let completedExpression = completionProbe(for: expression) else {
            return false
        }

        return (try? evaluate(completedExpression)) != nil
    }

    private static func completionProbe(for expression: String) -> String? {
        let balance = parenthesisBalance(expression)
        guard balance >= 0 else { return nil }

        let probe: String
        switch expression.last {
        case "+", "-", "*", "/", "%", "^", ",", "(":
            probe = expression + "1"
        default:
            return nil
        }

        return probe + String(repeating: ")", count: balance)
    }

    private static func isLiveInputIncomplete(_ error: MathError, expression: String) -> Bool {
        switch error {
        case .unexpectedEnd:
            return true
        case .mismatchedParentheses:
            return parenthesisBalance(expression) > 0
        case .invalidNumber(let value):
            return expression.hasSuffix(value) && isIncompleteNumber(value)
        case .unknownIdentifier(let value):
            return isKnownIdentifierPrefix(value)
        case .unexpectedToken:
            guard let identifier = trailingIdentifier(in: expression)?.lowercased() else {
                return false
            }
            return Lexer.supportedFunctions.contains(identifier)
        case .emptyExpression, .unexpectedCharacter, .divisionByZero,
             .wrongArgumentCount, .minimumArgumentCount, .domainError, .nonFiniteResult:
            return false
        }
    }

    private static func parenthesisBalance(_ expression: String) -> Int {
        expression.reduce(into: 0) { balance, character in
            if character == "(" {
                balance += 1
            } else if character == ")" {
                balance -= 1
            }
        }
    }

    private static func isIncompleteNumber(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        guard let exponentIndex = lowercased.firstIndex(of: "e") else {
            return value == "." || value.hasSuffix(".")
        }

        let exponent = lowercased[lowercased.index(after: exponentIndex)...]
        return exponent.isEmpty || exponent == "+" || exponent == "-"
    }

    private static func isKnownIdentifierPrefix(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        guard !lowercased.isEmpty else { return false }

        return Lexer.supportedFunctions.contains { $0.hasPrefix(lowercased) }
            || Lexer.constants.keys.contains { $0.hasPrefix(lowercased) }
    }

    private static func trailingIdentifier(in expression: String) -> String? {
        var characters: [Character] = []

        for character in expression.reversed() {
            if character.isLetter || character.isNumber || character == "_" {
                characters.append(character)
            } else if characters.isEmpty, character.isWhitespace {
                continue
            } else {
                break
            }
        }

        guard !characters.isEmpty else { return nil }
        return String(characters.reversed())
    }
}

private enum Token {
    case number(Double)
    case plus
    case minus
    case multiply
    case divide
    case power
    case modulo
    case leftParen
    case rightParen
    case comma
    case function(String)
    case constant(String)
}

private enum Lexer {
    static let supportedFunctions: Set<String> = [
        "sqrt", "sin", "cos", "tan", "log", "ln", "abs",
        "round", "floor", "ceil", "min", "max", "asin", "acos", "atan",
        "sinh", "cosh", "tanh", "exp", "cbrt"
    ]

    static let constants: [String: Double] = [
        "pi": .pi,
        "e": exp(1),
        "phi": (1 + sqrt(5.0)) / 2
    ]

    static func tokenize(_ input: String) throws -> [Token] {
        var tokens: [Token] = []
        var index = input.startIndex

        while index < input.endIndex {
            let character = input[index]

            if character.isWhitespace {
                index = input.index(after: index)
                continue
            }

            if character.isNumber || character == "." {
                let numberText = try scanNumber(in: input, from: &index)
                guard let value = Double(numberText) else {
                    throw MathExpressionEvaluator.MathError.invalidNumber(numberText)
                }
                tokens.append(.number(value))
                continue
            }

            if character.isLetter || character == "_" {
                var name = ""
                while index < input.endIndex, input[index].isLetter || input[index].isNumber || input[index] == "_" {
                    name.append(input[index])
                    index = input.index(after: index)
                }
                let lowercased = name.lowercased()
                if constants[lowercased] != nil {
                    tokens.append(.constant(lowercased))
                } else if supportedFunctions.contains(lowercased) {
                    tokens.append(.function(lowercased))
                } else {
                    throw MathExpressionEvaluator.MathError.unknownIdentifier(name)
                }
                continue
            }

            switch character {
            case "(": tokens.append(.leftParen)
            case ")": tokens.append(.rightParen)
            case ",": tokens.append(.comma)
            case "+": tokens.append(.plus)
            case "-": tokens.append(.minus)
            case "*": tokens.append(.multiply)
            case "/": tokens.append(.divide)
            case "%": tokens.append(.modulo)
            case "^": tokens.append(.power)
            default: throw MathExpressionEvaluator.MathError.unexpectedCharacter(character)
            }

            index = input.index(after: index)
        }

        return tokens
    }

    private static func scanNumber(in input: String, from index: inout String.Index) throws -> String {
        var numberText = ""
        var sawDigit = false
        var sawDecimalPoint = false

        while index < input.endIndex {
            let character = input[index]
            if character.isNumber {
                sawDigit = true
                numberText.append(character)
                index = input.index(after: index)
            } else if character == ".", !sawDecimalPoint {
                sawDecimalPoint = true
                numberText.append(character)
                index = input.index(after: index)
            } else {
                break
            }
        }

        guard sawDigit else {
            throw MathExpressionEvaluator.MathError.invalidNumber(numberText)
        }

        if index < input.endIndex, input[index] == "e" || input[index] == "E" {
            numberText.append(input[index])
            index = input.index(after: index)

            if index < input.endIndex, input[index] == "+" || input[index] == "-" {
                numberText.append(input[index])
                index = input.index(after: index)
            }

            var sawExponentDigit = false
            while index < input.endIndex, input[index].isNumber {
                sawExponentDigit = true
                numberText.append(input[index])
                index = input.index(after: index)
            }

            guard sawExponentDigit else {
                throw MathExpressionEvaluator.MathError.invalidNumber(numberText)
            }
        }

        return numberText
    }
}

private struct TokenParser {
    let tokens: [Token]
    private var position = 0

    init(tokens: [Token]) {
        self.tokens = tokens
    }

    mutating func parse() throws -> Double {
        guard !tokens.isEmpty else {
            throw MathExpressionEvaluator.MathError.emptyExpression
        }
        let value = try parseExpression()
        guard position == tokens.count else {
            throw MathExpressionEvaluator.MathError.unexpectedToken
        }
        return value
    }

    private mutating func parseExpression() throws -> Double {
        var value = try parseTerm()

        while position < tokens.count {
            if case .plus = tokens[position] {
                position += 1
                value += try parseTerm()
            } else if case .minus = tokens[position] {
                position += 1
                value -= try parseTerm()
            } else {
                break
            }
        }

        return value
    }

    private mutating func parseTerm() throws -> Double {
        var value = try parseUnary()

        while position < tokens.count {
            if case .multiply = tokens[position] {
                position += 1
                value *= try parseUnary()
            } else if case .divide = tokens[position] {
                position += 1
                let divisor = try parseUnary()
                guard divisor != 0 else {
                    throw MathExpressionEvaluator.MathError.divisionByZero
                }
                value /= divisor
            } else if case .modulo = tokens[position] {
                position += 1
                let divisor = try parseUnary()
                guard divisor != 0 else {
                    throw MathExpressionEvaluator.MathError.divisionByZero
                }
                value = value.truncatingRemainder(dividingBy: divisor)
            } else {
                break
            }
        }

        return value
    }

    private mutating func parsePower() throws -> Double {
        let base = try parsePrimary()

        if position < tokens.count, case .power = tokens[position] {
            position += 1
            let exponent = try parseUnary()
            return pow(base, exponent)
        }

        return base
    }

    private mutating func parseUnary() throws -> Double {
        if position < tokens.count {
            if case .plus = tokens[position] {
                position += 1
                return try parseUnary()
            } else if case .minus = tokens[position] {
                position += 1
                return -(try parseUnary())
            }
        }

        return try parsePower()
    }

    private mutating func parsePrimary() throws -> Double {
        guard position < tokens.count else {
            throw MathExpressionEvaluator.MathError.unexpectedEnd
        }

        switch tokens[position] {
        case .number(let value):
            position += 1
            return value
        case .constant(let name):
            position += 1
            guard let value = Lexer.constants[name] else {
                throw MathExpressionEvaluator.MathError.unknownIdentifier(name)
            }
            return value
        case .function(let name):
            return try parseFunction(name)
        case .leftParen:
            position += 1
            let value = try parseExpression()
            guard position < tokens.count, case .rightParen = tokens[position] else {
                throw MathExpressionEvaluator.MathError.mismatchedParentheses
            }
            position += 1
            return value
        default:
            throw MathExpressionEvaluator.MathError.unexpectedToken
        }
    }

    private mutating func parseFunction(_ name: String) throws -> Double {
        position += 1
        guard position < tokens.count, case .leftParen = tokens[position] else {
            throw MathExpressionEvaluator.MathError.unexpectedToken
        }
        position += 1

        var args: [Double] = []
        if position < tokens.count, case .rightParen = tokens[position] {
        } else {
            args.append(try parseExpression())
            while position < tokens.count, case .comma = tokens[position] {
                position += 1
                args.append(try parseExpression())
            }
        }

        guard position < tokens.count, case .rightParen = tokens[position] else {
            throw MathExpressionEvaluator.MathError.mismatchedParentheses
        }
        position += 1

        switch name {
        case "sqrt":
            let value = try requireArgs(name, args, 1)
            guard value >= 0 else {
                throw MathExpressionEvaluator.MathError.domainError(.nonNegative(name))
            }
            return sqrt(value)
        case "sin": return sin(try requireArgs(name, args, 1))
        case "cos": return cos(try requireArgs(name, args, 1))
        case "tan": return tan(try requireArgs(name, args, 1))
        case "asin":
            let value = try requireArgs(name, args, 1)
            guard value >= -1, value <= 1 else {
                throw MathExpressionEvaluator.MathError.domainError(.unitInterval(name))
            }
            return asin(value)
        case "acos":
            let value = try requireArgs(name, args, 1)
            guard value >= -1, value <= 1 else {
                throw MathExpressionEvaluator.MathError.domainError(.unitInterval(name))
            }
            return acos(value)
        case "atan": return atan(try requireArgs(name, args, 1))
        case "sinh": return sinh(try requireArgs(name, args, 1))
        case "cosh": return cosh(try requireArgs(name, args, 1))
        case "tanh": return tanh(try requireArgs(name, args, 1))
        case "log":
            let value = try requireArgs(name, args, 1)
            guard value > 0 else {
                throw MathExpressionEvaluator.MathError.domainError(.positive(name))
            }
            return log10(value)
        case "ln":
            let value = try requireArgs(name, args, 1)
            guard value > 0 else {
                throw MathExpressionEvaluator.MathError.domainError(.positive(name))
            }
            return log(value)
        case "abs": return abs(try requireArgs(name, args, 1))
        case "round": return (try requireArgs(name, args, 1)).rounded()
        case "floor": return (try requireArgs(name, args, 1)).rounded(.down)
        case "ceil": return (try requireArgs(name, args, 1)).rounded(.up)
        case "exp": return exp(try requireArgs(name, args, 1))
        case "cbrt": return cbrt(try requireArgs(name, args, 1))
        case "min":
            guard args.count >= 2 else {
                throw MathExpressionEvaluator.MathError.minimumArgumentCount(name, 2)
            }
            return args.min() ?? 0
        case "max":
            guard args.count >= 2 else {
                throw MathExpressionEvaluator.MathError.minimumArgumentCount(name, 2)
            }
            return args.max() ?? 0
        default:
            throw MathExpressionEvaluator.MathError.unknownIdentifier(name)
        }
    }

    private func requireArgs(_ name: String, _ args: [Double], _ count: Int) throws -> Double {
        guard args.count == count else {
            throw MathExpressionEvaluator.MathError.wrongArgumentCount(name, count)
        }
        return args[0]
    }
}
