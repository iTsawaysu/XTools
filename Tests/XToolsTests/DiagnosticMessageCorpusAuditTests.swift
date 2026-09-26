@testable import XTools
import Foundation
import Testing
import XToolsCore

/// 大规模提示信息语料审计。
///
/// 目标：把尽可能多、尽可能全的测试数据喂进每个工具的真实诊断路径，
/// 收集用户实际会看到的文案，然后：
///   1. 用 `ToolDiagnosticContract` 做客观校验（长度/单段/禁用片段/回显/行列泄漏）；
///   2. 把全部观测打印成报告，供人工核对语义质量（是否说明原因、是否有引导）。
///
/// 这里只对「客观契约」断言；语义问题只在报告中呈现，由产品决策单独处理。
struct DiagnosticMessageCorpusAuditTests {

    // MARK: - 观测账本

    struct Observation: Sendable {
        let tool: String
        let channel: String
        let rawInputs: [String]
        let displayInput: String
        let message: String
        let suggestion: String?
        let position: String
    }

    final class Ledger: @unchecked Sendable {
        private let lock = NSLock()
        private var rows: [Observation] = []

        func append(_ row: Observation) {
            lock.lock()
            rows.append(row)
            lock.unlock()
        }

        func snapshot() -> [Observation] {
            lock.lock()
            defer { lock.unlock() }
            return rows
        }
    }

    static func describe(_ input: String, limit: Int = 56) -> String {
        let flattened = input
            .replacingOccurrences(of: "\n", with: "⏎")
            .replacingOccurrences(of: "\t", with: "⇥")
            .replacingOccurrences(of: "\r", with: "␍")
        if flattened.count <= limit { return flattened }
        return String(flattened.prefix(limit)) + "…"
    }

    // MARK: - 采集助手

    @discardableResult
    static func collectDiagnostic(
        _ ledger: Ledger,
        tool: String,
        input: String,
        displayInput: String? = nil,
        additionalSensitiveInputs: [String] = [],
        channel: String,
        diagnostic: FormatDiagnostic
    ) -> Observation {
        let position: String
        if let line = diagnostic.line {
            position = diagnostic.column.map { "\(line):\($0)" } ?? "\(line)"
        } else {
            position = "—"
        }
        let row = Observation(
            tool: tool,
            channel: channel,
            rawInputs: [input] + additionalSensitiveInputs,
            displayInput: displayInput ?? describe(input),
            message: diagnostic.message,
            suggestion: diagnostic.suggestion,
            position: position
        )
        ledger.append(row)
        return row
    }

    @discardableResult
    static func collectMessage(
        _ ledger: Ledger,
        tool: String,
        input: String,
        displayInput: String? = nil,
        additionalSensitiveInputs: [String] = [],
        channel: String,
        message: String,
        suggestion: String? = nil,
        position: String = "—"
    ) -> Observation {
        let row = Observation(
            tool: tool,
            channel: channel,
            rawInputs: [input] + additionalSensitiveInputs,
            displayInput: displayInput ?? describe(input),
            message: message,
            suggestion: suggestion,
            position: position
        )
        ledger.append(row)
        return row
    }

    /// 运行一个会抛错的入口，记录抛出的本地化文案。
    @discardableResult
    static func collectThrowing<T>(
        _ ledger: Ledger,
        tool: String,
        input: String,
        displayInput: String? = nil,
        additionalSensitiveInputs: [String] = [],
        channel: String = "error",
        _ body: () throws -> T
    ) -> T? {
        do {
            return try body()
        } catch {
            collectMessage(
                ledger,
                tool: tool,
                input: input,
                displayInput: displayInput,
                additionalSensitiveInputs: additionalSensitiveInputs,
                channel: channel,
                message: error.localizedDescription
            )
            return nil
        }
    }

    // MARK: - 主审计

    static func verify(_ ledger: Ledger, section: String) {
        let rows = ledger.snapshot()
        print(Self.render(rows))

        let offenders = rows.flatMap { Self.violations(for: $0) }

        print("\n=== \(section) 契约违例 \(offenders.count) 条 ===")
        for offender in offenders { print(offender) }

        #expect(!rows.isEmpty, "语料审计没有采集到任何观测")
        #expect(offenders.isEmpty, Comment(rawValue: offenders.joined(separator: "\n")))
    }

    static func violations(for row: Observation) -> [String] {
        guard row.channel != "silent" else { return [] }
        // 短输入容易与正常文案用词重合；原文必须保持未裁短、未转义。
        let sensitive = row.rawInputs.filter { $0.count >= 16 }
        var offenders: [String] = []
        let messageViolations = ToolDiagnosticContract.violations(
            in: row.message,
            sensitiveInputs: sensitive
        )
        if !messageViolations.isEmpty {
            offenders.append(
                "[\(row.tool)] \(messageViolations.joined(separator: " / ")) ←「\(row.message)」"
            )
        }
        if let suggestion = row.suggestion {
            let suggestionViolations = ToolDiagnosticContract.violations(
                in: suggestion,
                sensitiveInputs: sensitive
            )
            if !suggestionViolations.isEmpty {
                offenders.append(
                    "[\(row.tool)/建议] \(suggestionViolations.joined(separator: " / ")) ←「\(suggestion)」"
                )
            }
        }
        return offenders
    }

    @Test func auditChecksUnmodifiedSensitiveInputsRatherThanReportSummaries() {
        let ledger = Ledger()
        let longInput = String(repeating: "A", count: 60)
        let longEcho = Self.collectMessage(
            ledger, tool: "long", input: longInput, channel: "error", message: "无效：\(longInput)"
        )
        #expect(longEcho.displayInput == String(repeating: "A", count: 56) + "…")
        #expect(Self.violations(for: longEcho).contains { $0.contains("诊断回显了原始或敏感输入") })

        let multilineInput = "header\nsensitive-payload-abcdefghijklmnop\nfooter"
        let lineEcho = Self.collectMessage(
            ledger, tool: "newline", input: multilineInput, channel: "error",
            message: "无效：sensitive-payload-abcdefghijklmnop"
        )
        #expect(lineEcho.displayInput.contains("⏎"))
        #expect(Self.violations(for: lineEcho).contains { $0.contains("诊断回显了原始或敏感输入") })

        let tabbedInput = "alpha-token\tbeta-secret\tgamma-value"
        let tabEcho = Self.collectMessage(
            ledger, tool: "tab", input: tabbedInput, channel: "error",
            message: "无效：alpha-token beta-secret gamma-value"
        )
        #expect(tabEcho.displayInput.contains("⇥"))
        #expect(Self.violations(for: tabEcho).contains { $0.contains("诊断回显了原始或敏感输入") })

        let safe = Self.collectMessage(
            ledger, tool: "safe", input: longInput, channel: "error", message: "输入格式无效。"
        )
        #expect(Self.violations(for: safe).isEmpty)
    }

    /// XML 诊断文案依赖 libxml 的错误码，且 `parser.parserError` 只给出笼统的
    /// 5/111，必须优先取 delegate 的细粒度错误。这里用真实语料把码值固定下来，
    /// 防止后续误改映射（码值语义见 XMLFormatting.xmlMessage 的注释）。
    @Test func xmlErrorCodesMatchTheDocumentedMapping() {
        let expectations: [(input: String, code: Int)] = [
            ("<root><1bad/></root>", 68),
            ("<root><title>Tom & Jerry</title></root>", 68),
            ("<root>&undefined;</root>", 26),
            ("<one>1</one><two>2</two>", 5),
            ("<root>", 5),
            ("plain text without tags", 4),
            ("<root attr=\"unclosed></root>", 38),
            ("<root a=1/>", 39),
            ("<root><!-- unterminated comment </root>", 45),
            ("<root><?pi unterminated</root>", 47),
            ("<root><item>one</items></root>", 76)
        ]

        for (input, expectedCode) in expectations {
            let delegate = XMLProbeDelegate()
            let parser = XMLParser(data: Data(input.utf8))
            parser.shouldResolveExternalEntities = false
            parser.delegate = delegate
            #expect(!parser.parse(), "「\(input)」应当解析失败")
            #expect((delegate.error as NSError?)?.code == expectedCode, "「\(input)」的错误码漂移")
        }
    }

    @Test func auditStructuredTextCorpus() {
        let ledger = Ledger()
        Self.auditStructuredText(ledger)
        Self.verify(ledger, section: "结构化文本")
    }

    @Test func auditEncoderCorpus() {
        let ledger = Ledger()
        Self.auditEncoders(ledger)
        Self.verify(ledger, section: "编解码")
    }

    @Test func auditDeveloperToolCorpus() {
        let ledger = Ledger()
        Self.auditDeveloperTools(ledger)
        Self.verify(ledger, section: "开发者工具")
    }

    @Test func auditWebSecurityCorpus() {
        let ledger = Ledger()
        Self.auditWebSecurity(ledger)
        Self.verify(ledger, section: "Web 与安全")
    }

    @Test func auditUtilityTimeColorCorpus() {
        let ledger = Ledger()
        Self.auditUtilityTimeColor(ledger)
        Self.verify(ledger, section: "工具与时间与颜色")
    }

    @Test func auditDiffAndDockerCorpus() {
        let ledger = Ledger()
        Self.auditDiffAndDocker(ledger)
        Self.verify(ledger, section: "对比与 Docker")
    }

    // MARK: - 报告渲染

    static func render(_ rows: [Observation]) -> String {
        var out = "\n========== 提示信息语料审计报告 ==========\n"
        out += "总观测：\(rows.count)\n"
        let grouped = Dictionary(grouping: rows, by: \.tool)
        for tool in grouped.keys.sorted() {
            guard let group = grouped[tool] else { continue }
            out += "\n----- \(tool)  (\(group.count)) -----\n"
            for row in group {
                var line = "  [\(row.channel)] 输入「\(row.displayInput)」 → 「\(row.message)」"
                if row.position != "—" { line += "  @\(row.position)" }
                if let suggestion = row.suggestion { line += "  建议:「\(suggestion)」" }
                out += line + "\n"
            }
        }
        return out
    }

    // MARK: - 结构化文本

    static func auditStructuredText(_ ledger: Ledger) {
        for input in jsonCorpus {
            let outcome = FormatRunner.run(input) {
                try JSONFormatting.formatResult($0, sortKeys: false, indentWidth: 2)
            }
            switch outcome {
            case .failed(let diagnostic):
                collectDiagnostic(ledger, tool: "json-formatter", input: input, channel: "error", diagnostic: diagnostic)
            case .produced(let result):
                if let warning = result.warning {
                    collectMessage(ledger, tool: "json-formatter", input: input, channel: "warning", message: warning)
                }
            case .empty:
                collectMessage(ledger, tool: "json-formatter", input: input, channel: "silent", message: "（空输入，无提示）")
            }
        }

        let labels = JSONDiffValidation.SideLabels(left: "JSON A", right: "JSON B")
        for pair in jsonDiffCorpus {
            let decision = JSONDiffValidation.evaluate(left: pair.0, right: pair.1, labels: labels)
            switch decision {
            case .empty:
                collectMessage(ledger, tool: "json-diff", input: pair.0,
                               displayInput: "\(Self.describe(pair.0)) | \(Self.describe(pair.1))",
                               additionalSensitiveInputs: [pair.1], channel: "silent", message: "（空态）")
            case .invalid(let message):
                collectMessage(ledger, tool: "json-diff", input: pair.0,
                               displayInput: "\(Self.describe(pair.0)) | \(Self.describe(pair.1))",
                               additionalSensitiveInputs: [pair.1], channel: "error", message: message)
            case .comparable:
                if let warning = JSONDiffValidation.comparisonWarning(left: pair.0, right: pair.1, labels: labels) {
                    collectMessage(ledger, tool: "json-diff", input: pair.0,
                                   displayInput: "\(Self.describe(pair.0)) | \(Self.describe(pair.1))",
                                   additionalSensitiveInputs: [pair.1], channel: "warning", message: warning)
                }
            }
        }

        for input in xmlCorpus {
            let outcome = FormatRunner.run(input) { try XMLFormatting.format($0) }
            if case .failed(let diagnostic) = outcome {
                collectDiagnostic(ledger, tool: "xml-formatter", input: input, channel: "error", diagnostic: diagnostic)
            }
        }

        for entry in yamlCorpus {
            do {
                _ = try YAMLPrettifier.formatValidated(entry.0, options: .init(indent: 2, sortKeys: entry.1))
            } catch let error as YAMLPrettifier.ValidationError {
                collectDiagnostic(ledger, tool: "yaml-prettify", input: entry.0, channel: "error", diagnostic: error.diagnostic)
            } catch {
                collectMessage(ledger, tool: "yaml-prettify", input: entry.0, channel: "error", message: error.localizedDescription)
            }
        }

        for input in sqlCorpus {
            let outcome = FormatRunner.run(input) { try SQLFormatting.format($0) }
            if case .failed(let diagnostic) = outcome {
                collectDiagnostic(ledger, tool: "sql-prettify", input: input, channel: "error", diagnostic: diagnostic)
            }
        }
    }

    // MARK: - 编解码

    static func auditEncoders(_ ledger: Ledger) {
        for entry in integerBaseCorpus {
            collectThrowing(ledger, tool: "integer-base-converter", input: entry.0,
                            displayInput: "\(Self.describe(entry.0)) [base \(entry.1)]") {
                try IntegerBaseConverter.validatedConversions(input: entry.0, fromBase: entry.1)
            }
        }

        for input in romanCorpus {
            collectThrowing(ledger, tool: "roman-numeral-converter", input: input) {
                try RomanNumeralConverter.validatedNumber(fromRoman: input)
            }
        }
        for input in arabicCorpus {
            collectThrowing(ledger, tool: "roman-numeral-converter", input: input) {
                try RomanNumeralConverter.validatedRoman(fromArabic: input)
            }
        }

        for input in unicodeCorpus {
            collectThrowing(ledger, tool: "text-to-unicode", input: input) {
                try UnicodeEscaping.decodeValidated(input)
            }
        }

        for input in urlCorpus {
            collectThrowing(ledger, tool: "url-encoder-decoder", input: input) {
                try URLPercentCoding.decode(input)
            }
        }

        for input in asciiToTextCorpus {
            collectThrowing(ledger, tool: "text-to-ascii-binary", input: input) {
                try ASCIIBinaryConversion.validatedASCIIToText(input)
            }
        }
        for input in binaryToTextCorpus {
            collectThrowing(ledger, tool: "text-to-ascii-binary", input: input) {
                try ASCIIBinaryConversion.validatedBinaryToText(input)
            }
        }
        for input in textToASCIICorpus {
            collectThrowing(ledger, tool: "text-to-ascii-binary", input: input) {
                try ASCIIBinaryConversion.validatedTextToASCII(input)
            }
        }

        for input in base64Corpus {
            collectThrowing(ledger, tool: "base64-string", input: input) {
                try Base64Conversion.decode(input)
            }
            collectThrowing(ledger, tool: "base64-string", input: input) {
                try Base64Conversion.parseDataURL(input)
            }
            collectThrowing(ledger, tool: "base64-string", input: input) {
                try Base64Conversion.decodeFilePayload(input)
            }
        }
    }

    // MARK: - 开发者工具

    static func auditDeveloperTools(_ ledger: Ledger) {
        for entry in regexCorpus {
            collectThrowing(ledger, tool: "regex-tester", input: entry.0) {
                try RegexMatcher.analyze(pattern: entry.0, in: entry.1, flags: entry.2)
            }
        }

        for input in mathCorpus {
            collectThrowing(ledger, tool: "math-evaluator", input: input) {
                try MathExpressionEvaluator.evaluate(input)
            }
            if case .invalid(let error) = MathExpressionEvaluator.evaluateLiveInput(input) {
                collectMessage(
                    ledger,
                    tool: "math-evaluator(实时)",
                    input: input,
                    channel: "error",
                    message: error.errorDescription ?? "（空文案）"
                )
            }
        }

        for input in chmodCorpus {
            collectThrowing(ledger, tool: "chmod-calculator", input: input) {
                try ChmodMode(octal: input)
            }
        }

        for input in cronCorpus {
            if let message = CronScheduler.validationMessage(input) {
                collectMessage(ledger, tool: "crontab-generator", input: input, channel: "error", message: message)
            }
        }

        for input in htmlToMarkdownCorpus {
            let result = HTMLToMarkdownConverter.convert(input, options: .manual)
            if let error = result.error {
                collectMessage(
                    ledger,
                    tool: "html-to-markdown",
                    input: input,
                    channel: "error",
                    message: HTMLToMarkdownDiagnostics.conversionErrorMessage(for: error)
                )
            }
            if let message = HTMLToMarkdownDiagnostics.conversionWarningMessage(for: result.warnings) {
                collectMessage(ledger, tool: "html-to-markdown", input: input, channel: "warning", message: message)
            }
        }
    }

    // MARK: - Web / 安全

    static func auditWebSecurity(_ ledger: Ledger) {
        for input in userAgentCorpus {
            if let issue = UserAgentParser.validationIssue(input) {
                collectMessage(
                    ledger,
                    tool: "useragent-parser",
                    input: input,
                    channel: "error",
                    message: issue.errorDescription ?? "（空文案）"
                )
            }
        }

        let encryptionCorpus: [(String, String, TextEncryptionService.Algorithm)] = [
            ("", "pw", .aes),
            ("   ", "pw", .aes),
            ("not-base64!!!", "pw", .aes),
            ("aGVsbG8=", "pw", .aes),
            ("aGVsbG8=", "", .aes),
            ("U2FsdGVkXXXX", "pw", .aes),
            ("aGVsbG8=", "pw", .tripleDES),
            ("aGVsbG8=", "wrongpass", .aes),
            (String(repeating: "A", count: 100_000), "pw", .aes)
        ]
        for entry in encryptionCorpus {
            collectThrowing(ledger, tool: "text-encryption(解密)", input: entry.0) {
                try TextEncryptionService.decrypt(entry.0, password: entry.1, algorithm: entry.2)
            }
        }

        // 算法与密文格式错配：用只带格式签名的静态样本触发前缀/头检测，
        // 避免每次审计都跑真实的 PBKDF2 加密。
        let algorithmMismatchCorpus: [(String, TextEncryptionService.Algorithm)] = [
            ("DT-AES-GCM-v1:QUFBQUFBQUFBQUFB", .aes),
            (Data("Salted__".utf8 + [UInt8](repeating: 0, count: 16)).base64EncodedString(), .aesGCM)
        ]
        for entry in algorithmMismatchCorpus {
            collectThrowing(ledger, tool: "text-encryption(解密)", input: entry.0,
                            displayInput: "格式错配样本[\(entry.1.rawValue)]") {
                try TextEncryptionService.decrypt(entry.0, password: "pw", algorithm: entry.1)
            }
        }

        for entry in basicAuthCorpus {
            var session = BasicAuthWorkspaceSession(mode: .parse, parseInput: entry)
            session.parse()
            if let error = session.parseError, !error.isEmpty {
                collectMessage(ledger, tool: "basic-auth-generator", input: entry, channel: "error", message: error)
            }
        }

        // 走会话层而非直调 JWTParser：parseError 是页面实际显示的字段，
        // 这样 core 文案与会话层硬编码漂移（core 已改、UI 停旧版）会被语料直接拦下。
        for input in jwtCorpus {
            var session = JWTWorkspaceSession()
            session.parseInput = input
            session.parse()
            if let error = session.parseError, !error.isEmpty {
                collectMessage(ledger, tool: "jwt-parser", input: input, channel: "error", message: error)
            }
        }
    }

    // MARK: - 工具 / 时间 / 颜色

    static func auditUtilityTimeColor(_ ledger: Ledger) {
        for input in timestampCorpus {
            if case .invalid(let issue) = TimestampInterpreter.evaluate(input) {
                collectMessage(
                    ledger,
                    tool: "date-time-converter",
                    input: input,
                    channel: "error",
                    message: issue.errorDescription ?? "（空文案）"
                )
            }
        }

        for input in cssColorCorpus {
            let result = CSSColorParser.classify(input)
            if let diagnostic = result.diagnostic {
                collectMessage(ledger, tool: "color-picker(CSS)", input: input, channel: "error", message: diagnostic.message)
            }
        }

        for input in homeContentCorpus {
            for action in HomeContentAction.allCases {
                switch HomeContentProcessor.run(action, input: input) {
                case .success(let result):
                    if let warning = result.warning {
                        collectMessage(ledger, tool: "quick-process", input: input, channel: "warning", message: warning)
                    }
                case .failure(let failure):
                    collectMessage(
                        ledger,
                        tool: "quick-process",
                        input: input,
                        displayInput: "\(action.rawValue)｜\(Self.describe(input))",
                        channel: "error",
                        message: failure.message
                    )
                }
            }
        }

        for entry in fileTypeCorpus {
            let report = FileTypeDetector.inspect(fileName: entry.0, byteCount: entry.1, leadingData: entry.2)
            if let message = report.conflictDiagnostic {
                collectMessage(ledger, tool: "file-type-detector", input: entry.0, channel: "warning", message: message)
            }
        }
    }

    // MARK: - 对比 / Docker

    static func auditDiffAndDocker(_ ledger: Ledger) {
        for entry in textDiffCorpus {
            collectThrowing(ledger, tool: "text-diff", input: entry.1,
                            additionalSensitiveInputs: [entry.0]) {
                try LineDiffer.safeAlignedDiff(left: entry.0, right: entry.1)
            }
        }

        let budget = LineDiffBudget.standard
        collectThrowing(ledger, tool: "text-diff(预算)", input: "> 行数上限") {
            try budget.validate(
                leftLineCount: budget.maximumInputLinesPerSide + 1,
                rightLineCount: budget.maximumInputLinesPerSide + 1
            )
        }

        for input in dockerRunCorpus {
            collectThrowing(ledger, tool: "docker-run→compose", input: input) {
                try DockerRunToDockerComposeService.convert(input)
            }
        }

        for input in dockerComposeCorpus {
            do {
                let result = try DockerComposeToRunService.convert(input)
                if let warningText = DockerComposeToRunDiagnostics.warningMessage(for: result.warnings) {
                    collectMessage(
                        ledger,
                        tool: "docker-compose→run",
                        input: input,
                        channel: "warning",
                        message: warningText
                    )
                }
            } catch let error as DockerComposeToRunError {
                let diagnostic = DockerComposeToRunDiagnostics.diagnostic(for: error)
                collectDiagnostic(ledger, tool: "docker-compose→run", input: input, channel: "error", diagnostic: diagnostic)
            } catch {
                collectMessage(ledger, tool: "docker-compose→run", input: input, channel: "error", message: error.localizedDescription)
            }
        }
    }

    // MARK: - 语料

    static let jsonCorpus: [String] = [
        "", "   ", "\n\t  \n",
        "{}", "[]", "null", "true", "false", "0",
        #"{"a":1}"#,
        #"{"a":1,"b":[1,2,{"c":null}],"d":true,"e":"x"}"#,
        #"{"unicode":"\u4e2d\u6587"}"#,
        #"{"emoji":"😀🎉"}"#,
        #"{"big":123456789012345678901234567890}"#,
        #"{"neg":-1.5e-10}"#,
        #"{"exp":2E+8}"#,
        #"{"a":1,}"#,
        #"[1,2,]"#,
        #"{id:1}"#,
        #"{'a':1}"#,
        #"{"a":1}extra"#,
        #"{"a":1}{"b":2}"#,
        #"{"a":1"#,
        #"[1,2"#,
        #"{"a":}"#,
        #"{"a" 1}"#,
        #"{"a":01}"#,
        #"{"a":+1}"#,
        #"{"a":0x10}"#,
        #"{"a":NaN}"#,
        #"{"a":Infinity}"#,
        #"{"a":-Infinity}"#,
        #"{"a":.5}"#,
        #"{"a":1.}"#,
        #"{"a":１２}"#,
        #"{"a":1.٢}"#,
        #"{"s":"\uZZZZ"}"#,
        #"{"s":"\uDE00"}"#,
        #"{"s":"\uD83D"}"#,
        "{\"s\":\"first line\nsecond line\"}",
        "{\n  // comment\n  \"value\": 1\n}",
        #"{"a":1,"a":2}"#,
        #"{"a":1,"a":2,"b":{"c":3,"c":4}}"#,
        "}",
        "]",
        #"{"a":1}}"#,
        #"{"a":1,,}"#,
        #"{"":1}"#,
        #"{"a":"\u0000"}"#,
        #"{"secret":"AKIAIOSFODNN7EXAMPLE","token":"sk-live-9f8e7d6c5b4a3210"}"#,
        String(repeating: "[", count: 40) + String(repeating: "]", count: 40),
        "{" + (0..<40).map { "\"k\($0)\":" }.joined() + "1" + String(repeating: "}", count: 40),
        #"{"a":1..2}"#,
        #"[1 2]"#,
        #""unterminated"#,
        #"tru"#,
        #"nul"#,
        #"{"a":"b\x41"}"#,
        #"[-]"#,
        #"{"a"}"#,
        #"{"a":trailing}"#
    ]

    static let jsonDiffCorpus: [(String, String)] = [
        (#"{"a":1}"#, #"{"a":1}"#),
        (#"{"a":1}"#, #"{"a":2}"#),
        (#"{"a":1}"#, #"{"a":1,"b":2}"#),
        (#"{"a":1,}"#, #"{"a":1}"#),
        (#"{"a":1"#, #"{"a":1}"#),
        (#"{"a":1"#, #"{"b":2"#),
        (#"{"a":1,"a":2}"#, #"{"a":1}"#),
        (#"{"a":1,"a":2}"#, #"{"a":1,"a":3}"#),
        ("", ""),
        ("   ", "\n")
    ]

    static let xmlCorpus: [String] = [
        "", "   ",
        #"<root><a>1</a></root>"#,
        #"<?xml version="1.0" encoding="UTF-8"?><root><a>1</a></root>"#,
        #"<root><a>1</root>"#,
        #"<root>"#,
        #"<root></root>"#,
        "plain text without tags",
        #"<root a=1/>"#,
        #"<root>&undefined;</root>"#,
        #"<root><a/><b/></root>"#,
        #"<root><1bad/></root>"#,
        #"<root attr="unclosed></root>"#,
        #"<a><b><c>"#,
        #"<root><!-- unterminated comment </root>"#,
        #"<root><![CDATA[unterminated</root>"#,
        #"<root>text</root>trailing"#,
        #"<root a="1" a="2"/>"#,
        #"<root><?pi unterminated</root>"#,
        #"<root><![CDATA[ok]]></root>"#,
        #"< root/>"#,
        #"<root></roots >"#,
        "<root>" + String(repeating: "<n>", count: 60) + String(repeating: "</n>", count: 60) + "</root>"
    ]

    static let yamlCorpus: [(String, Bool)] = [
        ("", false), ("   ", false),
        ("a: 1", false),
        ("a: 1\nb: 2", false),
        ("- 1\n- 2", false),
        ("a:\n  b: 1\n  c: 2", false),
        ("a: 1\n\tb: 2", false),
        ("a:\n\tb: 1", false),
        ("a: 1\n  b: 2", false),
        ("key: \"unclosed", false),
        ("key1: 1\nkey2: 2\nkey1: 3", false),
        ("key: value\n---\nkey2: value2", false),
        ("a: 1 # comment\nb: 2", true),
        ("# lead\na: 1\nb: 2", true),
        ("a: 1\nb: 2", true),
        ("{a: 1}", false),
        ("a: [1, 2", false),
        ("a: 1\nb", false),
        ("a: *undefined_anchor", false),
        ("a: &anchor 1\nb: *anchor", false),
        ("a: !!int notanint", false),
        ("- name: x\n  ports:\n    - '8080:80'", false),
        ("\ta: 1", false),
        ("a:\n  b: 1\n c: 2", false),
        ("{a: 1", false),
        ("a: 1\n\tb: 2", false),
        ("a: 'unclosed", false)
    ]

    static let sqlCorpus: [String] = [
        "", "   ",
        "select 1",
        "select id, name from users where active = 1 order by id;",
        "with a as (select 1) select * from a;",
        "begin; insert into t(x) values (1); commit;",
        "select",
        "from t",
        "select * from",
        "select (1",
        "select 1)",
        "select id, name from users where email = 'alice@example.com;",
        "select * from t order by",
        "select * from t where x = [unclosed",
        "select /* unterminated",
        "select $$ unterminated dollar quote",
        "select `unclosed backtick",
        "order by 1",
        "select * from t where x = 1 and order by 1",
        "insert into",
        "select 1 -- trailing comment",
        "select 'quote''escaped' from t",
        "select 1; select 2",
        "select * from t where a = -1",
        "select $tag$ broken dollar quote",
        "update t set",
        "delete from"
    ]

    static let integerBaseCorpus: [(String, Int)] = [
        ("", 10), ("   ", 10), ("+", 10), ("-", 10),
        ("0", 10), ("42", 10), ("-42", 10), ("+42", 10),
        ("00042", 10), ("-0", 10),
        ("7fffffff", 16), ("FFFFFFFFFFFFFFFF", 16), ("0x10", 16),
        ("777", 8), ("1010", 2), ("102", 2), ("8", 8),
        ("abc", 10), ("12.5", 10), ("1 2", 10), ("１０", 10),
        ("3", 3), ("42", 7),
        (String(repeating: "1", count: 4_096), 2),
        (String(repeating: "1", count: 4_097), 2),
        (String(repeating: "9", count: 4_097), 10),
        ("🙂", 10)
    ]

    static let romanCorpus: [String] = [
        "", "   ", "I", "IV", "MCMXCIV", "MMMCMXCIX",
        "IIII", "VV", "XXXX", "IC", "IL", "abc", "Ⅳ", "MMMM", "i"
    ]

    static let arabicCorpus: [String] = [
        "", "   ", "1", "3999", "4000", "0", "-1", "1.5", "abc", "１２", " 12 ", "0001"
    ]

    static let unicodeCorpus: [String] = [
        "", "plain", #"\u0041"#, #"\u4e2d"#,
        #"\uZZZZ"#, #"\u12"#, #"\u"#, #"\"#,
        #"\uD83D"#, #"\uDE00"#, #"\uD83D\uDE00"#,
        #"a\u4e2db"#, #"\U0041"#, #"\u0041extra"#
    ]

    static let urlCorpus: [String] = [
        "", "plain", "a%20b", "%", "%2", "%ZZ", "%GG",
        "%E4%B8%AD", "%FF", "%C3%28", "%F0%9F%98%80",
        "100%", "a%2Bb", "%25",
        "%E4%B8", "%E4%B8%AD%E6", "%%", "%-1"
    ]

    static let asciiToTextCorpus: [String] = [
        "", "   ", "65 66 67", "65,66,67", "0", "127", "128", "256", "-1",
        "65.5", "abc", "65 66 6", "６５", "65\t66\n67"
    ]

    static let binaryToTextCorpus: [String] = [
        "", "   ", "01000001", "01000001 01000010", "0100000", "010000011",
        "0100002", "1", "11111111", "11000000", "11000000 10000000"
    ]

    static let textToASCIICorpus: [String] = [
        "", "abc", "中文", "😀", "a\tb", "é"
    ]

    static let base64Corpus: [String] = [
        "", "   ", "aGVsbG8=", "aGVsbG8", "!!!!",
        "a", "ab", "abc", "abcd", "=====",
        "data:text/plain;base64,aGVsbG8=",
        "data:text/plain;base64,",
        "data:base64,aGVsbG8=",
        "data:text/plain,aGVsbG8=",
        "data:;base64,aGVsbG8=",
        "data:image/png;base64,iVBORw0KGgo=",
        "////", "8J+YgA==", "😀",
        "AKIAIOSFODNN7EXAMPLE",
        "aG VsbG8=", "YW Jj", "YWJ j", "====", "=AAA",
        "aGVsbG8==", "aGVsbG8x="
    ]

    static let regexCorpus: [(String, String, String)] = [
        ("", "abc", "g"),
        ("", "", "g"),
        (#"\d+"#, "a1b2", "g"),
        ("(", "", "g"),
        ("[", "", "g"),
        ("*", "", "g"),
        ("+", "", "g"),
        ("?", "", "g"),
        ("a{", "", "g"),
        ("{", "", "g"),
        ("a{1", "", "g"),
        ("a{1,", "", "g"),
        ("a{,5}", "", "g"),
        ("a{5,2}", "", "g"),
        ("[z-a]", "", "g"),
        ("\\", "", "g"),
        (#"(?<=a+)b"#, "ab", "g"),
        (#"(?<!a+)b"#, "ab", "g"),
        ("a)", "", "g"),
        (#"\d"#, "1", "q"),
        (#"\d"#, "1", "gi"),
        (#"\d"#, "1", "gimsxq"),
        (#"(a)(b)(c)"#, "abc", "g"),
        (#"(?P<name>a)"#, "a", "g"),
        (#"a*"#, "", "g"),
        (#"(?i)abc"#, "ABC", "g"),
        ("[" + String(repeating: "a", count: 300) + "]", "a", "g"),
        (String(repeating: "a", count: 20_000), "a", "g"),
        ("a{1000000}", "a", "g"),
        ("(a", "a", "g"),
        ("a{2,1}b", "a", "g"),
        (#"\p{Greek}"#, "α", "g"),
        (#"(?<name>a)"#, "a", "g")
    ]

    static let mathCorpus: [String] = [
        "", "   ", "1+1", "2*3", "(1+2)*3", "1/0", "0/0", "2^", "^2",
        "1++2", "1**2", "sqrt(-1)", "log(0)", "log(-1)", "asin(2)", "acos(2)",
        "ln(0)", "1e999", "-1e999", "1e308*10", "0.1+0.2", "10%3", "10%0",
        "(1+2", "1+2)", "foo(1)", "sin()", "sin(1,2)", "pi", "PI", "e",
        "1,2", "1 2", "abc", "1e", "1.", ".5", "1/3", "-0", "2^0.5",
        "pow(2,10)", "max(1,2,3)", "1+", "1-", "*2", "/2", "()", "()()"
    ]

    static let chmodCorpus: [String] = [
        "", " ", "7", "777", "0777", "7777", "77777", "888", "789",
        "abc", "77a", "-777", "0", "000", "9999", "１２３"
    ]

    static let cronCorpus: [String] = [
        "", "   ", "* * * * *", "0 0 * * *", "*/5 * * * *", "0 0 1 1 *",
        "@daily", "@reboot", "@yearly", "@unknown", "@private-token12",
        "* * * *", "* * * * * *", "60 * * * *", "* 24 * * *",
        "*/0 * * * *", "*/-1 * * * *", "1-5 * * * *", "1-5/2 * * * *",
        "abc * * * *", "* * abc * *", "5-1 * * * *", "1,2,3 * * * *",
        "0 0 30 2 *", "0 0 31 4 *", "0 0 29 2 *",
        "60-70 * * * *", "1,2, * * * *", "*/60 * * * *",
        "* * * * 7", "* * * * MON", "5--7 * * * *", "* * 0 * *"
    ]

    static let htmlToMarkdownCorpus: [String] = [
        "",
        "<p>hello</p>",
        "<div><script>alert(1)</script>text</div>",
        "<table><tr><td colspan=\"2\">a</td></tr></table>",
        "<custom-element>x</custom-element>",
        "<iframe src=\"https://evil.example\"></iframe>",
        "<body></body>",
        "<style>.a{color:red}</style>",
        "<p>" + String(repeating: "a", count: 5_000_000) + "</p>"
    ]

    static let userAgentCorpus: [String] = [
        "",
        "   ",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "curl/7.68.0",
        "hello",
        "Mozilla//5.0",
        "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)",
        "\u{0007}Mozilla/5.0",
        "Mozilla/5.0\u{0000}X",
        String(repeating: "Mozilla/5.0 ", count: 2_000)
    ]

    static let basicAuthCorpus: [String] = [
        "", "   ", "hello", "Basic", "Basic ", "Basic aGVsbG8=", "Basic !!!!",
        "Bearer aGVsbG8=", "aGVsbG8=", "Basic dXNlcjpwYXNz", "Basic dXNlcg==",
        "basic dXNlcjpwYXNz", "Basic dXNlcjpwYXNz:extra",
        "Basic " + String(repeating: "A", count: 20_000)
    ]

    static let jwtCorpus: [String] = [
        "", "   ", "abc", "a.b", "a.b.c", "a.b.c.d",
        "....", "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0",
        "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.",
        "!!!.!!!.!!!",
        "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.sig",
        "eyJhbGciOiJIUzI1NiJ9.eyJleHAiOiJub3QifQ.sig",
        "eyJhbGciOiJIUzI1NiJ9..sig",
        ".eyJzdWIiOiIxIn0.sig",
        "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.sig.extra",
        "...."
    ]

    static let timestampCorpus: [String] = [
        "", "   ", "-", "0", "1", "-1", "1700000000", "-62135596800",
        "-62135596801", "253402300799", "253402300800",
        "1.5", "abc", "1e5", " 1700000000 ", "１２３", "+1700000000",
        String(repeating: "9", count: 40)
    ]

    static let cssColorCorpus: [String] = [
        "", "  ", "#fff", "#ffffff", "#ffffffff", "#gggggg", "#12345",
        "rgb(1,2,3)", "rgb(1,2)", "rgb(1,2,3,4)", "rgb(300,0,0)",
        "rgba(1,2,3,0.5)", "rgba(1,2,3,2)", "hsl(120,50%,50%)",
        "hsl(400,50%,50%)", "hsl(120,50%)", "red", "notacolor",
        "transparent", "color(srgb 1 0 0)", "oklch(0.5 0.1 200)",
        "lab(50% 0 0)", "color-mix(in srgb, red, blue)", "rgb(",
        "device-cmyk(0 0 0 1)"
    ]

    static let homeContentCorpus: [String] = [
        "", "   ", #"{"a":1}"#, #"{"a":1"#, "aGVsbG8=", "hello%20world",
        "plain text", String(repeating: "a", count: 200_000),
        "{" + String(repeating: "{\"a\":", count: 40) + "1" + String(repeating: "}", count: 40),
        #"{"secret":"AKIAIOSFODNN7EXAMPLE"}"#,
        "%ZZ%FF", "%E4%B8"
    ]

    static let fileTypeCorpus: [(String, Int64?, Data?)] = [
        ("empty.dat", 0, Data()),
        ("empty.txt", 0, Data()),
        ("photo.png", 1024, Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])),
        ("photo.txt", 1024, Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])),
        ("archive.zip", 2048, Data([0x50, 0x4B, 0x03, 0x04])),
        ("noext", 10, Data([0x00, 0x01, 0x02, 0x03])),
        ("weird.zzz", 10, Data([0x00, 0x01, 0x02, 0x03])),
        ("binary.bin", 10, Data([0x00, 0x01, 0x02, 0x03])),
        ("missing.dat", nil, nil),
        ("norights.txt", 100, nil)
    ]

    static let textDiffCorpus: [(String, String)] = [
        ("", ""), ("a", "a"), ("a", "b"), ("a\nb", "a\nc"),
        ("a\nb\nc", "c\nb\na"), ("line", "line\n"),
        (String(repeating: "x\n", count: 5_000), String(repeating: "y\n", count: 5_000)),
        (String(repeating: "same\n", count: 300_000), String(repeating: "same\n", count: 300_000))
    ]

    static let dockerRunCorpus: [String] = [
        "", "   ", "docker", "docker run", "docker run -d nginx",
        "docker run nginx", "docker run -d -p 8080:80 --name web nginx:latest",
        "docker run -d --name x -e A=1 -e B=2 -v /a:/b nginx",
        "docker ps -a", "docker run -d nginx; docker run -d redis",
        "docker run -d nginx && echo done",
        "docker run --unknown-flag nginx",
        "docker run -d",
        "docker run -d --name",
        "docker run -d --name \"unclosed",
        "docker run -d --restart=always nginx",
        "docker run -d --memory=512m --cpus=1.5 nginx",
        "docker run --rm -it ubuntu bash",
        "docker run " + String(repeating: "-e A=1 ", count: 500) + "nginx",
        "docker run --network=host --pid=host nginx",
        "docker run --name=web nginx",
        "docker exec -it web sh",
        "docker run -p",
        "docker  run   nginx",
        "docker run --entrypoint /bin/sh alpine -c 'echo hi'"
    ]

    static let dockerComposeCorpus: [String] = [        "", "   ", "not: yaml: [", "[1,2,3]", "a: 1",
        "services: {}",
        "services:\n  web:\n    image: nginx",
        "services:\n  web:\n    image: nginx\n    ports:\n      - \"80:80\"",
        "services:\n  web:\n    build: .\n    image: nginx",
        "services:\n  web:\n    image: nginx\n    depends_on:\n      - db",
        "services:\n  web:\n    image: nginx\n    deploy:\n      resources:\n        limits:\n          cpus: \"0.5\"",
        "services:\n  web:\n    image: nginx\n    network_mode: bridge\n    networks:\n      - frontend",
        "services:\n  web:\n    image: nginx\n    environment:\n      - A=1\n      - B=2",
        "services:\n  web:\n    image: nginx\n    volumes:\n      - ./a:/b:ro\n      - vol:/data",
        "services:\n  web:\n    image: nginx\n    healthcheck:\n      test: [\"CMD\", \"curl\", \"-f\", \"http://localhost\"]",
        "services:\n  web:\n    image: nginx\n    sysctls:\n      net.core.somaxconn: 1024\n    ulimits:\n      nofile: 65535",
        "services:\n  a:\n    image: nginx\n  b:\n    image: redis\n    depends_on:\n      - a",
        "services:\n\tweb:\n\t\timage: nginx",
        "services: 1",
        "services:\n  web: image: nginx",
        "services:\n  web:\n    image: nginx\n    ports:\n      - '80",
        "services:\n  app:\n    image: nginx\n" + (1...20).map { "    unmapped_compose_field_\(String(format: "%02d", $0)): 1" }.joined(separator: "\n"),
        "services:\n" + ["alpha", "beta", "gamma"].map { name in
            "  \(name):\n    image: nginx\n    depends_on: [db]\n    build: .\n    profiles: [p]"
        }.joined(separator: "\n")
    ]
}

/// 探查用：捕获 `XMLParserDelegate` 上报的细粒度解析错误。
final class XMLProbeDelegate: NSObject, XMLParserDelegate {
    var error: Error?

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        error = parseError
    }
}
