import XToolsCore
import Testing

struct JSONFormattingTests {
    // MARK: - test.md JSON samples

    @Test func testMarkdownShortJSONSampleFormatsAndPreservesTypes() throws {
        let result = try JSONFormatting.formatResult(#"{"id":1,"name":"Alice","active":true,"tags":["dev","ops"],"meta":null}"#, sortKeys: false, indentWidth: 2)

        #expect(result.warning == nil)
        #expect(result.text ==
            """
            {
              "id": 1,
              "name": "Alice",
              "active": true,
              "tags": [
                "dev",
                "ops"
              ],
              "meta": null
            }
            """
        )
    }

    @Test func testMarkdownLongJSONSampleFormatsUnicodeEscapesAndEmptyContainers() throws {
        let input = #"{"project":{"id":"toolkit-001","name":"开发者工具箱","version":"2.4.0","createdAt":"2026-07-07T09:30:45+08:00","enabled":true,"limits":{"maxItems":5000,"timeoutMs":120000,"ratio":0.875},"owners":[{"id":101,"name":"Rena","roles":["admin","developer"],"contact":{"email":"rena@example.com","phone":"+86-10-8888-6666"}},{"id":102,"name":"QA 用户","roles":["tester"],"contact":{"email":"qa@example.com","phone":null}}],"features":{"jsonFormatter":{"enabled":true,"options":{"indent":2,"sortKeys":false}},"sqlFormatter":{"enabled":true,"dialects":["postgresql","mysql","sqlite"]},"htmlToMarkdown":{"enabled":true,"preserveTables":true}},"samples":[{"type":"string","value":"包含中文、emoji 🙂、换行\\n、制表符\\t、引号\\\"、反斜杠\\\\"},{"type":"number","value":1234567890.12345},{"type":"emptyObject","value":{}},{"type":"emptyArray","value":[]}]},"audit":{"updatedBy":"system","history":[{"at":"2026-07-01T00:00:00Z","action":"created"},{"at":"2026-07-06T18:22:11Z","action":"updated"}]}}"#

        let output = try JSONFormatting.format(input, sortKeys: false, indentWidth: 2)

        #expect(output.contains(#""name": "开发者工具箱""#))
        #expect(output.contains(#""name": "QA 用户""#))
        #expect(output.contains(#""value": "包含中文、emoji 🙂、换行\\n、制表符\\t、引号\\\"、反斜杠\\\\""#))
        #expect(output.contains(#""value": {}"#))
        #expect(output.contains(#""value": []"#))
        #expect(output.contains(#""phone": null"#))
        #expect(output.contains(#""enabled": true"#))
        #expect(output.contains(#""ratio": 0.875"#))
    }

    @Test func testMarkdownTopLevelArraySampleFormats() throws {
        let output = try JSONFormatting.format(#"[{"id":1,"score":99.5},{"id":2,"score":0},{"id":3,"score":-42}]"#, sortKeys: false, indentWidth: 2)

        #expect(output ==
            """
            [
              {
                "id": 1,
                "score": 99.5
              },
              {
                "id": 2,
                "score": 0
              },
              {
                "id": 3,
                "score": -42
              }
            ]
            """
        )
    }

    @Test func testMarkdownInvalidJSONSamplesThrowFormattingErrors() throws {
        let invalidSamples = [
            #"{"id":1,"name":"Alice",}"#,
            #"{id: 1, 'name': 'Alice'}"#,
            """
            {
              // JSON 标准不允许注释
              "value": NaN
            }
            """,
            #"{"user":{"id":1,"name":"missing end"}"#
        ]

        for sample in invalidSamples {
            #expect(throws: JSONFormatting.FormattingError.self) {
                _ = try JSONFormatting.format(sample, sortKeys: false, indentWidth: 2)
            }
        }
    }

    @Test func testMarkdownDuplicateKeySamplePreservesAllMembers() throws {
        let result = try JSONFormatting.formatResult(#"{"id":1,"name":"first","name":"second"}"#, sortKeys: false, indentWidth: 2)

        #expect(result.text ==
            """
            {
              "id": 1,
              "name": "first",
              "name": "second"
            }
            """
        )
        #expect(result.warning == "JSON 含重复 key。")
        #expect(result.duplicateKeys == ["name"])
    }

    @Test func adjustIndentationKeepsTwoSpacePrettyPrintedJSONAtTwoSpaces() {
        let json = """
        {
          "a" : {
            "b" : 1
          }
        }
        """

        let adjusted = JSONFormatting.adjustIndentation(json, to: 2)

        #expect(adjusted.contains("\n  \"a\""))
        #expect(adjusted.contains("\n    \"b\""))
    }

    @Test func adjustIndentationExpandsTwoSpacePrettyPrintedJSONToFourSpaces() {
        let json = """
        {
          "a" : {
            "b" : 1
          }
        }
        """

        let adjusted = JSONFormatting.adjustIndentation(json, to: 4)

        #expect(adjusted.contains("\n    \"a\""))
        #expect(adjusted.contains("\n        \"b\""))
    }

    @Test func formatPreservesInputKeyOrderByDefault() throws {
        let output = try JSONFormatting.format(#"{"b":2,"a":1,"c":3}"#, sortKeys: false, indentWidth: 2)

        #expect(
            output ==
            """
            {
              "b": 2,
              "a": 1,
              "c": 3
            }
            """
        )
    }

    @Test func formatSortsKeysOnlyWhenRequested() throws {
        let output = try JSONFormatting.format(#"{"b":2,"a":1,"c":3}"#, sortKeys: true, indentWidth: 2)

        #expect(
            output ==
            """
            {
              "a": 1,
              "b": 2,
              "c": 3
            }
            """
        )
    }

    @Test func formatPreservesNestedInputKeyOrderByDefault() throws {
        let output = try JSONFormatting.format(#"{"outer":{"z":0,"a":1},"root":true}"#, sortKeys: false, indentWidth: 2)

        #expect(
            output.contains("""
              "outer": {
                "z": 0,
                "a": 1
              },
            """)
        )
    }

    @Test func formatDoesNotEscapeForwardSlashes() throws {
        let output = try JSONFormatting.format(#"{"url":"https://example.com/a/b"}"#, sortKeys: false, indentWidth: 2)

        #expect(output.contains(#""url": "https://example.com/a/b""#))
        #expect(!output.contains(#"\/"#))
    }

    @Test func formatUsesStandardColonSpacing() throws {
        let output = try JSONFormatting.format(#"{"key":"value"}"#, sortKeys: false, indentWidth: 2)

        #expect(output.contains(#""key": "value""#))
        #expect(!output.contains(#""key" : "value""#))
    }

    @Test func formatUsesTwoSpaceIndentation() throws {
        let output = try JSONFormatting.format(#"{"a":{"b":1}}"#, sortKeys: false, indentWidth: 2)

        #expect(output.contains("\n  \"a\": {"))
        #expect(output.contains("\n    \"b\": 1"))
    }

    @Test func formatUsesFourSpaceIndentation() throws {
        let output = try JSONFormatting.format(#"{"a":{"b":1}}"#, sortKeys: false, indentWidth: 4)

        #expect(output.contains("\n    \"a\": {"))
        #expect(output.contains("\n        \"b\": 1"))
    }

    @Test func minifyRemovesInsignificantWhitespace() throws {
        let output = try JSONFormatting.minify(
            """
            {
              "b": 2,
              "a": [1, 2]
            }
            """
        )

        #expect(output == #"{"b":2,"a":[1,2]}"#)
    }

    @Test func minifyDoesNotEscapeForwardSlashes() throws {
        let output = try JSONFormatting.minify(#"{"url":"https://example.com/a/b"}"#)

        #expect(output == #"{"url":"https://example.com/a/b"}"#)
    }

    @Test func invalidJSONThrowsFormattingError() throws {
        #expect {
            _ = try JSONFormatting.format(#"{"a":"#, sortKeys: false, indentWidth: 2)
        } throws: { error in
            guard case JSONFormatting.FormattingError.invalidJSON = error else { return false }
            return true
        }
    }

    @Test func invalidJSONReportsLineColumnSnippetAndFactualMessage() throws {
        let error = #expect(throws: (any Error).self) {
            _ = try JSONFormatting.format(#"{"json": "test", "a": b }"#, sortKeys: false, indentWidth: 2)
        }

        guard let error,
              case JSONFormatting.FormattingError.invalidJSON(let diagnostic) = error else {
            Issue.record("Expected JSON formatting diagnostic")
            return
        }

        #expect(diagnostic.line == 1)
        #expect(diagnostic.column == 23)
        #expect(diagnostic.message.contains("未加引号"))
        #expect(diagnostic.excerpt == #"{"json": "test", "a": b }"#)
        #expect(diagnostic.suggestion == nil)
        #expect(diagnostic.localizedDescription == diagnostic.message)
        #expect(diagnostic.displayMessage == "值不能是未加引号的标识符 b")
        #expect(diagnostic.formatName == "JSON")
        #expect(diagnostic.line == 1)
        #expect(diagnostic.column == 23)
        #expect(!diagnostic.localizedDescription.contains("附近："))
        #expect(!diagnostic.localizedDescription.contains("建议："))
        #expect(!diagnostic.workspaceMessage.contains("处理方式："))
    }

    @Test func invalidJSONDiagnosticsDescribeSpecificSyntaxProblems() throws {
        let samples: [(input: String, expected: String)] = [
            (#"{"id":1,"name":"Alice",}"#, "对象末尾多了逗号"),
            (#"{"a":1,, "b":2}"#, "对象成员之间多了逗号"),
            (#"{id: 1}"#, "对象键必须使用双引号"),
            (#"{'name': 'Alice'}"#, "双引号"),
            ("{\n  // comment\n  \"value\": 1\n}", "JSON 不支持注释"),
            (#"{"value": 1 // comment}"#, "JSON 不支持注释"),
            (#"{"value": NaN}"#, "JSON 不支持 NaN"),
            (#"{"user":{"id":1}"#, "对象没有完整闭合"),
            (#"[1,2,]"#, "数组末尾多了逗号"),
            (#"[1,,2]"#, "数组元素之间多了逗号"),
            (#"{"n": 01}"#, "数字不能有前导零"),
            (#"{"n": -}"#, "负号后缺少数字"),
            (#"{"n": +1}"#, "JSON 数字前不能写加号"),
            (#"{"n": 0x10}"#, "JSON 不支持十六进制数字"),
            (#"{"n":１２}"#, "JSON 数字只能使用半角"),
            (#"{"n":1.٢}"#, "JSON 小数部分只能使用半角"),
            (#"{"n": 1.}"#, "小数点后缺少数字"),
            (#"{"n": 1e}"#, "指数部分缺少数字"),
            (#"{"bad":"\uZZZZ"}"#, "Unicode 转义"),
            (#"{"loneLowSurrogate":"\uDE00"}"#, "低位代理项不能单独出现"),
            (#"{"a":}"#, "对象键后缺少值"),
            ("{\"bad\":\"line\nbreak\"}", "未转义的控制字符"),
            (#"{"a":1} {"b":2}"#, "根值后还有额外内容")
        ]

        var messages: [String] = []
        for sample in samples {
            let diagnostic = try invalidJSONDiagnostic(for: sample.input)
            messages.append(diagnostic.message)
            #expect(
                diagnostic.message.contains(sample.expected),
                "Expected diagnostic '\(diagnostic.message)' to contain '\(sample.expected)'"
            )
        }

        #expect(Set(messages).count >= 10)
    }

    // MARK: - Empty containers

    @Test func formatEmptyObjectAndArrayStayCompact() throws {
        #expect(try JSONFormatting.format("{}", sortKeys: false, indentWidth: 2) == "{}")
        #expect(try JSONFormatting.format("[]", sortKeys: false, indentWidth: 2) == "[]")
        #expect(try JSONFormatting.format(#"{"a":{},"b":[]}"#, sortKeys: false, indentWidth: 2) ==
            """
            {
              "a": {},
              "b": []
            }
            """
        )
    }

    // MARK: - Indentation width edge cases

    @Test func formatWithZeroIndentStillBreaksLines() throws {
        let output = try JSONFormatting.format(#"{"a":1}"#, sortKeys: false, indentWidth: 0)

        #expect(output ==
            """
            {
            "a": 1
            }
            """
        )
    }

    @Test func formatClampsNegativeIndentToZero() throws {
        // A negative width must not crash or produce negative-length padding.
        let output = try JSONFormatting.format(#"{"a":1}"#, sortKeys: false, indentWidth: -4)

        #expect(output ==
            """
            {
            "a": 1
            }
            """
        )
    }

    // MARK: - String escaping (silent-corruption risk)

    @Test func formatEscapesQuotesAndBackslashes() throws {
        let output = try JSONFormatting.format(#"{"path":"C:\\a\"b"}"#, sortKeys: false, indentWidth: 2)

        #expect(output.contains(#""path": "C:\\a\"b""#))
    }

    @Test func formatEscapesControlCharactersAsShortSequences() throws {
        // Tab and newline inside a string value must be re-emitted as \t / \n.
        let output = try JSONFormatting.format("{\"s\":\"a\\tb\\nc\"}", sortKeys: false, indentWidth: 2)

        #expect(output.contains(#""s": "a\tb\nc""#))
    }

    @Test func formatEscapesLowControlCharactersAsUnicode() throws {
        // U+0001 has no short escape, so escapeString emits it as \u%04X (uppercase hex).
        let output = try JSONFormatting.format("{\"s\":\"\\u0001\"}", sortKeys: false, indentWidth: 2)

        #expect(output.contains(#"\u0001"#))
    }

    @Test func formatDecodesUnicodeEscapeThenReEmitsLiteral() throws {
        // 中 decodes to 中; a BMP character round-trips as its literal form.
        let output = try JSONFormatting.format("{\"s\":\"\\u4e2d\"}", sortKeys: false, indentWidth: 2)

        #expect(output.contains(#""s": "中""#))
    }

    @Test func formatDecodesSurrogatePairEmoji() throws {
        // 😀 is a surrogate pair for 😀 and must decode to one scalar.
        let output = try JSONFormatting.format("{\"s\":\"\\ud83d\\ude00\"}", sortKeys: false, indentWidth: 2)

        #expect(output.contains("😀"))
    }

    // MARK: - Number and literal fidelity

    @Test func formatPreservesNumberAndBooleanAndNullLiterals() throws {
        let output = try JSONFormatting.minify(#"{"i":42,"f":3.14,"e":1e3,"t":true,"f2":false,"n":null}"#)

        #expect(output == #"{"i":42,"f":3.14,"e":1e3,"t":true,"f2":false,"n":null}"#)
    }

    @Test func rejectsNonASCIIDigitsInNumbers() throws {
        #expect(throws: JSONFormatting.FormattingError.self) {
            _ = try JSONFormatting.minify(#"{"n":１２}"#)
        }

        #expect(throws: JSONFormatting.FormattingError.self) {
            _ = try JSONFormatting.minify(#"{"n":1.٢}"#)
        }
    }

    @Test func minifySortKeysIsDisabledSoOrderIsPreserved() throws {
        // minify never sorts; input order must survive.
        let output = try JSONFormatting.minify(#"{"b":1,"a":2}"#)

        #expect(output == #"{"b":1,"a":2}"#)
    }

    @Test func formatSortsNestedObjectKeysWhenRequested() throws {
        let output = try JSONFormatting.format(#"{"outer":{"z":1,"a":2}}"#, sortKeys: true, indentWidth: 2)

        #expect(output ==
            """
            {
              "outer": {
                "a": 2,
                "z": 1
              }
            }
            """
        )
    }

    @Test func formatPreservesDuplicateObjectMembersInsteadOfLastWins() throws {
        let output = try JSONFormatting.format(#"{"a":1,"a":2,"b":3}"#, sortKeys: false, indentWidth: 2)

        #expect(output ==
            """
            {
              "a": 1,
              "a": 2,
              "b": 3
            }
            """
        )
    }

    @Test func formatSortKeysKeepsDuplicateMemberRelativeOrder() throws {
        let output = try JSONFormatting.format(#"{"b":0,"a":1,"a":2,"c":3}"#, sortKeys: true, indentWidth: 2)

        #expect(output ==
            """
            {
              "a": 1,
              "a": 2,
              "b": 0,
              "c": 3
            }
            """
        )
    }

    @Test func canonicalEquivalentButScalarDistinctKeysAreNotDuplicates() throws {
        let input = #"{"é":1,"e\u0301":2}"#

        let formatted = try JSONFormatting.formatResult(input, sortKeys: false, indentWidth: 2)
        let minified = try JSONFormatting.minifyResult(input)

        #expect(formatted.warning == nil)
        #expect(formatted.duplicateKeys.isEmpty)
        #expect(Array(formatted.text.utf8) == Array(
            """
            {
              "é": 1,
              "é": 2
            }
            """.utf8
        ))
        #expect(minified.warning == nil)
        #expect(minified.duplicateKeys.isEmpty)
        #expect(Array(minified.text.utf8) == Array(#"{"é":1,"é":2}"#.utf8))
    }

    @Test func decodedEquivalentEscapesRemainDuplicateKeys() throws {
        let ascii = try JSONFormatting.formatResult(#"{"a":1,"\u0061":2}"#, sortKeys: false, indentWidth: 2)
        let emoji = try JSONFormatting.minifyResult(#"{"😀":1,"\ud83d\ude00":2}"#)

        #expect(ascii.warning == "JSON 含重复 key。")
        #expect(ascii.duplicateKeys == ["a"])
        #expect(ascii.text.contains(#""a": 1"#))
        #expect(ascii.text.contains(#""a": 2"#))
        #expect(emoji.warning == "JSON 含重复 key。")
        #expect(emoji.duplicateKeys == ["😀"])
        #expect(emoji.text == #"{"😀":1,"😀":2}"#)
    }

    @Test func duplicateKeyResultsKeepCanonicallyEquivalentIdentitiesSeparate() throws {
        let result = try JSONFormatting.minifyResult(#"{"é":0,"\u00e9":1,"e\u0301":0,"e\u0301":1}"#)

        #expect(result.warning == "JSON 含重复 key。")
        #expect(result.duplicateKeys.count == 2)
        #expect(Array(result.duplicateKeys[0].utf8) == [0xC3, 0xA9])
        #expect(Array(result.duplicateKeys[1].utf8) == [0x65, 0xCC, 0x81])
    }

    @Test func exactIdentitySortingIsDeterministicAndStable() throws {
        let input = #"{"é":1,"e\u0301":2,"\u0061":3,"a":4,"n":9007199254740993,"f":1.2300,"x":1e999}"#

        let first = try JSONFormatting.minifyResult(input, sortKeys: true)
        let second = try JSONFormatting.minifyResult(input, sortKeys: true)

        #expect(Array(first.text.utf8) == Array(second.text.utf8))
        #expect(Array(first.text.utf8) == Array(#"{"a":3,"a":4,"é":2,"f":1.2300,"n":9007199254740993,"x":1e999,"é":1}"#.utf8))
        #expect(first.duplicateKeys == ["a"])
    }

    @Test func arraySortingUsesExactIdentityInPrettyAndCompactRenderers() throws {
        let input = #"["é","e\u0301"]"#
        let reversed = #"["e\u0301","é"]"#

        let prettyInput = try JSONFormatting.formatResult(
            input,
            sortKeys: true,
            sortArrays: true,
            indentWidth: 2
        )
        let prettyReversed = try JSONFormatting.formatResult(
            reversed,
            sortKeys: true,
            sortArrays: true,
            indentWidth: 2
        )
        let compactInput = try JSONFormatting.minifyResult(
            input,
            sortKeys: true,
            sortArrays: true
        )
        let compactReversed = try JSONFormatting.minifyResult(
            reversed,
            sortKeys: true,
            sortArrays: true
        )

        #expect(prettyInput.exactTextIdentity == prettyReversed.exactTextIdentity)
        #expect(compactInput.exactTextIdentity == compactReversed.exactTextIdentity)
        #expect(Array(compactInput.text.utf8) == Array(#"["é","é"]"#.utf8))
    }

    @Test func manyDistinctDuplicateKeysPreserveFirstDuplicateOrder() throws {
        let count = 3_000
        let members = (0..<count).flatMap { index in
            [#""k\#(index)":0"#, #""k\#(index)":1"#]
        }
        let result = try JSONFormatting.minifyResult("{" + members.joined(separator: ",") + "}")

        #expect(result.duplicateKeys.count == count)
        #expect(result.duplicateKeys.first == "k0")
        #expect(result.duplicateKeys.last == "k2999")
        #expect(result.text.hasPrefix(#"{"k0":0,"k0":1,"k1":0,"k1":1"#))
    }

    @Test func minifyPreservesDuplicateObjectMembersInsteadOfLastWins() throws {
        let result = try JSONFormatting.minifyResult(#"{"a":1,"a":2,"b":3}"#)

        #expect(result.text == #"{"a":1,"a":2,"b":3}"#)
        #expect(result.warning == "JSON 含重复 key。")
        #expect(result.duplicateKeys == ["a"])
    }

    @Test func formatPreservesNumberLiteralsWithoutRoundingOrNormalization() throws {
        let output = try JSONFormatting.format(#"{"safe":42,"unsafe":9007199254740993,"fraction":1.2300,"exp":1e999}"#, sortKeys: false, indentWidth: 2)

        #expect(output ==
            """
            {
              "safe": 42,
              "unsafe": 9007199254740993,
              "fraction": 1.2300,
              "exp": 1e999
            }
            """
        )
    }

    @Test func minifyReversesFormatWithoutDataLoss() throws {
        let original = #"{"b":2,"a":[1,{"nested":true}],"s":"x/y"}"#
        let formatted = try JSONFormatting.format(original, sortKeys: false, indentWidth: 4)
        let reminified = try JSONFormatting.minify(formatted)

        #expect(reminified == original)
    }

    // MARK: - Depth, container tracing & minify sort keys

    @Test func maxNestingDepthSafelyRejectsDeepNesting() throws {
        let deepJSON = String(repeating: "[", count: 40) + String(repeating: "]", count: 40)
        let diagnostic = try invalidJSONDiagnostic(for: deepJSON)
        #expect(diagnostic.message.contains("超过最大安全深度"))
    }

    @Test func unclosedNestedObjectReportsContainerKey() throws {
        let sample = #"{"matrix": {"level_1": {"target": 1"#
        let diagnostic = try invalidJSONDiagnostic(for: sample)
        #expect(diagnostic.message.contains("对象没有完整闭合"))
        #expect(diagnostic.message.contains("level_1") || diagnostic.message.contains("matrix"))
    }

    @Test func minifySupportsKeySorting() throws {
        let input = #"{"z":1,"a":2,"m":3}"#
        let result = try JSONFormatting.minifyResult(input, sortKeys: true)
        #expect(result.text == #"{"a":2,"m":3,"z":1}"#)
    }

    @Test func escapesJSONStringProperly() throws {
        let minified = #"{"name":"XTools","tags":["a","b"]}"#
        let escaped = JSONFormatting.escapeJSON(minified)
        #expect(escaped == #""{\"name\":\"XTools\",\"tags\":[\"a\",\"b\"]\}""# || escaped.contains(#"\"name\""#))
        #expect(escaped.hasPrefix("\"") && escaped.hasSuffix("\""))

        let unescaped = JSONFormatting.unescapeJSON(escaped)
        #expect(unescaped == minified)
    }

    @Test func unescapesManualEscapedStringWithoutQuotes() throws {
        let rawEscaped = #"{\"name\":\"XTools\"}"#
        let unescaped = JSONFormatting.unescapeJSON(rawEscaped)
        #expect(unescaped == #"{"name":"XTools"}"#)
    }

    @Test func unescapesUnicodeEscapedCharacters() throws {
        let rawEscaped = #"{\"title\":\"\u4e2d\u6587\",\"symbol\":\"\u2705\"}"#
        let unescaped = JSONFormatting.unescapeJSON(rawEscaped)
        #expect(unescaped == #"{"title":"中文","symbol":"✅"}"#)
    }

    private func invalidJSONDiagnostic(for input: String) throws -> FormatDiagnostic {
        let error = #expect(throws: (any Error).self) {
            _ = try JSONFormatting.format(input, sortKeys: false, indentWidth: 2)
        }

        guard let error,
              case JSONFormatting.FormattingError.invalidJSON(let diagnostic) = error else {
            Issue.record("Expected JSON formatting diagnostic")
            throw JSONDiagnosticTestFailure.missingDiagnostic
        }

        return diagnostic
    }

    private enum JSONDiagnosticTestFailure: Error {
        case missingDiagnostic
    }
}
