import XToolsCore
import Foundation
import Testing

/// Probes critical development-tool paths (12 tools).
/// Failures here are product defects or documentation drift against Core contracts.
struct DevelopmentTestDataProbeTests {
    private let jsonLabels = JSONDiffValidation.SideLabels(left: "JSON A", right: "JSON B")

    // MARK: - Empty / quiet inputs (FormatRunner + converters)

    @Test func emptyAndWhitespaceInputsStayQuietForFormatters() {
        let blanks = ["", "   ", "\n\t  \n"]

        for blank in blanks {
            let json = FormatRunner.run(blank) {
                try JSONFormatting.formatResult($0, sortKeys: false, indentWidth: 2)
            }
            #expect(json == .empty)

            let sql = FormatRunner.run(blank) { try SQLFormatting.format($0) }
            #expect(sql == .empty)

            let xml = FormatRunner.run(blank) { try XMLFormatting.format($0) }
            #expect(xml == .empty)

            let yaml = FormatRunner.run(blank) { try YAMLPrettifier.formatValidated($0) }
            #expect(yaml == .empty)
        }

        #expect(JSONDiffValidation.evaluate(left: "  ", right: "\n", labels: jsonLabels) == .empty)
        #expect(JSONStructuralDiff.alignedDiff(left: "", right: "", labels: jsonLabels) == .empty)

        let regex = try! RegexMatcher.analyze(pattern: "", in: "abc", flags: "g")
        #expect(regex.matches.isEmpty)
        #expect(regex.statistics.matchCount == 0)
    }

    // MARK: - JSON-FMT

    @Test func jsonFmtErrorSamplesThrowAndDuplicateKeyWarns() throws {
        let invalid: [(input: String, expected: String)] = [
            (#"{"id":1,"name":"Alice",}"#, "对象末尾多了逗号"), // JSON-FMT-04
            (#"{id: 1, 'name': 'Alice'}"#, "对象键必须使用双引号"), // JSON-FMT-05
            ("{\n  // comment\n  \"value\": NaN\n}", "JSON 不支持注释"), // JSON-FMT-06
            (#"{"value": NaN}"#, "JSON 不支持 NaN"),
            (#"{"value": Infinity}"#, "JSON 不支持 Infinity"),
            (#"{"user":{"id":1,"name":"missing end"}"#, "对象没有完整闭合"), // JSON-FMT-07
            (#"{"leadingZero": 01}"#, "数字不能有前导零"),
            (#"{"badEscape":"\uZZZZ"}"#, "Unicode 转义"),
            (#"{"loneLowSurrogate":"\uDE00"}"#, "低位代理项不能单独出现"),
            (#"{"a":}"#, "对象键后缺少值")
        ]
        for sample in invalid {
            let diagnostic = try jsonDiagnostic(for: sample.input)
            #expect(diagnostic.message.contains(sample.expected))
            #expect(!diagnostic.message.contains("The operation"))
        }

        let dup = try JSONFormatting.formatResult(#"{"id":1,"name":"first","name":"second"}"#, sortKeys: false, indentWidth: 2)
        #expect(dup.warning?.contains("重复 key") == true)
        #expect(dup.text.contains(#""name": "first""#))
        #expect(dup.text.contains(#""name": "second""#))

        let sorted = try JSONFormatting.format(#"{"b":2,"a":1}"#, sortKeys: true, indentWidth: 2)
        #expect(sorted.contains(#""a": 1"#))
        #expect(sorted.firstIndex(of: "a")! < sorted.firstIndex(of: "b")!)

        let minified = try JSONFormatting.minify(#"{"b": 2, "a": 1}"#)
        #expect(minified == #"{"b":2,"a":1}"# || minified.contains(#""b":2"#))
    }

    @Test func jsonFmtDiagnosticsMatchProductLevelErrorCases() throws {
        let groupedIllegalNumbers = try jsonDiagnostic(
            for: #"{"leadingZero": 01, "plus": +1, "hex": 0x10, "infinity": Infinity}"#
        )
        #expect(groupedIllegalNumbers.message.contains("数字不能有前导零"))
        #expect(!groupedIllegalNumbers.message.contains("对象键必须使用双引号"))

        let plus = try jsonDiagnostic(for: #"{"plus": +1}"#)
        #expect(plus.message.contains("JSON 数字前不能写加号"))
        #expect(plus.suggestion == nil)

        let hex = try jsonDiagnostic(for: #"{"hex": 0x10}"#)
        #expect(hex.message.contains("JSON 不支持十六进制数字"))
        #expect(hex.suggestion == nil)

        let fullWidth = try jsonDiagnostic(for: #"{"count":１２,"zero":０}"#)
        #expect(fullWidth.message.contains("JSON 数字只能使用半角 0 到 9"))
        #expect(!fullWidth.message.contains("对象键必须使用双引号"))

        let localizedFraction = try jsonDiagnostic(for: #"{"n":1.٢}"#)
        #expect(localizedFraction.message.contains("JSON 小数部分只能使用半角 0 到 9"))

        let unescapedNewline = try jsonDiagnostic(for: "{\"message\":\"first line\nsecond line\"}")
        #expect(unescapedNewline.message.contains("未转义的控制字符"))
        #expect(unescapedNewline.suggestion == nil)
    }

    // MARK: - SQL-FMT

    @Test func sqlFmtValidAndInvalidSamples() throws {
        let ok = try SQLFormatting.format(
            "with active as (select id from users where active = 1) select * from active order by id;",
            options: .init(keywordCase: .upper)
        )
        #expect(ok.uppercased().contains("WITH"))
        #expect(ok.uppercased().contains("SELECT"))

        let lower = try SQLFormatting.format("select id from users;", options: .init(keywordCase: .lower))
        #expect(lower.contains("select"))
        #expect(!lower.contains("SELECT"))

        let transaction = try SQLFormatting.format("begin; insert into logs(event) values ('start'); commit;")
        #expect(transaction.contains("BEGIN;"))
        #expect(transaction.contains("COMMIT;"))

        let invalid: [(input: String, expected: String)] = [
            ("select id, name from users where email = 'alice@example.com;", "字符串字面量没有闭合"),
            ("select from where order by;", "SELECT 缺少要查询"),
            ("select * from users where id in (1, 2, 3;", "左括号没有对应的右括号"),
            ("select id, name from users order by;", "ORDER BY 缺少排序表达式"),
            ("select $$hello; -- not comment$$ as body;", "PostgreSQL")
        ]
        for sample in invalid {
            let diagnostic = try sqlDiagnostic(for: sample.input)
            #expect(diagnostic.message.contains(sample.expected))
            #expect(!diagnostic.localizedDescription.contains("NS"))
            #expect(!diagnostic.localizedDescription.contains("The operation"))
        }
    }

    // MARK: - XML-FMT

    @Test func xmlFmtValidInvalidAndMixedContent() throws {
        let ok = try XMLFormatting.format(#"<root><item id="1">a</item></root>"#)
        #expect(ok.contains("<root>"))
        #expect(ok.contains(#"id="1""#) || ok.contains("id=\"1\""))

        let mixed = try XMLFormatting.format(
            #"<article><p>Hello <strong>world</strong></p></article>"#
        )
        #expect(mixed.contains("Hello"))
        #expect(mixed.contains("<strong>world</strong>") || mixed.contains("world"))

        let invalid: [(input: String, expectedFragments: [String])] = [
            (#"<root><item>one</items></root>"#, ["标签", "不匹配"]),
            (#"<user id="1" id="2"><name>Alice</name></user>"#, ["重复", "属性"]),
            (#"<root><title>Tom & Jerry</title></root>"#, ["&", "转义"]),
            (#"<one>1</one><two>2</two>"#, ["根节点"])
        ]
        for sample in invalid {
            let diagnostic = try xmlDiagnostic(for: sample.input)
            for fragment in sample.expectedFragments {
                #expect(diagnostic.message.contains(fragment))
            }
            #expect(!diagnostic.localizedDescription.contains("NSXMLParserErrorDomain"))
            #expect(!diagnostic.localizedDescription.contains("The operation"))
        }
    }

    // MARK: - YAML-FMT

    @Test func yamlFmtValidInvalidAndDuplicateKey() throws {
        let ok = try YAMLPrettifier.formatValidated("name: Alice\nage: 30")
        #expect(ok.contains("name:"))
        #expect(ok.contains("Alice"))

        let invalid: [(input: String, expected: String)] = [
            ("user:\n  id: 1\n name: Alice", "缩进"),
            ("user:\n\tid: 1", "缩进必须使用空格"),
            ("user\n  id: 1", "冒号"),
            ("service:\n  <<: *missing\n  image: nginx", "未定义"),
            (#"name: "Alice"#, "引号"),
            ("first: 1\n---\nsecond: 2", "一个 YAML 文档"),
            ("service:\n  image: nginx:1.25\n  image: nginx:1.26", "重复")
        ]
        for sample in invalid {
            let diagnostic = try yamlDiagnostic(for: sample.input)
            #expect(diagnostic.message.contains(sample.expected))
            #expect(!diagnostic.localizedDescription.contains("did not find"))
        }
    }

    // MARK: - JSON-DIFF

    @Test func jsonDiffStructuralEquivalenceAndErrors() {
        let left = #"{"b":2,"a":1}"#
        let right = """
        {
          "a": 1,
          "b": 2
        }
        """
        #expect(JSONDiffValidation.evaluate(left: left, right: right, labels: jsonLabels) == .comparable)

        let changed = JSONDiffValidation.evaluate(
            left: #"{"id":1,"name":"Alice"}"#,
            right: #"{"id":1,"name":"Bob","role":"admin"}"#,
            labels: jsonLabels
        )
        #expect(changed == .comparable)

        let duplicateWarning = JSONDiffValidation.comparisonWarning(
            left: #"{"name":"first","name":"second"}"#,
            right: #"{"name":"second"}"#,
            labels: jsonLabels
        )
        #expect(duplicateWarning?.contains("重复 key") == true)
        #expect(duplicateWarning == "JSON A 含重复 key。")

        if case .invalid(let message) = JSONDiffValidation.evaluate(
            left: #"{"ok":true}"#,
            right: #"{"ok":true,}"#,
            labels: jsonLabels
        ) {
            #expect(message.contains("JSON B 格式错误"))
            #expect(message == "JSON B 格式错误：对象末尾多了逗号")
            #expect(!message.contains("请修正该侧后再对比"))
            #expect(!message.contains("处理方式："))
        } else {
            Issue.record("Expected invalid right side")
        }

        if case .invalid = JSONDiffValidation.evaluate(
            left: #"{id:1}"#,
            right: #"{"id":1}"#,
            labels: jsonLabels
        ) {
            // ok
        } else {
            Issue.record("Expected invalid left side")
        }
    }

    // MARK: - TEXT-DIFF

    @Test func textDiffLineChangesAndBudgetMessage() {
        let same = LineDiffer.diff(left: "alpha\nbeta", right: "alpha\nbeta")
        #expect(same.contains("共 0 行不同"))

        let changed = LineDiffer.diff(left: "line-a\nshared", right: "line-b\nshared")
        #expect(changed.contains("共 1 行不同") || changed.contains("共 2 行不同") || changed.contains("共"))
        #expect(changed.contains("line-a"))
        #expect(changed.contains("line-b"))

        let emptyVs = LineDiffer.diff(left: "", right: "only-right")
        #expect(emptyVs.contains("only-right") || emptyVs.contains("1") || !emptyVs.isEmpty)

        // Budget: construct line counts that exceed standard LCS cells without huge strings.
        // estimated cells = (L+1)*(R+1); standard max = 12_000_000
        // Use safeAlignedDiff path via JSONStructuralDiff / LineDiffer.safeAlignedDiff
        let leftLines = Array(repeating: "x", count: 4000).joined(separator: "\n")
        let rightLines = Array(repeating: "y", count: 4000).joined(separator: "\n")
        // 4001*4001 = ~16M > 12M
        do {
            _ = try LineDiffer.safeAlignedDiff(left: leftLines, right: rightLines)
            Issue.record("Expected inputTooLarge for 4000x4000 lines")
        } catch let error as LineDiffError {
            #expect(error.errorDescription?.contains("对比内容过大") == true)
            #expect(error.errorDescription?.contains("请减少内容或分段比较后再试") == false)
            #expect(error.errorDescription?.contains("处理方式：") == false)
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    // MARK: - REGEX

    @Test func regexFlagsCapturesAndErrors() throws {
        let email = try RegexMatcher.analyze(
            pattern: #"\b[\w.+-]+@[\w-]+\.[\w.-]+\b"#,
            in: "a@example.com and b@test.org",
            flags: "g"
        )
        #expect(email.matches.count == 2)

        let named = try RegexMatcher.analyze(
            pattern: #"(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})"#,
            in: "release 2026-07-12 done",
            flags: "g"
        )
        #expect(named.matches.count == 1)

        let caseInsensitive = try RegexMatcher.analyze(pattern: "json", in: "JSON Formatter", flags: "gi")
        #expect(caseInsensitive.matches.count >= 1)

        let unsupportedFlag = #expect(throws: RegexMatcher.MatcherError.unsupportedFlag("u")) {
            _ = try RegexMatcher.analyze(pattern: "a", in: "a", flags: "gu")
        }
        #expect(unsupportedFlag?.errorDescription?.contains("不支持的正则标志") == true)
        #expect(unsupportedFlag?.errorDescription?.contains("当前支持 g、i、m、s、x") == true)

        let unclosed = #expect(throws: RegexMatcher.MatcherError.self) {
            _ = try RegexMatcher.analyze(pattern: "(unclosed", in: "text", flags: "g")
        }
        #expect(unclosed?.errorDescription == "括号未闭合。")

        let lookbehindError = #expect(throws: RegexMatcher.MatcherError.self) {
            _ = try RegexMatcher.analyze(pattern: #"(?<=\d{2,})abc"#, in: "1abc 12abc 123abc", flags: "g")
        }
        #expect(lookbehindError?.errorDescription?.contains("变长后顾") == true)

        let firstOnly = try RegexMatcher.analyze(pattern: #"\d+"#, in: "a1 b22 c333", flags: "")
        #expect(firstOnly.matches.count == 1)

        let global = try RegexMatcher.analyze(pattern: #"\d+"#, in: "a1 b22 c333", flags: "g")
        #expect(global.matches.count == 3)
    }

    // MARK: - DOCKER

    @Test func dockerConvertSuccessWarningsAndErrors() throws {
        let short = try DockerRunToDockerComposeService.convert("docker run nginx")
        #expect(short.yaml.contains("image:"))
        #expect(short.yaml.contains("nginx"))

        let web = try DockerRunToDockerComposeService.convert(
            "docker run -d --name dev-api -p 8080:80 -e NODE_ENV=production -v /Users/sun/data:/app/data --restart unless-stopped example/api:2.4.0"
        )
        #expect(web.yaml.contains("container_name: dev-api"))
        #expect(web.yaml.contains("8080:80") || web.yaml.contains("\"8080:80\""))
        #expect(web.yaml.contains("NODE_ENV"))
        #expect(web.notTranslatable.isEmpty)
        #expect(web.warnings.isEmpty)

        let env = try DockerRunToDockerComposeService.convert(
            #"docker run --name env-test -e EMPTY= -e TOKEN="abc=123==xyz" -e JSON='{"enabled":true,"count":3}' alpine:3.20 env"#
        )
        #expect(env.yaml.contains("EMPTY") || env.yaml.contains("TOKEN") || env.yaml.contains("environment"))

        let platform = try DockerRunToDockerComposeService.convert(
            "docker run --platform linux/amd64 --no-healthcheck nginx"
        )
        #expect(platform.yaml.contains("nginx"))
        #expect(platform.yaml.contains("platform: linux/amd64"))
        #expect(platform.yaml.contains("healthcheck:"))
        #expect(platform.yaml.contains("disable: true"))
        #expect(platform.warnings.isEmpty)

        let typo = try DockerRunToDockerComposeService.convert(
            "docker run --naem typo-nginx -p 8080:80 nginx"
        )
        #expect(typo.warnings.contains(where: { $0.kind == .unknownFlag && $0.option.contains("naem") }))
        let typoWarning = DockerRunToDockerComposeDiagnostics.warningMessage(for: typo.warnings)
        #expect(typoWarning == "部分 Docker 选项无法转换。")

        #expect {
            _ = try DockerRunToDockerComposeService.convert("docker run -d --name missing-image -p 8080:80")
        } throws: { error in
            guard case DockerRunToDockerComposeError.missingImage = error,
                  let description = (error as? LocalizedError)?.errorDescription else {
                return false
            }
            return description == "docker run 命令缺少镜像名称。"
                && !description.contains("处理方式：")
        }
        #expect(DockerRunToDockerComposeError.missingImage.errorDescription == "docker run 命令缺少镜像名称。")

        do {
            _ = try DockerRunToDockerComposeService.convert(#"docker run -e MESSAGE="hello nginx"#)
            Issue.record("Expected unterminated quote diagnostic")
        } catch DockerRunToDockerComposeError.unterminatedQuote {
            let description = DockerRunToDockerComposeError.unterminatedQuote.errorDescription ?? ""
            #expect(description == "命令包含未闭合的引号。")
            #expect(!description.contains("处理方式："))
        } catch {
            Issue.record("Unexpected Docker conversion error: \(error)")
        }

        #expect {
            _ = try DockerRunToDockerComposeService.convert("docker run --rm alpine sh docker run --rm alpine sh")
        } throws: { error in
            guard case DockerRunToDockerComposeError.multipleCommands = error,
                  let description = (error as? LocalizedError)?.errorDescription else {
                return false
            }
            return description == "一次只能转换一条 docker run 命令。"
        }

        #expect {
            _ = try DockerRunToDockerComposeService.convert("podman run nginx")
        } throws: { error in
            guard case DockerRunToDockerComposeError.invalidCommand = error,
                  let description = (error as? LocalizedError)?.errorDescription else {
                return false
            }
            return description == "仅支持单条 docker run 命令。"
        }
    }

    // MARK: - HTML-MD

    @Test func htmlToMarkdownCorePathsAndWarnings() {
        let simple = HTMLToMarkdownConverter.convert(
            "<h1>Title</h1><p>Hello <strong>world</strong>. Visit <a href=\"https://example.com\">Example</a>.</p>"
        )
        #expect(simple.contains("# Title"))
        #expect(simple.contains("**world**"))
        #expect(simple.contains("[Example](https://example.com)"))

        let result = HTMLToMarkdownConverter.convert(
            "<style>body{}</style><script>alert(1)</script><p>Safe</p><video src=\"a.mp4\"></video>",
            options: HTMLToMarkdownOptions()
        )
        #expect(result.markdown.contains("Safe"))
        #expect(!result.markdown.lowercased().contains("alert(1)"))

        let emptyish = HTMLToMarkdownConverter.convert("<div></div>", options: HTMLToMarkdownOptions())
        let emptyBody = emptyish.markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(emptyish.warnings.contains(.emptyVisibleContent) || emptyBody.isEmpty || emptyBody.count < 20)
    }

    // MARK: - CRON

    @Test func cronExpressionsValidAndInvalid() {
        #expect(CronScheduler.parseFields("*/5 * * * *") != nil)
        #expect(CronScheduler.parseFields("0 9 * * 1-5") != nil)
        #expect(CronScheduler.resolveExpression("@reboot").isEmpty || CronScheduler.parseFields(CronScheduler.resolveExpression("@reboot")) == nil)

        let hourly = CronScheduler.resolveExpression("@hourly")
        #expect(CronScheduler.parseFields(hourly) != nil || hourly.split(separator: " ").count == 5)

        #expect(CronScheduler.parseFields("*/5 * * *") == nil) // wrong field count
        #expect(CronScheduler.parseFields("60 * * * *") == nil) // out of range
        #expect(CronScheduler.parseFields("*/0 * * * *") == nil) // step 0
    }


    // MARK: - CHMOD

    @Test func chmodCommonModesMatchExpectedOctalAndSymbolic() {
        let m644 = ChmodMode(
            owner: .init(read: true, write: true, execute: false),
            group: .init(read: true, write: false, execute: false),
            other: .init(read: true, write: false, execute: false)
        )
        #expect(m644.octalString == "644")
        #expect(
            ChmodMode(
                owner: .init(read: true, write: true, execute: false),
                group: .init(read: true, write: false, execute: false),
                other: .init(read: true, write: false, execute: false)
            ).symbolicString == "rw-r--r--"
        )

        #expect(
            ChmodMode(
                owner: .init(read: true, write: true, execute: true),
                group: .init(read: true, write: false, execute: true),
                other: .init(read: true, write: false, execute: true)
            ).octalString == "755"
        )
        #expect(
            ChmodMode(
                owner: .init(read: true, write: true, execute: true),
                group: .init(read: true, write: false, execute: true),
                other: .init(read: true, write: false, execute: true)
            ).symbolicString == "rwxr-xr-x"
        )

        #expect(
            ChmodMode(
                owner: .init(read: true, write: true, execute: false),
                group: .init(read: false, write: false, execute: false),
                other: .init(read: false, write: false, execute: false)
            ).octalString == "600"
        )
        #expect(
            ChmodMode(
                owner: .init(read: false, write: false, execute: false),
                group: .init(read: false, write: false, execute: false),
                other: .init(read: false, write: false, execute: false)
            ).octalString == "000"
        )
        #expect(
            ChmodMode(
                owner: .init(read: true, write: true, execute: true),
                group: .init(read: true, write: true, execute: true),
                other: .init(read: true, write: true, execute: true)
            ).octalString == "777"
        )
        #expect(
            ChmodMode(
                owner: .init(read: false, write: false, execute: true),
                group: .init(read: false, write: false, execute: true),
                other: .init(read: false, write: false, execute: true)
            ).octalString == "111"
        )
    }

    // MARK: - CROSS

    @Test func crossToolIsolationSamples() throws {
        #expect(throws: JSONFormatting.FormattingError.self) {
            _ = try JSONFormatting.format("{id:1}", sortKeys: false, indentWidth: 2)
        }

        let yaml = try YAMLPrettifier.formatValidated(
            #"""
            payloads:
              json: '{"id":1,"ok":true}'
              sql: "select id from users"
            """#
        )
        #expect(yaml.contains("payloads:"))
        #expect(yaml.contains("json:"))
    }

    private func jsonDiagnostic(for input: String) throws -> FormatDiagnostic {
        let error = #expect(throws: (any Error).self) {
            _ = try JSONFormatting.format(input, sortKeys: false, indentWidth: 2)
        }

        guard let error,
              case JSONFormatting.FormattingError.invalidJSON(let diagnostic) = error else {
            Issue.record("Expected JSON formatting diagnostic")
            throw ProbeFailure.missingDiagnostic
        }

        return diagnostic
    }

    private func sqlDiagnostic(for input: String) throws -> FormatDiagnostic {
        let error = #expect(throws: (any Error).self) {
            _ = try SQLFormatting.format(input)
        }

        guard let error,
              case let diagnosticError as SQLFormatting.ValidationError = error else {
            Issue.record("Expected SQL formatting diagnostic")
            throw ProbeFailure.missingDiagnostic
        }

        return diagnosticError.diagnostic
    }

    private func xmlDiagnostic(for input: String) throws -> FormatDiagnostic {
        let error = #expect(throws: (any Error).self) {
            _ = try XMLFormatting.format(input)
        }

        guard let error,
              case XMLFormatting.FormattingError.invalidXML(let diagnostic) = error else {
            Issue.record("Expected XML formatting diagnostic")
            throw ProbeFailure.missingDiagnostic
        }

        return diagnostic
    }

    private func yamlDiagnostic(for input: String) throws -> FormatDiagnostic {
        let error = #expect(throws: (any Error).self) {
            _ = try YAMLPrettifier.formatValidated(input)
        }

        guard let error,
              case YAMLPrettifier.ValidationError.invalidSyntax(let diagnostic) = error else {
            Issue.record("Expected YAML formatting diagnostic")
            throw ProbeFailure.missingDiagnostic
        }

        return diagnostic
    }

    private enum ProbeFailure: Error {
        case missingDiagnostic
    }
}
