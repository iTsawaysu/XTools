@testable import XToolsCore
import Foundation
import Testing

/// 独有探针输入：只覆盖各域 A 类测试没有碰过的输入组合。
/// 与域内测试逐字重复的诊断文案断言已在 2026-10 审计中删除；
/// 标准向量请去各域测试文件（JSONUtilitiesTests / SQLFormattingTests 等）。
struct DevelopmentTestDataProbeTests {
    private let jsonLabels = JSONDiffValidation.SideLabels(left: "JSON A", right: "JSON B")

    // MARK: - 跨工具空白输入

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

    // MARK: - JSON-FMT 独有输入

    @Test func jsonFmtDiagnosticsPreferTheFirstReportedError() throws {
        // 同一文档里多个非法数字并存时，只报第一类错误，不串报键名问题。
        let groupedIllegalNumbers = try jsonDiagnostic(
            for: #"{"leadingZero": 01, "plus": +1, "hex": 0x10, "infinity": Infinity}"#
        )
        #expect(groupedIllegalNumbers.message.contains("数字不能有前导零"))
        #expect(!groupedIllegalNumbers.message.contains("对象键必须使用双引号"))
    }

    @Test func jsonFormatterSupportsTopLevelScalars() throws {
        #expect(try JSONFormatting.format(#""just a string""#, sortKeys: false, indentWidth: 2) == #""just a string""#)
        #expect(try JSONFormatting.format("-123.45e+6", sortKeys: false, indentWidth: 2) == "-123.45e+6")
    }

    // MARK: - SQL-FMT 独有输入

    @Test func sqlFmtDollarQuotedPayloadDiagnostic() throws {
        let diagnostic = try sqlDiagnostic(for: "select $$hello; -- not comment$$ as body;")
        #expect(diagnostic.message.contains("PostgreSQL"))
        #expect(!diagnostic.localizedDescription.contains("NS"))
        #expect(!diagnostic.localizedDescription.contains("The operation"))
    }

    @Test func sqlCommentLookalikesInsideStringLiteralsStayLiteral() throws {
        // `--` 出现在字符串字面量内时不是注释；路径里的反斜杠与 % 原样保留。
        let escaped = #"select 'it''s ok' as message from "order" where note = '-- not a comment' and path like 'C:\\temp\\%';"#
        let formatted = try SQLFormatting.format(escaped, options: .init(keywordCase: .lower))

        #expect(formatted.contains("'-- not a comment'"))
        #expect(formatted.contains(#"'C:\\temp\\%'"#))
    }

    // MARK: - XML-FMT 独有输入

    @Test func xmlFormatterRejectsExternalEntityDOCTYPE() {
        // XXE：外部实体声明不得展开进格式化输出。
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

    // MARK: - JSON-DIFF 独有输入

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

    @Test func jsonDiffIgnoresObjectKeyOrder() throws {
        let rows = try comparableJSONRows(
            left: #"{"a":1,"b":2,"c":{"x":10,"y":20}}"#,
            right: #"{"c":{"y":20,"x":10},"b":2,"a":1}"#
        )
        #expect(rows.isEmpty)
    }

    // MARK: - TEXT-DIFF 独有输入

    @Test func textDiffHandlesUnicodeAndControlCharacterLines() {
        let trailing = LineDiffer.alignedDiff(left: "alpha\nbeta \ngamma", right: "alpha\nbeta\ngamma\n")
        #expect(trailing.contains { $0.kind.isDifference })

        let unicode = LineDiffer.alignedDiff(left: "café\nemoji: 👨‍💻", right: "café\nemoji: 👩‍💻")
        #expect(unicode.contains { $0.kind.isDifference })

        let control = LineDiffer.alignedDiff(left: "col1\tcol2\nline with bell: \u{7}", right: "col1    col2\nline with bell:")
        #expect(control.contains { $0.kind.isDifference })
    }

    // MARK: - REGEX 独有输入

    @Test func regexMatcherMultilineAnchorsAndPartialEmailFiltering() throws {
        // 多行锚点 ^$ 只匹配行首/行尾；残缺邮箱不进结果。
        let multiline = try RegexMatcher.analyze(
            pattern: #"^ERROR\s+\[(.+?)\]\s+(.*)$"#,
            in: "INFO [api] started\nERROR [worker] job failed\nWARN [api] slow request\nERROR [db] connection timeout",
            flags: "gm"
        )
        #expect(multiline.matches.map(\.value) == ["ERROR [worker] job failed", "ERROR [db] connection timeout"])

        let email = try RegexMatcher.analyze(
            pattern: #"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"#,
            in: "Contact: alice@example.com, bob.smith+dev@sub.example.co.uk, invalid@, @missing.local, qa@test.io.",
            flags: "g"
        )
        #expect(email.matches.map(\.value) == ["alice@example.com", "bob.smith+dev@sub.example.co.uk", "qa@test.io"])
    }

    // MARK: - DOCKER 独有输入（run→compose 长形式旗标）

    @Test func dockerRunToComposeLongFormFlagsAndQuotedMounts() throws {
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
        // 8fe8d77：--mount 的完整选项映射为 Compose 长形式（-v 仍为短形式）。
        #expect(mounts.yaml.contains("- type: bind"))
        #expect(mounts.yaml.contains("source: /host/path"))
        #expect(mounts.yaml.contains("target: /data"))
        #expect(mounts.yaml.contains("read_only: true"))
        #expect(mounts.yaml.contains("- \"/run:size=64m\""))
        #expect(mounts.yaml.contains("- \"127.0.0.1:8080:80\""))
        #expect(mounts.yaml.contains("- \"53:53/udp\""))
    }

    // MARK: - HTML-MD 独有输入

    @Test func htmlToMarkdownNestedStrongLinksAndUnknownEntitiesPassThrough() {
        let markdown = HTMLToMarkdownConverter.convert(
            """
            <p><a href="/docs"><strong>Docs</strong></a></p>
            <p>unknown entity: &unknown; stays visible</p>
            <ol><li>one</li><li><del>two</del></li></ol>
            """
        )

        #expect(markdown.contains("[**Docs**](/docs)"))
        #expect(markdown.contains("&unknown;"))
        #expect(markdown.contains("1. one"))
        #expect(markdown.contains("2. ~~two~~"))
    }

    // MARK: - CHMOD 独有模式（644/755/000 见 ChmodCalculatorTests）

    @Test func chmodOctalAndSymbolicCoverTheRemainingModes() {
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
            ).symbolicString == "---------"
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
                owner: .init(read: true, write: true, execute: true),
                group: .init(read: true, write: true, execute: true),
                other: .init(read: true, write: true, execute: true)
            ).symbolicString == "rwxrwxrwx"
        )
        #expect(
            ChmodMode(
                owner: .init(read: false, write: false, execute: true),
                group: .init(read: false, write: false, execute: true),
                other: .init(read: false, write: false, execute: true)
            ).octalString == "111"
        )
        #expect(
            ChmodMode(
                owner: .init(read: false, write: false, execute: true),
                group: .init(read: false, write: false, execute: true),
                other: .init(read: false, write: false, execute: true)
            ).symbolicString == "--x--x--x"
        )
    }

    // MARK: - Helpers

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

    private func comparableJSONRows(left: String, right: String) throws -> [DiffAlignedRow] {
        let decision = JSONStructuralDiff.alignedDiff(left: left, right: right, labels: jsonLabels)
        guard case .comparable(let rows) = decision else {
            Issue.record("Expected comparable JSON diff, got \(decision)")
            return []
        }
        return rows
    }

    private enum ProbeFailure: Error {
        case missingDiagnostic
    }
}
