import Foundation
import ICU

private struct ICURegexMatchContext {
    let totalStepLimit: Int32
    var totalSteps: Int32 = 0
    var currentOperationSteps: Int32 = 0
}

private func icuRegexMatchCallback(_ rawContext: UnsafeRawPointer?, _ steps: Int32) -> Int8 {
    guard let rawContext else {
        return 0
    }

    let context = UnsafeMutableRawPointer(mutating: rawContext)
        .assumingMemoryBound(to: ICURegexMatchContext.self)
    guard steps >= context.pointee.currentOperationSteps else {
        return 0
    }

    let delta = steps - context.pointee.currentOperationSteps
    context.pointee.currentOperationSteps = steps
    guard delta <= context.pointee.totalStepLimit - context.pointee.totalSteps else {
        return 0
    }

    context.pointee.totalSteps += delta
    return 1
}

public enum RegexMatcher {
    public struct Preset: Equatable, Identifiable, Sendable {
        public let id: String
        public let title: String
        public let pattern: String
        public let flags: String
        public let examples: [Example]

        public var exampleText: String {
            examples.map(\.text).joined(separator: "\n")
        }

        public init(id: String, title: String, pattern: String, flags: String = "g", examples: [Example]) {
            self.id = id
            self.title = title
            self.pattern = pattern
            self.flags = flags
            self.examples = examples
        }
    }

    public struct Example: Equatable, Sendable {
        public let text: String
        public let shouldMatch: Bool

        public init(_ text: String, shouldMatch: Bool) {
            self.text = text
            self.shouldMatch = shouldMatch
        }
    }

    public struct Report: Equatable, Sendable {
        public let pattern: String
        public let flags: String
        public let matches: [Match]
        public let statistics: Statistics
    }

    public struct Match: Equatable, Sendable {
        public let value: String
        public let index: Int
        public let end: Int
        public let captures: [Capture]
        public let groups: [Capture]
    }

    public struct Capture: Equatable, Sendable {
        public let name: String
        public let value: String
        public let start: Int
        public let end: Int

        public init(name: String, value: String, start: Int, end: Int) {
            self.name = name
            self.value = value
            self.start = start
            self.end = end
        }
    }

    public struct Statistics: Equatable, Sendable {
        public let matchCount: Int
        public let captureCount: Int
        public let namedGroupCount: Int
        public let matchedCharacterCount: Int
    }

    public struct Budget: Equatable, Sendable {
        public static let standard = Budget(
            maxPatternUTF16Length: 16_384,
            maxTextUTF16Length: 500_000,
            matchTimeLimit: 500,
            backtrackStackLimitBytes: 8 * 1_024 * 1_024,
            maxMatchCount: 10_000,
            maxCaptureCount: 50_000,
            maxResultUTF16Length: 2_000_000
        )

        public let maxPatternUTF16Length: Int
        public let maxTextUTF16Length: Int
        public let matchTimeLimit: Int32
        public let backtrackStackLimitBytes: Int32
        public let maxMatchCount: Int
        public let maxCaptureCount: Int
        public let maxResultUTF16Length: Int

        public init(
            maxPatternUTF16Length: Int,
            maxTextUTF16Length: Int,
            matchTimeLimit: Int32,
            backtrackStackLimitBytes: Int32,
            maxMatchCount: Int,
            maxCaptureCount: Int = 50_000,
            maxResultUTF16Length: Int = 2_000_000
        ) {
            precondition(maxPatternUTF16Length > 0)
            precondition(maxTextUTF16Length > 0)
            precondition(matchTimeLimit > 0)
            precondition(backtrackStackLimitBytes > 0)
            precondition(maxMatchCount > 0)
            precondition(maxCaptureCount > 0)
            precondition(maxResultUTF16Length > 0)

            self.maxPatternUTF16Length = maxPatternUTF16Length
            self.maxTextUTF16Length = maxTextUTF16Length
            self.matchTimeLimit = matchTimeLimit
            self.backtrackStackLimitBytes = backtrackStackLimitBytes
            self.maxMatchCount = maxMatchCount
            self.maxCaptureCount = maxCaptureCount
            self.maxResultUTF16Length = maxResultUTF16Length
        }
    }

    public enum MatcherError: Error, Equatable, LocalizedError, Sendable {
        case unsupportedFlag(String)
        case compatibilityBoundary(String)
        case invalidPattern(String)
        case patternTooLong
        case textTooLong
        case timeLimitExceeded
        case stackLimitExceeded
        case resourceLimitExceeded
        case matchCountLimitExceeded
        case captureCountLimitExceeded
        case resultSizeLimitExceeded
        case internalFailure

        public var errorDescription: String? {
            switch self {
            case .unsupportedFlag(let flag):
                return "不支持的正则标志：\(flag)。当前支持 g、i、m、s、x。"
            case .compatibilityBoundary(let message):
                return message
            case .invalidPattern(let message):
                return message
            case .patternTooLong:
                return "正则表达式过长。"
            case .textTooLong:
                return "测试文本过长。"
            case .timeLimitExceeded:
                return "正则表达式计算量过大。"
            case .stackLimitExceeded, .resourceLimitExceeded:
                return "正则表达式计算量过大。"
            case .matchCountLimitExceeded:
                return "匹配结果过多。"
            case .captureCountLimitExceeded:
                return "捕获结果过多。"
            case .resultSizeLimitExceeded:
                return "匹配结果内容过多。"
            case .internalFailure:
                return "正则匹配失败。"
            }
        }
    }

    public static func analyze(
        pattern: String,
        in text: String,
        flags: String = "g",
        budget: Budget = .standard
    ) throws -> Report {
        let normalizedFlags = try normalizeFlags(flags)
        guard !pattern.isEmpty else {
            return Report(pattern: pattern, flags: normalizedFlags, matches: [], statistics: emptyStatistics)
        }

        guard pattern.utf16.count <= budget.maxPatternUTF16Length else {
            throw MatcherError.patternTooLong
        }
        guard text.utf16.count <= budget.maxTextUTF16Length else {
            throw MatcherError.textTooLong
        }

        let namedGroups = namedCaptureNames(in: pattern)
        let matches = try executeMatches(
            pattern: pattern,
            text: text,
            flags: normalizedFlags,
            namedGroups: namedGroups,
            budget: budget
        )

        return Report(
            pattern: pattern,
            flags: normalizedFlags,
            matches: matches,
            statistics: Statistics(
                matchCount: matches.count,
                captureCount: matches.reduce(0) { $0 + $1.captures.count },
                namedGroupCount: matches.reduce(0) { $0 + $1.groups.count },
                matchedCharacterCount: matches.reduce(0) { $0 + $1.value.count }
            )
        )
    }

    public static func summaryText(for report: Report) -> String {
        guard !report.matches.isEmpty else {
            return "匹配到 0 处"
        }

        var lines = ["匹配到 \(report.statistics.matchCount) 处", ""]
        for (index, match) in report.matches.enumerated() {
            lines.append("匹配 #\(index + 1)：范围 [\(match.index), \(match.end))；文本 \(match.value)")

            for capture in match.captures {
                lines.append("  捕获 \(capture.name)：范围 [\(capture.start), \(capture.end))；文本 \(capture.value)")
            }

            for group in match.groups {
                lines.append("  命名组 \(group.name)：范围 [\(group.start), \(group.end))；文本 \(group.value)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static let emptyStatistics = Statistics(
        matchCount: 0,
        captureCount: 0,
        namedGroupCount: 0,
        matchedCharacterCount: 0
    )

    /// UI / preset matching: unique non-whitespace flags, preferred `gimsx` order,
    /// then any unknown flags in first-seen order. Does not throw — execution still
    /// validates via `normalizeFlags(_:)`.
    public static func normalizeFlagsForUI(_ flags: String) -> String {
        let preferredOrder = Array("gimsx")
        let uniqueFlags = flags.reduce(into: [Character]()) { result, flag in
            if !flag.isWhitespace, !result.contains(flag) {
                result.append(flag)
            }
        }
        let orderedKnownFlags = preferredOrder.filter { uniqueFlags.contains($0) }
        let unknownFlags = uniqueFlags.filter { !preferredOrder.contains($0) }
        return String(orderedKnownFlags + unknownFlags)
    }

    private static func normalizeFlags(_ flags: String) throws -> String {
        let supportedFlags = Set("gimsx")
        var normalized: [Character] = []

        for flag in flags where !flag.isWhitespace {
            guard supportedFlags.contains(flag) else {
                throw MatcherError.unsupportedFlag(String(flag))
            }
            if !normalized.contains(flag) {
                normalized.append(flag)
            }
        }

        return String(normalized)
    }

    private static func executeMatches(
        pattern: String,
        text: String,
        flags: String,
        namedGroups: [String],
        budget: Budget
    ) throws -> [Match] {
        let patternUTF16 = Array(pattern.utf16)
        let textUTF16 = Array(text.utf16)

        // ICU retains the subject pointer, so every native operation must finish inside these scopes.
        return try patternUTF16.withUnsafeBufferPointer { patternBuffer in
            try textUTF16.withUnsafeBufferPointer { textBuffer in
                var createStatus = U_ZERO_ERROR
                let expression = uregex_open(
                    patternBuffer.baseAddress,
                    Int32(patternBuffer.count),
                    expressionFlags(for: flags),
                    nil,
                    &createStatus
                )
                guard !isICUFailure(createStatus), let expression else {
                    if let expression {
                        uregex_close(expression)
                    }
                    throw matcherError(for: createStatus, pattern: pattern, compiling: true)
                }
                var expressionNeedsClose = true
                defer {
                    if expressionNeedsClose {
                        uregex_close(expression)
                    }
                }

                var setupStatus = U_ZERO_ERROR
                uregex_setText(expression, textBuffer.baseAddress, Int32(textBuffer.count), &setupStatus)
                uregex_setTimeLimit(expression, budget.matchTimeLimit, &setupStatus)
                uregex_setStackLimit(expression, budget.backtrackStackLimitBytes, &setupStatus)
                let groupCount = Int(uregex_groupCount(expression, &setupStatus))
                guard !isICUFailure(setupStatus), groupCount >= 0 else {
                    throw matcherError(for: setupStatus, pattern: pattern)
                }

                var namedGroupNumbers: [(String, Int32)] = []
                for name in namedGroups {
                    let nameUTF16 = Array(name.utf16)
                    var groupStatus = U_ZERO_ERROR
                    let groupNumber = nameUTF16.withUnsafeBufferPointer { buffer in
                        uregex_groupNumberFromName(
                            expression,
                            buffer.baseAddress,
                            Int32(buffer.count),
                            &groupStatus
                        )
                    }
                    if groupStatus == U_REGEX_INVALID_CAPTURE_GROUP_NAME {
                        continue
                    }
                    guard !isICUFailure(groupStatus), groupNumber > 0 else {
                        throw matcherError(for: groupStatus, pattern: pattern)
                    }
                    namedGroupNumbers.append((name, groupNumber))
                }

                var matchContext = ICURegexMatchContext(totalStepLimit: budget.matchTimeLimit)
                return try withUnsafeMutablePointer(to: &matchContext) { context in
                    defer {
                        uregex_close(expression)
                        expressionNeedsClose = false
                    }

                    var callbackStatus = U_ZERO_ERROR
                    uregex_setMatchCallback(
                        expression,
                        icuRegexMatchCallback,
                        UnsafeRawPointer(context),
                        &callbackStatus
                    )
                    guard !isICUFailure(callbackStatus) else {
                        throw matcherError(for: callbackStatus, pattern: pattern)
                    }

                    var matches: [Match] = []
                    var captureCount = 0
                    var resultUTF16Length = 0
                    var hasStarted = false

                    func accountForResult(_ capture: Capture, isCapture: Bool) throws {
                        if isCapture {
                            guard captureCount < budget.maxCaptureCount else {
                                throw MatcherError.captureCountLimitExceeded
                            }
                            captureCount += 1
                        }

                        let valueLength = capture.value.utf16.count
                        guard valueLength <= budget.maxResultUTF16Length - resultUTF16Length else {
                            throw MatcherError.resultSizeLimitExceeded
                        }
                        resultUTF16Length += valueLength
                    }

                    while true {
                        context.pointee.currentOperationSteps = 0
                        var findStatus = U_ZERO_ERROR
                        let found: Int8
                        if hasStarted {
                            found = uregex_findNext(expression, &findStatus)
                        } else {
                            hasStarted = true
                            found = uregex_find(expression, 0, &findStatus)
                        }
                        guard !isICUFailure(findStatus) else {
                            throw matcherError(for: findStatus, pattern: pattern)
                        }
                        guard found != 0 else {
                            break
                        }
                        guard matches.count < budget.maxMatchCount else {
                            throw MatcherError.matchCountLimitExceeded
                        }

                        guard let fullMatch = try capture(
                            name: "0",
                            groupNumber: 0,
                            expression: expression,
                            in: text
                        ) else {
                            throw MatcherError.internalFailure
                        }
                        try accountForResult(fullMatch, isCapture: false)

                        var captures: [Capture] = []
                        captures.reserveCapacity(groupCount)
                        if groupCount > 0 {
                            for index in 1...groupCount {
                                if let capture = try capture(
                                    name: "\(index)",
                                    groupNumber: Int32(index),
                                    expression: expression,
                                    in: text
                                ) {
                                    try accountForResult(capture, isCapture: true)
                                    captures.append(capture)
                                }
                            }
                        }

                        var groups: [Capture] = []
                        groups.reserveCapacity(namedGroupNumbers.count)
                        for (name, groupNumber) in namedGroupNumbers {
                            if let capture = try capture(
                                name: name,
                                groupNumber: groupNumber,
                                expression: expression,
                                in: text
                            ) {
                                try accountForResult(capture, isCapture: true)
                                groups.append(capture)
                            }
                        }

                        matches.append(
                            Match(
                                value: fullMatch.value,
                                index: fullMatch.start,
                                end: fullMatch.end,
                                captures: captures,
                                groups: groups
                            )
                        )

                        if !flags.contains("g") {
                            break
                        }
                    }

                    return matches
                }
            }
        }
    }

    private static func capture(
        name: String,
        groupNumber: Int32,
        expression: OpaquePointer,
        in text: String
    ) throws -> Capture? {
        var status = U_ZERO_ERROR
        let start = uregex_start(expression, groupNumber, &status)
        let end = uregex_end(expression, groupNumber, &status)
        guard !isICUFailure(status) else {
            throw matcherError(for: status, pattern: "")
        }
        guard start >= 0, end >= start else {
            return nil
        }

        let range = NSRange(location: Int(start), length: Int(end - start))
        guard let stringRange = Range(range, in: text) else {
            throw MatcherError.internalFailure
        }

        return Capture(
            name: name,
            value: String(text[stringRange]),
            start: text.distance(from: text.startIndex, to: stringRange.lowerBound),
            end: text.distance(from: text.startIndex, to: stringRange.upperBound)
        )
    }

    private static func expressionFlags(for flags: String) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains("i") { result |= UInt32(UREGEX_CASE_INSENSITIVE.rawValue) }
        if flags.contains("m") { result |= UInt32(UREGEX_MULTILINE.rawValue) }
        if flags.contains("s") { result |= UInt32(UREGEX_DOTALL.rawValue) }
        if flags.contains("x") { result |= UInt32(UREGEX_COMMENTS.rawValue) }
        return result
    }

    private static func isICUFailure(_ status: UErrorCode) -> Bool {
        status.rawValue > U_ZERO_ERROR.rawValue
    }

    private static func matcherError(
        for status: UErrorCode,
        pattern: String,
        compiling: Bool = false
    ) -> MatcherError {
        switch status {
        case U_REGEX_TIME_OUT, U_REGEX_STOPPED_BY_CALLER:
            return .timeLimitExceeded
        case U_REGEX_STACK_OVERFLOW:
            return .stackLimitExceeded
        case U_MEMORY_ALLOCATION_ERROR:
            return .resourceLimitExceeded
        default:
            if compiling,
               status.rawValue >= U_REGEX_INTERNAL_ERROR.rawValue,
               status.rawValue < U_REGEX_ERROR_LIMIT.rawValue {
                return classifyPatternError(for: pattern)
            }
            return .internalFailure
        }
    }

    private static func namedCaptureNames(in pattern: String) -> [String] {
        let characters = Array(pattern)
        var names: [String] = []
        var isEscaped = false
        var isInCharacterClass = false
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if isEscaped {
                isEscaped = false
                index += 1
                continue
            }

            if character == "\\" {
                isEscaped = true
                index += 1
                continue
            }

            if character == "[" {
                isInCharacterClass = true
                index += 1
                continue
            }

            if character == "]" {
                isInCharacterClass = false
                index += 1
                continue
            }

            if !isInCharacterClass,
               index + 3 < characters.count,
               character == "(",
               characters[index + 1] == "?",
               characters[index + 2] == "<" {
                let firstNameCharacter = characters[index + 3]
                if firstNameCharacter == "=" || firstNameCharacter == "!" {
                    index += 1
                    continue
                }

                var nameCharacters: [Character] = []
                var nameIndex = index + 3
                while nameIndex < characters.count, characters[nameIndex] != ">" {
                    nameCharacters.append(characters[nameIndex])
                    nameIndex += 1
                }

                if nameIndex < characters.count, !nameCharacters.isEmpty {
                    let name = String(nameCharacters)
                    if !names.contains(name) {
                        names.append(name)
                    }
                    index = nameIndex
                    continue
                }
            }

            index += 1
        }

        return names
    }
}
