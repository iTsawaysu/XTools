@testable import XToolsCore
import Foundation
import Testing

struct ExpandedDevelopmentTestDataTests {
    private let jsonLabels = JSONDiffValidation.SideLabels(left: "JSON A", right: "JSON B")

    @Test func jsonFormatterRejectsInvalidNumbersAndUnicodeEscapes() {
        let invalidSamples = [
            #"{"leadingZero": 01, "plus": +1, "hex": 0x10, "infinity": Infinity}"#,
            #"{"badEscape":"\uZZZZ","badSurrogate":"\uD83D"}"#
        ]

        for sample in invalidSamples {
            #expect(throws: JSONFormatting.FormattingError.self) {
                _ = try JSONFormatting.format(sample, sortKeys: false, indentWidth: 2)
            }
        }
    }

    @Test func jsonFormatterSupportsTopLevelScalarsAndDuplicateKeyWarning() throws {
        #expect(try JSONFormatting.format(#""just a string""#, sortKeys: false, indentWidth: 2) == #""just a string""#)
        #expect(try JSONFormatting.format("-123.45e+6", sortKeys: false, indentWidth: 2) == "-123.45e+6")

        let result = try JSONFormatting.formatResult(#"{"id":1,"name":"first","name":"second"}"#, sortKeys: false, indentWidth: 2)
        #expect(result.warning == "JSON 含重复 key。")
        #expect(result.duplicateKeys == ["name"])
        #expect(result.text.contains(#""name": "first""#))
        #expect(result.text.contains(#""name": "second""#))
    }

    @Test func sqlFormatterRejectsExpandedInvalidSamples() throws {
        let invalidSamples = [
            "select id, name from users where email = 'alice@example.com;",
            "select from where order by;",
            "select * from users where id in (1, 2, 3;",
            "select id, name from users order by;"
        ]

        for sample in invalidSamples {
            #expect(throws: SQLFormatting.ValidationError.self) {
                _ = try SQLFormatting.format(sample)
            }
        }
    }

    @Test func sqlFormatterPreservesQuotedStringsIdentifiersAndKeywordCase() throws {
        let escaped = #"select 'it''s ok' as message, "quoted""identifier" as ident, `quoted``identifier` as mysql_ident from "order" where note = '-- not a comment' and path like 'C:\\temp\\%';"#
        let formatted = try SQLFormatting.format(escaped, options: .init(keywordCase: .lower))

        #expect(formatted.contains("select"))
        #expect(formatted.contains("from"))
        #expect(formatted.contains("'it''s ok'"))
        #expect(formatted.contains(#""quoted""identifier""#))
        #expect(formatted.contains(#"`quoted``identifier`"#))
        #expect(formatted.contains("'-- not a comment'"))
        #expect(formatted.contains(#"'C:\\temp\\%'"#))
    }

    @Test func xmlFormatterRejectsUnsafeOrMalformedExpandedSamples() {
        let malformedSamples = [
            #"<root><item>one</items></root>"#,
            #"<user id="1" id="2"><name>Alice</name></user>"#,
            #"<root><title>Tom & Jerry</title></root>"#,
            #"<root><item id=123>bad attribute</item></root>"#,
            #"<one>1</one><two>2</two>"#
        ]

        for sample in malformedSamples {
            #expect(throws: XMLFormatting.FormattingError.self) {
                _ = try XMLFormatting.format(sample)
            }
        }

        let externalEntity = """
        <!DOCTYPE root [
          <!ENTITY ext SYSTEM "file:///etc/passwd">
        ]>
        <root>&ext;</root>
        """

        do {
            let output = try XMLFormatting.format(externalEntity)
            #expect(!output.contains("root:x:"))
            #expect(!output.contains("/bin/"))
        } catch let error as XMLFormatting.FormattingError {
            #expect(error.diagnostic.displayMessage == "不支持 DOCTYPE 声明")
            #expect(error.diagnostic.formatName == "XML")
        } catch {
            Issue.record("Expected XML formatting error, got \(error)")
        }
    }

    @Test func yamlFormatterRejectsExpandedInvalidSamplesAndPreservesBlockScalars() throws {
        let invalidSamples = [
            "user:\n  id: 1\n name: Alice",
            "user:\n\tid: 1\n\tname: Alice",
            "user\n  id: 1",
            "service:\n  <<: *missing_defaults\n  image: nginx",
            #"name: "Alice"#,
            "first: 1\n---\nsecond: 2",
            "service:\n  image: nginx:1.25\n  image: nginx:1.26"
        ]

        for sample in invalidSamples {
            #expect(throws: YAMLPrettifier.ValidationError.self) {
                _ = try YAMLPrettifier.formatValidated(sample)
            }
        }

        let block = """
        script: |
          echo "start: $(date)"
          curl -H "Accept: application/json" https://example.com/api
          cat <<'JSON'
          {"id":1,"ok":true}
          JSON
        next: value
        """
        let formatted = try YAMLPrettifier.formatValidated(block)
        #expect(formatted.contains("script: |"))
        #expect(formatted.contains(#"echo "start: $(date)""#))
        #expect(formatted.contains("next: value"))
    }

    @Test func jsonDiffCanonicalizesBeforeShowingLargeArrayLocalDifferences() throws {
        let left = #"{"items":[{"id":1,"status":"ok"},{"id":2,"status":"ok"},{"id":3,"status":"ok"},{"id":4,"status":"ok"},{"id":5,"status":"ok"}]}"#
        let right = #"{"items":[{"id":1,"status":"ok"},{"id":2,"status":"ok"},{"id":3,"status":"failed"},{"id":4,"status":"ok"},{"id":6,"status":"new"}]}"#

        let rows = try comparableJSONRows(left: left, right: right)
        let visibleTexts = rows.flatMap { [$0.left?.text, $0.right?.text].compactMap(\.self) }

        #expect(rows.count > 10)
        #expect(visibleTexts.contains { $0.trimmingCharacters(in: .whitespaces) == #""status": "failed""# })
        #expect(visibleTexts.contains { $0.trimmingCharacters(in: .whitespaces) == #""id": 6,"# })
        #expect(rows.filter(\.kind.isDifference).count < rows.count)
    }

    @Test func jsonDiffBlocksInvalidSidesAndIgnoresObjectKeyOrder() throws {
        let invalidDecision = JSONStructuralDiff.alignedDiff(
            left: #"{"id":1,"name":"Alice"}"#,
            right: #"{"id":1,"name":"Alice",}"#,
            labels: jsonLabels
        )
        guard case .invalid(let invalidMessage) = invalidDecision else {
            Issue.record("Expected invalid JSON diff decision")
            return
        }
        #expect(invalidMessage.contains("JSON B 格式错误"))
        #expect(invalidMessage == "JSON B 格式错误：对象末尾多了逗号")

        let rows = try comparableJSONRows(
            left: #"{"a":1,"b":2,"c":{"x":10,"y":20}}"#,
            right: #"{"c":{"y":20,"x":10},"b":2,"a":1}"#
        )
        #expect(rows.isEmpty)
    }

    @Test func textDiffHandlesWhitespaceUnicodeLongLinesAndControlCharacters() {
        let trailing = LineDiffer.alignedDiff(left: "alpha\nbeta \ngamma", right: "alpha\nbeta\ngamma\n")
        #expect(trailing.contains { $0.kind.isDifference })

        let unicode = LineDiffer.alignedDiff(left: "café\nemoji: 👨‍💻", right: "café\nemoji: 👩‍💻")
        #expect(unicode.contains { $0.kind.isDifference })

        let longLeft = "token=" + String(repeating: "a", count: 160)
        let longRight = "token=" + String(repeating: "a", count: 80) + "b" + String(repeating: "a", count: 79)
        let longRows = LineDiffer.alignedDiff(left: longLeft, right: longRight)
        #expect(longRows.first?.kind == .changed)
        #expect(longRows.first?.right?.segments.contains { $0.kind == .added && $0.text.contains("b") } == true)

        let control = LineDiffer.alignedDiff(left: "col1\tcol2\nline with bell: \u{7}", right: "col1    col2\nline with bell:")
        #expect(control.contains { $0.kind.isDifference })
    }

    @Test func regexMatcherCoversExpandedSamples() throws {
        let email = try RegexMatcher.analyze(
            pattern: #"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"#,
            in: "Contact: alice@example.com, bob.smith+dev@sub.example.co.uk, invalid@, @missing.local, qa@test.io.",
            flags: "g"
        )
        #expect(email.matches.map(\.value) == ["alice@example.com", "bob.smith+dev@sub.example.co.uk", "qa@test.io"])

        let dates = try RegexMatcher.analyze(
            pattern: #"(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})"#,
            in: "release=2026-07-07, invalid=2026-7-7, next=2026-12-31",
            flags: "g"
        )
        #expect(dates.matches.count == 2)
        #expect(dates.matches.first?.groups.map(\.name) == ["year", "month", "day"])

        let multiline = try RegexMatcher.analyze(
            pattern: #"^ERROR\s+\[(.+?)\]\s+(.*)$"#,
            in: "INFO [api] started\nERROR [worker] job failed\nWARN [api] slow request\nERROR [db] connection timeout",
            flags: "gm"
        )
        #expect(multiline.matches.map(\.value) == ["ERROR [worker] job failed", "ERROR [db] connection timeout"])

        #expect(throws: RegexMatcher.MatcherError.unsupportedFlag("u")) {
            _ = try RegexMatcher.analyze(pattern: #"[\p{Script=Han}]+"#, in: "Hello 世界", flags: "gu")
        }
        #expect(throws: RegexMatcher.MatcherError.unsupportedFlag("y")) {
            _ = try RegexMatcher.analyze(pattern: #"\d+"#, in: "1 2", flags: "y")
        }
    }

    @Test func dockerConversionCoversExpandedFlagsWarningsAndEscaping() throws {
        let service = try DockerRunToDockerComposeService.convert(
            #"docker run --env-file .env --hostname app-host --expose 8080 --read-only --init nginx"#
        )
        #expect(service.yaml.contains("env_file:"))
        #expect(service.yaml.contains("- .env"))
        #expect(service.yaml.contains("hostname: app-host"))
        #expect(service.yaml.contains("expose:"))
        #expect(service.yaml.contains("- \"8080\""))
        #expect(service.yaml.contains("read_only: true"))
        #expect(service.yaml.contains("init: true"))

        let mounts = try DockerRunToDockerComposeService.convert(
            #"docker run --mount type=bind,source=/host/path,target=/data,readonly --tmpfs /run:size=64m -p127.0.0.1:8080:80/tcp -p 53:53/udp nginx"#
        )
        #expect(mounts.yaml.contains("- \"/host/path:/data:ro\""))
        #expect(mounts.yaml.contains("- \"/run:size=64m\""))
        #expect(mounts.yaml.contains("- \"127.0.0.1:8080:80\""))
        #expect(mounts.yaml.contains("- \"53:53/udp\""))

        let supported = try DockerRunToDockerComposeService.convert("docker run --platform linux/amd64 --no-healthcheck nginx")
        #expect(supported.yaml.contains("image: nginx"))
        #expect(supported.yaml.contains("platform: linux/amd64"))
        #expect(supported.yaml.contains("healthcheck:"))
        #expect(supported.yaml.contains("disable: true"))
        #expect(supported.warnings.isEmpty)

        #expect {
            _ = try DockerRunToDockerComposeService.convert("docker run nginx docker run redis")
        } throws: { error in
            guard case DockerRunToDockerComposeError.multipleCommands = error else {
                return false
            }
            return true
        }
    }

    @Test func htmlToMarkdownCoversExpandedEntityAndStructureSamples() {
        let markdown = HTMLToMarkdownConverter.convert(
            """
            <!-- comment -->
            <h1>Title</h1><p>A&nbsp;B<br>C &#x1F600; &#169; &unknown;</p>
            <p><a href="/docs"><strong>Docs</strong></a></p>
            <script>alert("x")</script><style>body{}</style>
            <hr><ol><li>one</li><li><del>two</del></li></ol>
            <table><tr><th>Name</th><th>Value</th></tr><tr><td>A | B</td><td>1</td></tr></table>
            """
        )

        #expect(markdown.contains("# Title"))
        #expect(markdown.contains("A B"))
        #expect(markdown.contains("😀"))
        #expect(markdown.contains("©"))
        #expect(markdown.contains("&unknown;"))
        #expect(markdown.contains("[**Docs**](/docs)"))
        #expect(markdown.contains("---"))
        #expect(markdown.contains("1. one"))
        #expect(markdown.contains("2. ~~two~~"))
        #expect(markdown.contains("A \\| B"))
        #expect(!markdown.contains("alert"))
        #expect(!markdown.localizedCaseInsensitiveContains("<script"))
    }

    @Test func cronSchedulerCoversExpandedExpressions() {
        #expect(CronScheduler.resolveExpression("@reboot") == "")
        #expect(CronScheduler.nextRuns("@reboot", count: 3, after: Date(timeIntervalSince1970: 0), calendar: Calendar(identifier: .gregorian)).isEmpty)

        #expect(CronScheduler.parseFields("*/5 * * * *")?.minutes == Set(stride(from: 0, through: 55, by: 5)))
        #expect(CronScheduler.parseFields("0 9 * * 1-5")?.weekdays == Set([1, 2, 3, 4, 5]))
        #expect(CronScheduler.parseFields("30 8 1 JAN MON")?.months == Set([1]))
        #expect(CronScheduler.parseFields("30 8 1 JAN MON")?.weekdays == Set([1]))
        #expect(CronScheduler.parseFields("0 0 * * 0")?.weekdays == Set([0]))
        #expect(CronScheduler.parseFields("0 0 * * 7")?.weekdays == Set([7]))
        #expect(CronScheduler.parseFields("* * * *") == nil)
        #expect(CronScheduler.parseFields("60 24 32 13 8") == nil)
        #expect(CronScheduler.parseFields("*/0 * * * *") == nil)
    }

    @Test func chmodCalculatorCoversExpandedPermissionSamples() {
        let samples: [(octal: String, symbolic: String, owner: (Bool, Bool, Bool), group: (Bool, Bool, Bool), other: (Bool, Bool, Bool))] = [
            ("644", "rw-r--r--", (true, true, false), (true, false, false), (true, false, false)),
            ("755", "rwxr-xr-x", (true, true, true), (true, false, true), (true, false, true)),
            ("600", "rw-------", (true, true, false), (false, false, false), (false, false, false)),
            ("000", "---------", (false, false, false), (false, false, false), (false, false, false)),
            ("777", "rwxrwxrwx", (true, true, true), (true, true, true), (true, true, true)),
            ("111", "--x--x--x", (false, false, true), (false, false, true), (false, false, true))
        ]

        for sample in samples {
            #expect(ChmodMode(owner: .init(read: sample.owner.0, write: sample.owner.1, execute: sample.owner.2), group: .init(read: sample.group.0, write: sample.group.1, execute: sample.group.2), other: .init(read: sample.other.0, write: sample.other.1, execute: sample.other.2)).octalString == sample.octal)
            #expect(ChmodMode(owner: .init(read: sample.owner.0, write: sample.owner.1, execute: sample.owner.2), group: .init(read: sample.group.0, write: sample.group.1, execute: sample.group.2), other: .init(read: sample.other.0, write: sample.other.1, execute: sample.other.2)).symbolicString == sample.symbolic)
        }
    }

    private func comparableJSONRows(left: String, right: String) throws -> [DiffAlignedRow] {
        let decision = JSONStructuralDiff.alignedDiff(left: left, right: right, labels: jsonLabels)
        guard case .comparable(let rows) = decision else {
            Issue.record("Expected comparable JSON diff, got \(decision)")
            return []
        }
        return rows
    }
}
