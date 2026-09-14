import XToolsCore
import Foundation
import Testing

struct RegexMatcherTests {
    @Test func honorsGlobalFlag() throws {
        let firstOnly = try RegexMatcher.analyze(pattern: #"\d+"#, in: "a1b22c333", flags: "")
        #expect(firstOnly.matches.count == 1)
        #expect(firstOnly.matches[0].value == "1")
        #expect(firstOnly.matches[0].index == 1)

        let allMatches = try RegexMatcher.analyze(pattern: #"\d+"#, in: "a1b22c333", flags: "g")
        #expect(allMatches.matches.map(\.value) == ["1", "22", "333"])
        #expect(allMatches.matches.map(\.index) == [1, 3, 6])
        #expect(allMatches.statistics.matchCount == 3)
    }

    @Test func supportsCommonFlags() throws {
        let ignoreCase = try RegexMatcher.analyze(pattern: "abc", in: "ABC abc", flags: "i")
        #expect(ignoreCase.matches.first?.value == "ABC")

        let multiline = try RegexMatcher.analyze(pattern: "^foo", in: "bar\nfoo", flags: "m")
        #expect(multiline.matches.first?.index == 4)

        let dotAll = try RegexMatcher.analyze(pattern: "a.*c", in: "a\nc", flags: "s")
        #expect(dotAll.matches.first?.value == "a\nc")
    }

    @Test func supportsExtendedCommentsFlag() throws {
        let report = try RegexMatcher.analyze(
            pattern: #"""
            a b c # ignore spaces and this comment
            """#,
            in: "abc",
            flags: "x"
        )

        #expect(report.flags == "x")
        #expect(report.matches.first?.value == "abc")
    }

    @Test func ignoresNamedGroupLikeTextInExtendedCommentsAndQuotedLiterals() throws {
        let commented = try RegexMatcher.analyze(
            pattern: "(?<real>abc) # (?<fake>ignored)",
            in: "abc",
            flags: "x"
        )
        #expect(commented.matches.first?.groups.map(\.name) == ["real"])

        let quoted = try RegexMatcher.analyze(
            pattern: #"(?<real>abc)\Q(?<fake>x)\E"#,
            in: "abc(?<fake>x)",
            flags: ""
        )
        #expect(quoted.matches.first?.groups.map(\.name) == ["real"])
    }

    @Test func normalizesDuplicateAndWhitespaceFlags() throws {
        let report = try RegexMatcher.analyze(pattern: "abc", in: "ABC abc", flags: " g i g \n i ")

        #expect(report.flags == "gi")
        #expect(report.matches.map(\.value) == ["ABC", "abc"])
    }

    @Test func reportsCapturesAndNamedGroups() throws {
        let report = try RegexMatcher.analyze(pattern: #"(?<word>\w+)-(\d+)"#, in: "item-42", flags: "")
        let match = try firstMatch(from: report)

        #expect(match.value == "item-42")
        #expect(match.index == 0)
        #expect(match.end == 7)
        #expect(match.captures == [
            RegexMatcher.Capture(name: "1", value: "item", start: 0, end: 4),
            RegexMatcher.Capture(name: "2", value: "42", start: 5, end: 7)
        ])
        #expect(match.groups == [RegexMatcher.Capture(name: "word", value: "item", start: 0, end: 4)])
        #expect(report.statistics.captureCount == 2)
        #expect(report.statistics.namedGroupCount == 1)
    }

    @Test func formatsCopySummaryWithCapturesAndNamedGroups() throws {
        let report = try RegexMatcher.analyze(pattern: #"(?<word>\w+)-(\d+)"#, in: "item-42", flags: "")
        let summary = RegexMatcher.summaryText(for: report)

        #expect(summary.contains("匹配到 1 处"))
        #expect(summary.contains("匹配 #1：范围 [0, 7)；文本 item-42"))
        #expect(summary.contains("捕获 1：范围 [0, 4)；文本 item"))
        #expect(summary.contains("捕获 2：范围 [5, 7)；文本 42"))
        #expect(summary.contains("命名组 word：范围 [0, 4)；文本 item"))
    }

    @Test func reportsCharacterOffsetsForUnicodeText() throws {
        let report = try RegexMatcher.analyze(pattern: #"(?<word>测试)"#, in: "😀测试A", flags: "")
        let match = try firstMatch(from: report)

        #expect(match.value == "测试")
        #expect(match.index == 1)
        #expect(match.end == 3)
        #expect(match.groups == [RegexMatcher.Capture(name: "word", value: "测试", start: 1, end: 3)])
    }

    @Test func matchesEmptyInputWhenPatternAllowsIt() throws {
        let report = try RegexMatcher.analyze(pattern: #"^$"#, in: "", flags: "")
        let match = try firstMatch(from: report)

        #expect(match.value == "")
        #expect(match.index == 0)
        #expect(match.end == 0)
        #expect(report.statistics.matchCount == 1)
    }

    @Test func reportsZeroLengthMatches() throws {
        let report = try RegexMatcher.analyze(pattern: #"(?=\w)"#, in: "ab cd", flags: "g")

        #expect(report.matches.map(\.value) == ["", "", "", ""])
        #expect(report.matches.map(\.index) == [0, 1, 3, 4])
        #expect(report.matches.map(\.end) == [0, 1, 3, 4])
        #expect(report.statistics.matchCount == 4)
        #expect(report.statistics.matchedCharacterCount == 0)
    }

    @Test func validatesPresetExamples() throws {
        let requiredPresetIDs: Set<String> = [
            "mainland-mobile",
            "email",
            "html-tag-content",
            "ipv4",
            "strong-password",
            "date-ymd",
            "duplicate-word",
            "url",
            "uuid",
            "hex-color"
        ]
        let presetIDs = Set(RegexMatcher.presets.map(\.id))
        #expect(presetIDs.isSuperset(of: requiredPresetIDs))

        for preset in RegexMatcher.presets {
            for example in preset.examples {
                let report = try RegexMatcher.analyze(pattern: preset.pattern, in: example.text, flags: preset.flags)
                let didMatch = !report.matches.isEmpty
                #expect(didMatch == example.shouldMatch, "preset \(preset.id) example \(example.text)")
            }
        }
    }

    @Test func validatesPresetExampleTextAsUserInput() throws {
        for preset in RegexMatcher.presets {
            #expect(!preset.examples.isEmpty, "preset \(preset.id)")

            let report = try RegexMatcher.analyze(pattern: preset.pattern, in: preset.exampleText, flags: preset.flags)
            let expectedMatchCount = preset.examples.filter(\.shouldMatch).count
            #expect(report.matches.count == expectedMatchCount, "preset \(preset.id)")
        }
    }

    @Test func hasUniquePresetIDs() throws {
        let presetIDs = RegexMatcher.presets.map(\.id)
        #expect(Set(presetIDs).count == presetIDs.count)
    }

    @Test func rejectsInvalidPatterns() throws {
        let error = #expect(throws: RegexMatcher.MatcherError.self) {
            _ = try RegexMatcher.analyze(pattern: "(", in: "abc", flags: "g")
        }
        guard case .invalidPattern = error else {
            Issue.record("Expected invalidPattern, got \(String(describing: error))")
            return
        }
        #expect(error?.errorDescription == "括号未闭合。")
    }

    @Test func invalidPatternMessagesNameCommonSyntaxProblems() throws {
        let unclosedClass = #expect(throws: RegexMatcher.MatcherError.self) {
            _ = try RegexMatcher.analyze(pattern: "[abc", in: "abc", flags: "g")
        }
        #expect(unclosedClass?.errorDescription == "字符组未闭合。")

        let reversedRange = #expect(throws: RegexMatcher.MatcherError.self) {
            _ = try RegexMatcher.analyze(pattern: "a{2,1}", in: "aaa", flags: "g")
        }
        #expect(reversedRange?.errorDescription == "量词范围无效。")

        let missingLowerBound = #expect(throws: RegexMatcher.MatcherError.self) {
            _ = try RegexMatcher.analyze(pattern: "a{,2}", in: "aa", flags: "g")
        }
        #expect(missingLowerBound?.errorDescription == "量词写法不完整。")

        let invalidClassRange = #expect(throws: RegexMatcher.MatcherError.self) {
            _ = try RegexMatcher.analyze(pattern: "[z-a]", in: "za", flags: "g")
        }
        #expect(invalidClassRange?.errorDescription == "字符组范围顺序无效。")

        let leadingQuantifier = #expect(throws: RegexMatcher.MatcherError.self) {
            _ = try RegexMatcher.analyze(pattern: "*abc", in: "abc", flags: "g")
        }
        #expect(leadingQuantifier?.errorDescription == "量词前缺少表达式。")
    }

    @Test func reportsEngineCompatibilityBoundaryForVariableLengthLookbehind() throws {
        let error = #expect(throws: RegexMatcher.MatcherError.self) {
            _ = try RegexMatcher.analyze(pattern: #"(?<=\d{2,})abc"#, in: "12abc 123abc", flags: "g")
        }

        #expect(error?.errorDescription?.contains("变长后顾") == true)
        #expect(error?.errorDescription?.contains("当前正则引擎不支持") == true)
        #expect(error?.errorDescription?.contains("正则语法错误，请检查括号、字符组、量词和转义写法") != true)
    }

    @Test func rejectsUnsupportedFlags() throws {
        #expect(throws: RegexMatcher.MatcherError.unsupportedFlag("z")) {
            _ = try RegexMatcher.analyze(pattern: "abc", in: "abc", flags: "z")
        }
        let error = #expect(throws: RegexMatcher.MatcherError.self) {
            _ = try RegexMatcher.analyze(pattern: "abc", in: "abc", flags: "z")
        }
        #expect(error?.errorDescription?.contains("当前支持 g、i、m、s、x") == true)
    }

    @Test func normalizeFlagsForUIOrdersKnownFlagsAndKeepsUnknowns() {
        #expect(RegexMatcher.normalizeFlagsForUI("xmig") == "gimx")
        #expect(RegexMatcher.normalizeFlagsForUI("  g  i  ") == "gi")
        #expect(RegexMatcher.normalizeFlagsForUI("zgiz") == "giz")
        #expect(RegexMatcher.normalizeFlagsForUI("") == "")
    }

    @Test func prioritizesUnsupportedFlagErrorsBeforePatternCompilation() throws {
        // Unsupported flag "z" must surface before the invalid pattern "(" is compiled.
        #expect(throws: RegexMatcher.MatcherError.unsupportedFlag("z")) {
            _ = try RegexMatcher.analyze(pattern: "(", in: "abc", flags: "z")
        }
    }

    @Test func rejectsPatternAndTextBeyondBudgetWithoutEchoingInput() throws {
        let patternSecret = "private-pattern-secret"
        let patternError = #expect(throws: RegexMatcher.MatcherError.patternTooLong) {
            _ = try RegexMatcher.analyze(
                pattern: patternSecret,
                in: "text",
                budget: budget(maxPatternUTF16Length: 4)
            )
        }
        ToolDiagnosticContract.expectFactual(
            patternError?.errorDescription ?? "",
            sensitiveInputs: [patternSecret]
        )

        let textSecret = "private-text-secret"
        let textError = #expect(throws: RegexMatcher.MatcherError.textTooLong) {
            _ = try RegexMatcher.analyze(
                pattern: ".",
                in: textSecret,
                budget: budget(maxTextUTF16Length: 4)
            )
        }
        ToolDiagnosticContract.expectFactual(
            textError?.errorDescription ?? "",
            sensitiveInputs: [textSecret]
        )
    }

    @Test func emptyPatternStaysQuietEvenWhenTextExceedsBudget() throws {
        let report = try RegexMatcher.analyze(
            pattern: "",
            in: String(repeating: "A", count: 100),
            budget: budget(maxTextUTF16Length: 1)
        )

        #expect(report.matches.isEmpty)
    }

    @Test func rejectsExcessiveMatchCountWithoutReturningPartialReport() throws {
        let error = #expect(throws: RegexMatcher.MatcherError.matchCountLimitExceeded) {
            _ = try RegexMatcher.analyze(
                pattern: ".",
                in: "abc",
                flags: "g",
                budget: budget(maxMatchCount: 2)
            )
        }

        #expect(error?.errorDescription == "匹配结果过多。")
    }

    @Test func rejectsExcessiveCaptureCountAndResultContent() throws {
        let captureError = #expect(throws: RegexMatcher.MatcherError.captureCountLimitExceeded) {
            _ = try RegexMatcher.analyze(
                pattern: "(A)(B)",
                in: "AB",
                budget: budget(maxCaptureCount: 1)
            )
        }
        #expect(captureError?.errorDescription == "捕获结果过多。")

        let contentError = #expect(throws: RegexMatcher.MatcherError.resultSizeLimitExceeded) {
            _ = try RegexMatcher.analyze(
                pattern: "(A+)",
                in: "AAAA",
                budget: budget(maxResultUTF16Length: 7)
            )
        }
        #expect(contentError?.errorDescription == "匹配结果内容过多。")
    }

    @Test func catastrophicBacktrackingStopsAtTimeLimit() throws {
        let text = String(repeating: "A", count: 50_000) + "C"
        let clock = ContinuousClock()
        let start = clock.now
        let error = #expect(throws: RegexMatcher.MatcherError.timeLimitExceeded) {
            _ = try RegexMatcher.analyze(
                pattern: "(A+)+B",
                in: text,
                budget: budget(matchTimeLimit: 1)
            )
        }

        #expect(clock.now - start < .seconds(2))
        #expect(error?.errorDescription == "正则表达式计算量过大。")
        ToolDiagnosticContract.expectFactual(
            error?.errorDescription ?? "",
            sensitiveInputs: ["(A+)+B", String(text.prefix(256))]
        )
    }

    @Test func defaultBudgetAllowsMaximumLengthLinearScan() throws {
        let text = String(repeating: "A", count: RegexMatcher.Budget.standard.maxTextUTF16Length)
        let report = try RegexMatcher.analyze(pattern: "Z", in: text, flags: "g")

        #expect(report.matches.isEmpty)
    }

    @Test func excessiveBacktrackingStopsAtStackLimit() throws {
        let error = #expect(throws: RegexMatcher.MatcherError.stackLimitExceeded) {
            _ = try RegexMatcher.analyze(
                pattern: "(A|AA)+B",
                in: String(repeating: "A", count: 4_000) + "C",
                budget: budget(matchTimeLimit: 1_000_000, backtrackStackLimitBytes: 1_024)
            )
        }

        #expect(error?.errorDescription == "正则表达式计算量过大。")
    }

    @Test func resourceDiagnosticsAreStableAndFactual() {
        let sensitiveInput = "TOKEN=private-secret /tmp/private/file"
        let errors: [RegexMatcher.MatcherError] = [
            .patternTooLong,
            .textTooLong,
            .timeLimitExceeded,
            .stackLimitExceeded,
            .resourceLimitExceeded,
            .matchCountLimitExceeded,
            .captureCountLimitExceeded,
            .resultSizeLimitExceeded,
            .internalFailure
        ]

        for error in errors {
            ToolDiagnosticContract.expectFactual(
                error.errorDescription ?? "",
                sensitiveInputs: [sensitiveInput]
            )
        }
    }

    private func budget(
        maxPatternUTF16Length: Int = RegexMatcher.Budget.standard.maxPatternUTF16Length,
        maxTextUTF16Length: Int = RegexMatcher.Budget.standard.maxTextUTF16Length,
        matchTimeLimit: Int32 = RegexMatcher.Budget.standard.matchTimeLimit,
        backtrackStackLimitBytes: Int32 = RegexMatcher.Budget.standard.backtrackStackLimitBytes,
        maxMatchCount: Int = RegexMatcher.Budget.standard.maxMatchCount,
        maxCaptureCount: Int = RegexMatcher.Budget.standard.maxCaptureCount,
        maxResultUTF16Length: Int = RegexMatcher.Budget.standard.maxResultUTF16Length
    ) -> RegexMatcher.Budget {
        RegexMatcher.Budget(
            maxPatternUTF16Length: maxPatternUTF16Length,
            maxTextUTF16Length: maxTextUTF16Length,
            matchTimeLimit: matchTimeLimit,
            backtrackStackLimitBytes: backtrackStackLimitBytes,
            maxMatchCount: maxMatchCount,
            maxCaptureCount: maxCaptureCount,
            maxResultUTF16Length: maxResultUTF16Length
        )
    }

    private func firstMatch(from report: RegexMatcher.Report) throws -> RegexMatcher.Match {
        try #require(report.matches.first)
    }
}
