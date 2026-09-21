@testable import XToolsCore
import Testing

struct TestMarkdownDiffRegexCoverageTests {
    private let labels = JSONDiffValidation.SideLabels(left: "JSON A", right: "JSON B")

    @Test(arguments: [
        "JSON-DIFF-01", "JSON-DIFF-02", "JSON-DIFF-03", "JSON-DIFF-04", "JSON-DIFF-05",
        "JSON-DIFF-06", "JSON-DIFF-07", "JSON-DIFF-08", "JSON-DIFF-09", "JSON-DIFF-10",
        "JSON-DIFF-11", "JSON-DIFF-12", "JSON-DIFF-13", "JSON-DIFF-14"
    ])
    func jsonDiffCase(_ id: String) throws {
        let testCase = try TestMarkdownCaseSupport.testCase(id)

        switch id {
        case "JSON-DIFF-01", "JSON-DIFF-08":
            let rows = try rows(testCase, left: 0, right: 1)
            #expect(rows.isEmpty)
        case "JSON-DIFF-02":
            let rows = try rows(testCase, left: 0, right: 1)
            let text = rowText(rows)
            for fragment in ["Alice Zhang", "false", "pro", "quota", "timezone", "lastLoginAt"] {
                #expect(text.contains(fragment))
            }
        case "JSON-DIFF-03":
            #expect(try rows(testCase, left: 0, right: 1).contains { $0.kind.isDifference })
        case "JSON-DIFF-04":
            let text = rowText(try rows(testCase, left: 0, right: 1))
            #expect(text.contains(#""count": 1"#))
            #expect(text.contains(#""count": "1""#))
            #expect(text.contains(#""empty": null"#))
        case "JSON-DIFF-05":
            let text = rowText(try rows(testCase, left: 0, right: 1))
            #expect(text.contains(#""value": "left""#))
            #expect(text.contains(#""value": "right""#))
            #expect(text.contains(#""id": 3"#))
        case "JSON-DIFF-06":
            let decision = JSONDiffValidation.evaluate(
                left: try block(testCase, 0), right: try block(testCase, 1), labels: labels
            )
            guard case .invalid(let message) = decision else {
                Issue.record("Expected invalid right side")
                return
            }
            #expect(message == "JSON B 格式错误：对象末尾多了逗号")
        case "JSON-DIFF-07":
            let decision = JSONDiffValidation.evaluate(
                left: try block(testCase, 0), right: try block(testCase, 1), labels: labels
            )
            guard case .invalid(let message) = decision else {
                Issue.record("Expected invalid left side")
                return
            }
            #expect(message.contains("JSON A 格式错误"))
            #expect(!message.contains("JSON B 格式错误"))
        case "JSON-DIFF-09":
            let left = try block(testCase, 0)
            let right = try block(testCase, 1)
            #expect(JSONDiffValidation.comparisonWarning(left: left, right: right, labels: labels)?.contains("JSON A") == true)
            #expect(try TestMarkdownCaseSupport.comparableJSONRows(left: left, right: right).contains { $0.kind.isDifference })
        case "JSON-DIFF-10":
            let text = rowText(try rows(testCase, left: 0, right: 1))
            #expect(text.contains(#""status": "failed""#))
            #expect(text.contains(#""id": 6"#))
            #expect(text.contains(#""status": "new""#))
        case "JSON-DIFF-11":
            let left = #"{"items": ["# + (0..<3500).map(String.init).joined(separator: ",") + "]}"
            let right = #"{"items": ["# + (0..<3499).map(String.init).joined(separator: ",") + ",999999]}"
            let decision = JSONStructuralDiff.alignedDiff(left: left, right: right, labels: labels, budget: .standard)
            guard case .comparable(let rows) = decision else {
                Issue.record("Expected sparse large JSON diff to remain comparable")
                return
            }
            #expect(rows.filter { $0.kind.isDifference }.count == 1)
            #expect(JSONStructuralDiff.alignedDiff(left: #"{"a":1}"#, right: #"{"a":2}"#, labels: labels).isComparable)
        case "JSON-DIFF-12":
            #expect(JSONDiffValidation.evaluate(left: "", right: " \n", labels: labels) == .empty)
            #expect(JSONStructuralDiff.alignedDiff(left: "", right: "", labels: labels) == .empty)
        case "JSON-DIFF-13":
            let rightInvalid = try TestMarkdownCaseSupport.testCase("JSON-DIFF-06")
            let leftInvalid = try TestMarkdownCaseSupport.testCase("JSON-DIFF-07")
            if case .invalid(let message) = JSONDiffValidation.evaluate(
                left: try block(rightInvalid, 0), right: try block(rightInvalid, 1), labels: labels
            ) {
                #expect(message.hasPrefix("JSON B 格式错误："))
            } else {
                Issue.record("Expected right-side label")
            }
            if case .invalid(let message) = JSONDiffValidation.evaluate(
                left: try block(leftInvalid, 0), right: try block(leftInvalid, 1), labels: labels
            ) {
                #expect(message.hasPrefix("JSON A 格式错误："))
            } else {
                Issue.record("Expected left-side label")
            }
        case "JSON-DIFF-14":
            let boolRows = try TestMarkdownCaseSupport.comparableJSONRows(
                left: try block(testCase, 0), right: try block(testCase, 1)
            )
            let nullRows = try TestMarkdownCaseSupport.comparableJSONRows(
                left: try block(testCase, 2), right: try block(testCase, 3)
            )
            let emptyRows = try TestMarkdownCaseSupport.comparableJSONRows(
                left: try block(testCase, 4), right: try block(testCase, 5)
            )
            #expect(boolRows.contains { $0.kind.isDifference })
            #expect(nullRows.contains { $0.kind.isDifference })
            #expect(emptyRows.isEmpty)
        default:
            Issue.record("Unhandled case \(id)")
        }
    }

    @Test(arguments: [
        "TEXT-DIFF-01", "TEXT-DIFF-02", "TEXT-DIFF-03", "TEXT-DIFF-04", "TEXT-DIFF-05",
        "TEXT-DIFF-06", "TEXT-DIFF-07", "TEXT-DIFF-08", "TEXT-DIFF-09", "TEXT-DIFF-10",
        "TEXT-DIFF-11", "TEXT-DIFF-12", "TEXT-DIFF-13"
    ])
    func textDiffCase(_ id: String) throws {
        let testCase = try TestMarkdownCaseSupport.testCase(id)

        switch id {
        case "TEXT-DIFF-01":
            #expect(LineDiffer.displayDiff(left: try block(testCase, 0), right: try block(testCase, 1)).allSatisfy { !$0.kind.isDifference })
        case "TEXT-DIFF-02", "TEXT-DIFF-03", "TEXT-DIFF-04":
            #expect(LineDiffer.displayDiff(left: try block(testCase, 0), right: try block(testCase, 1)).contains { $0.kind.isDifference })
        case "TEXT-DIFF-05":
            let rows = LineDiffer.displayDiff(left: try block(testCase, 0), right: try block(testCase, 1))
            #expect(rows.contains { $0.kind == .added && $0.text == "only on right" })
        case "TEXT-DIFF-06":
            let left = try block(testCase, 0)
            let right = (try block(testCase, 1)).replacingOccurrences(of: "\n", with: "\r\n")
            #expect(LineDiffer.displayDiff(left: left, right: right).allSatisfy { !$0.kind.isDifference })
        case "TEXT-DIFF-07":
            let left = (try block(testCase, 0)).replacingOccurrences(of: "␠", with: " ")
            let right = try block(testCase, 1) + "\n"
            let rows = LineDiffer.displayDiff(left: left, right: right)
            #expect(rows.contains { $0.kind.isDifference && $0.text.contains("beta") })
            #expect(rows.contains { $0.kind.isDifference && $0.text.isEmpty })
        case "TEXT-DIFF-08":
            let rows = LineDiffer.alignedDiff(left: try block(testCase, 0), right: try block(testCase, 1))
            #expect(rows.contains { $0.kind.isDifference })
            #expect(rows.flatMap { [$0.left?.text, $0.right?.text].compactMap(\.self) }.contains { $0.contains("👨‍💻") || $0.contains("👩‍💻") })
        case "TEXT-DIFF-09":
            let rows = LineDiffer.alignedDiff(left: try block(testCase, 0), right: try block(testCase, 1))
            #expect(rows.contains { $0.kind.isDifference })
            let source = try TestMarkdownCaseSupport.readSource("Sources/XTools/ToolPages/Workbench/Diff/IndexEditableDiffWorkspace.swift")
            #expect(source.contains("textContainer.lineBreakMode = .byCharWrapping"))
            #expect(source.contains("textView.isHorizontallyResizable = false"))
        case "TEXT-DIFF-10":
            let rows = LineDiffer.alignedDiff(left: try block(testCase, 0), right: try block(testCase, 1))
            #expect(rows.contains { $0.kind.isDifference })
        case "TEXT-DIFF-11":
            let left = (0..<4000).map { "line-\($0)" }.joined(separator: "\n")
            let right = (0..<4000).map { $0 == 3999 ? "line-changed" : "line-\($0)" }.joined(separator: "\n")
            let rows = try LineDiffer.safeAlignedDiff(left: left, right: right)
            #expect(rows.count == 4_000)
            #expect(rows.filter { $0.kind.isDifference }.count == 1)
        case "TEXT-DIFF-13":
            let left = (0..<4000).map { "left-\($0)" }.joined(separator: "\n")
            let right = (0..<4000).map { "right-\($0)" }.joined(separator: "\n")
            let error = #expect(throws: LineDiffError.self) {
                _ = try LineDiffer.safeAlignedDiff(left: left, right: right)
            }
            // 超限提示要说清实际规模与上限，而不是一句不透露任何信息的「过大，无法计算」。
            let message = error?.errorDescription ?? ""
            #expect(message.contains("对比内容过大"), Comment(rawValue: message))
            #expect(message.contains("左侧 4,000 行、右侧 4,000 行"), Comment(rawValue: message))
            #expect(message.contains("12,000,000 个比对单元"), Comment(rawValue: message))
            #expect(try LineDiffer.safeAlignedDiff(left: "a", right: "b").contains { $0.kind.isDifference })
        case "TEXT-DIFF-12":
            #expect(LineDiffer.diff(left: "", right: "") == "")
            #expect(try LineDiffer.safeAlignedDiff(left: "", right: "").isEmpty)
        default:
            Issue.record("Unhandled case \(id)")
        }
    }

    @Test(arguments: [
        "REGEX-01", "REGEX-02", "REGEX-03", "REGEX-04", "REGEX-05", "REGEX-06",
        "REGEX-07", "REGEX-08", "REGEX-09", "REGEX-10", "REGEX-11", "REGEX-12",
        "REGEX-13", "REGEX-14", "REGEX-15", "REGEX-16", "REGEX-17", "REGEX-18",
        "REGEX-19"
    ])
    func regexCase(_ id: String) throws {
        let testCase = try TestMarkdownCaseSupport.testCase(id)

        switch id {
        case "REGEX-01":
            #expect(try report(testCase).matches.map(\.value) == ["alice@example.com", "bob.smith+dev@sub.example.co.uk", "qa@test.io"])
        case "REGEX-02":
            let result = try report(testCase)
            #expect(result.matches.map(\.value) == ["2026-07-07", "2026-12-31"])
            #expect(result.matches.allSatisfy { $0.groups.map(\.name) == ["year", "month", "day"] })
        case "REGEX-03":
            let result = try report(testCase)
            #expect(result.matches.map(\.value) == ["ERROR [worker] job failed", "ERROR [db] connection timeout"])
        case "REGEX-04":
            #expect(try report(testCase).matches.map(\.value) == ["<tag>one</tag>", "<tag>two</tag>", "<tag>three</tag>"])
        case "REGEX-05":
            #expect(try report(testCase).matches.map(\.value) == ["Passw0rd", "ValidPwd2026"])
        case "REGEX-06":
            #expect(try report(testCase).matches.map(\.value) == ["世界", "格式化"])
        case "REGEX-07":
            #expect(throws: RegexMatcher.MatcherError.self) {
                _ = try RegexMatcher.analyze(pattern: try block(testCase, 0), in: try block(testCase, 1), flags: "g")
            }
        case "REGEX-08":
            let error = #expect(throws: RegexMatcher.MatcherError.self) {
                _ = try RegexMatcher.analyze(pattern: try block(testCase, 0), in: try block(testCase, 1), flags: "g")
            }
            #expect(error?.errorDescription?.contains("变长后顾") == true)
        case "REGEX-09":
            #expect(throws: RegexMatcher.MatcherError.unsupportedFlag("u")) {
                _ = try RegexMatcher.analyze(pattern: try block(testCase, 0), in: try block(testCase, 2), flags: try block(testCase, 1))
            }
        case "REGEX-10":
            #expect(try report(testCase).matches.first?.value == "A\nC")
        case "REGEX-11":
            let pattern = try block(testCase, 0)
            let text = try block(testCase, 2)
            #expect(try RegexMatcher.analyze(pattern: pattern, in: text, flags: "").matches.map(\.value) == ["1"])
            #expect(try RegexMatcher.analyze(pattern: pattern, in: text, flags: "g").matches.map(\.value) == ["1", "22", "333"])
        case "REGEX-12":
            let result = try report(testCase)
            #expect(result.matches.map(\.index) == [0, 1, 3, 4])
            #expect(try RegexMatcher.analyze(pattern: "", in: try block(testCase, 2), flags: "g").matches.isEmpty)
        case "REGEX-13":
            #expect(try RegexMatcher.analyze(pattern: "", in: "text", flags: "g").matches.isEmpty)
            #expect(try RegexMatcher.analyze(pattern: #"\d+"#, in: "", flags: "g").matches.isEmpty)
        case "REGEX-14":
            #expect(try RegexMatcher.analyze(pattern: "abc", in: "ABC abc", flags: try block(testCase, 0)).flags == "gi")
            for flag in ["u", "y", "A"] {
                #expect(throws: RegexMatcher.MatcherError.unsupportedFlag(flag)) {
                    _ = try RegexMatcher.analyze(pattern: "abc", in: "abc", flags: flag)
                }
            }
        case "REGEX-15", "REGEX-16", "REGEX-17":
            let error = #expect(throws: RegexMatcher.MatcherError.self) {
                _ = try RegexMatcher.analyze(pattern: try block(testCase, 0), in: try block(testCase, 1), flags: "g")
            }
            let expectedMessage = try block(testCase, 2)
            #expect(error?.errorDescription == expectedMessage)
        case "REGEX-18":
            let result = try report(testCase)
            #expect(result.matches.map(\.value) == ["item-42", "order-100"])
            let summary = RegexMatcher.summaryText(for: result)
            for fragment in ["匹配到 2 处", "捕获 1", "捕获 2", "命名组 word", "范围"] {
                #expect(summary.contains(fragment))
            }
        case "REGEX-19":
            #expect(RegexMatcher.presets.count == 10)
            for preset in RegexMatcher.presets {
                let result = try RegexMatcher.analyze(pattern: preset.pattern, in: preset.exampleText, flags: preset.flags)
                #expect(result.matches.count == preset.examples.filter(\.shouldMatch).count)
            }
            let source = try TestMarkdownCaseSupport.readSource("Sources/XTools/ToolPages/Development/RegexTesterPage.swift")
            #expect(source.contains("ForEach(RegexMatcher.presets)"))
            #expect(source.contains("applyPreset(preset)"))
            #expect(source.contains("text = preset.exampleText"))
            #expect(source.contains("RegexMatcher.summaryText(for: report)"))
        default:
            Issue.record("Unhandled case \(id)")
        }
    }

    private func rows(_ testCase: MarkdownDevelopmentCase, left: Int, right: Int) throws -> [DiffAlignedRow] {
        try TestMarkdownCaseSupport.comparableJSONRows(
            left: try block(testCase, left), right: try block(testCase, right)
        )
    }

    private func rowText(_ rows: [DiffAlignedRow]) -> String {
        rows.flatMap { [$0.left?.text, $0.right?.text].compactMap(\.self) }.joined(separator: "\n")
    }

    private func report(_ testCase: MarkdownDevelopmentCase) throws -> RegexMatcher.Report {
        try RegexMatcher.analyze(
            pattern: try block(testCase, 0),
            in: try block(testCase, 2),
            flags: try block(testCase, 1)
        )
    }

    private func block(_ testCase: MarkdownDevelopmentCase, _ index: Int) throws -> String {
        try TestMarkdownCaseSupport.block(testCase, index)
    }
}

private extension JSONStructuralDiff.Decision {
    var isComparable: Bool {
        if case .comparable = self { return true }
        return false
    }
}
