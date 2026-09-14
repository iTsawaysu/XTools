import XToolsCore
import Testing

struct FormatRunnerTests {
    // 空输入：去除首尾空白后为空则返回 .empty，且不调用 produce。
    @Test func emptyInputReturnsEmptyWithoutProducing() {
        var produceCalled = false
        let outcome = FormatRunner.run("   \n\t ") { (value: String) -> String in
            produceCalled = true
            return value
        }

        #expect(outcome == .empty)
        #expect(produceCalled == false)
    }

    @Test func nonEmptyInputRunsProduce() {
        let outcome = FormatRunner.run("hello") { $0.uppercased() }
        #expect(outcome == .produced("HELLO"))
    }

    // 携带诊断的错误：runner 保留完整 FormatDiagnostic（位置/摘录/内部建议），而非仅字符串。
    @Test func diagnosticProvidingErrorIsPreservedInFull() {
        let expected = FormatDiagnostic(
            formatName: "JSON",
            message: "意外的字符",
            line: 3,
            column: 7,
            excerpt: "  \"a\": ,",
            suggestion: "补全缺失的值。"
        )

        let outcome: FormatOutcome<String> = FormatRunner.run("{bad}") { _ in
            throw JSONFormatting.FormattingError.invalidJSON(expected)
        }

        #expect(outcome == .failed(expected))
    }

    // 非诊断错误：回退为通用中文诊断，不崩溃，也不透传底层英文异常。
    @Test func nonDiagnosticErrorFallsBackToMessageOnly() {
        struct Bare: Error {}
        let outcome: FormatOutcome<String> = FormatRunner.run("x") { _ in throw Bare() }

        guard case .failed(let diagnostic) = outcome else {
            Issue.record("期望 .failed，实际为 \(outcome)")
            return
        }
        #expect(diagnostic.line == nil)
        #expect(diagnostic.message == "格式化失败，输入内容无法解析")
        #expect(!diagnostic.localizedDescription.contains("The operation"))
        #expect(!diagnostic.localizedDescription.contains("Error Domain"))
        #expect(!diagnostic.localizedDescription.contains("NSXMLParserErrorDomain"))
    }

    // 四个格式化器错误类型都遵从 FormatDiagnosticProviding，能被 runner 统一捕获。
    @Test func allFormatterErrorsFlowThroughRunner() {
        let diag = FormatDiagnostic(formatName: "X", message: "boom")

        let jsonOutcome: FormatOutcome<String> = FormatRunner.run("a") { _ in
            throw JSONFormatting.FormattingError.invalidJSON(diag)
        }
        let xmlOutcome: FormatOutcome<String> = FormatRunner.run("a") { _ in
            throw XMLFormatting.FormattingError.invalidXML(diag)
        }
        let yamlOutcome: FormatOutcome<String> = FormatRunner.run("a") { _ in
            throw YAMLPrettifier.ValidationError.invalidSyntax(diag)
        }
        let sqlOutcome: FormatOutcome<String> = FormatRunner.run("a") { _ in
            throw SQLFormatting.ValidationError.missingStatementKeyword(diag)
        }

        #expect(jsonOutcome == .failed(diag))
        #expect(xmlOutcome == .failed(diag))
        #expect(yamlOutcome == .failed(diag))
        #expect(sqlOutcome == .failed(diag))
    }

    @Test func formatterFailureMessagesStayLocalizedAndShort() {
        let outcomes: [(format: String, outcome: FormatOutcome<String>)] = [
            (
                "JSON",
                FormatRunner.run(#"{"json": "test", "a": b }"#) {
                    try JSONFormatting.format($0, sortKeys: false, indentWidth: 2)
                }
            ),
            (
                "XML",
                FormatRunner.run("<root><item id=1 /></root>") {
                    try XMLFormatting.format($0)
                }
            ),
            (
                "YAML",
                FormatRunner.run("services:\n  web: [nginx") {
                    try YAMLPrettifier.formatValidated($0)
                }
            ),
            (
                "SQL",
                FormatRunner.run("foo") {
                    try SQLFormatting.format($0)
                }
            )
        ]

        for item in outcomes {
            guard case .failed(let diagnostic) = item.outcome else {
                Issue.record("Expected \(item.format) to fail")
                continue
            }

            let message = diagnostic.localizedDescription
            #expect(!message.contains("\n"))
            #expect(!message.contains("did not"))
            #expect(!message.contains("could not"))
            #expect(!message.contains("expected"))
            #expect(!message.contains("Unexpected"))
            #expect(!message.contains("NSXMLParserErrorDomain"))
            #expect(!message.contains("The operation"))
            #expect(!message.contains("Error Domain"))
            #expect(!message.contains("YamlError"))
        }
    }

    // 端到端：真实非法 JSON 经 runner 得到 .failed，且诊断带 formatName。
    @Test func realInvalidJSONProducesFailure() {
        let outcome = FormatRunner.run("{ \"a\": }") { input in
            try JSONFormatting.format(input, sortKeys: false, indentWidth: 2)
        }

        guard case .failed(let diagnostic) = outcome else {
            Issue.record("期望 .failed，实际为 \(outcome)")
            return
        }
        #expect(diagnostic.formatName == "JSON")
    }

    // MARK: - FormatBinding 归约（页面状态三元组）

    // 空输入归约：输出、错误、警告全部清空（对齐现网 .empty 分支）。
    @Test func bindingEmptyClearsOutputErrorAndWarning() {
        let outcome: FormatOutcome<String> = .empty
        let binding = outcome.binding(text: { $0 })

        #expect(binding == FormatBinding(output: "", error: nil, warning: nil))
    }

    // 成功归约（无 warning 页）：写输出、清错误、无警告（对齐 XML/YAML/SQL）。
    @Test func bindingProducedWritesOutputAndClearsErrorWithoutWarning() {
        let outcome: FormatOutcome<String> = .produced("FORMATTED")
        let binding = outcome.binding(text: { $0 })

        #expect(binding.output == "FORMATTED")
        #expect(binding.error == nil)
        #expect(binding.warning == nil)
    }

    // 成功归约（带 warning 页）：warning 闭包取到产出值的可选警告（对齐 JSON）。
    @Test func bindingProducedCarriesWarningWhenProvided() {
        struct Result: Equatable { let text: String; let warning: String? }
        let outcome: FormatOutcome<Result> = .produced(Result(text: "OUT", warning: "键顺序已保留"))
        let binding = outcome.binding(text: { $0.text }, warning: { $0.warning })

        #expect(binding.output == "OUT")
        #expect(binding.error == nil)
        #expect(binding.warning == "键顺序已保留")
    }

    // 成功归约：产出值 warning 为 nil 时，归约后 warning 也为 nil。
    @Test func bindingProducedWithNilWarningStaysNil() {
        struct Result: Equatable { let text: String; let warning: String? }
        let outcome: FormatOutcome<Result> = .produced(Result(text: "OUT", warning: nil))
        let binding = outcome.binding(text: { $0.text }, warning: { $0.warning })

        #expect(binding.warning == nil)
    }

    // 失败归约：写工作区诊断文案到 error，清空 output 与 warning。
    @Test func bindingFailedWritesWorkspaceMessageAndClearsOutputAndWarning() {
        let diagnostic = FormatDiagnostic(
            formatName: "JSON",
            message: "意外的字符",
            line: 2,
            column: 5,
            suggestion: "把当前位置改成合法的 JSON 值。"
        )
        let outcome: FormatOutcome<String> = .failed(diagnostic)
        let binding = outcome.binding(text: { $0 })

        #expect(binding.output == "")
        #expect(binding.error == diagnostic.workspaceMessage)
        #expect(binding.error?.contains("处理方式：") == false)
        #expect(binding.error?.contains("把当前位置改成合法的 JSON 值") == false)
        #expect(binding.error == "意外的字符")
        #expect(binding.error == diagnostic.displayMessage)
        #expect(binding.warning == nil)
    }

    @Test func workspaceMessageUsesOnlyTheFactualMessage() {
        let diagnostic = FormatDiagnostic(formatName: "JSON", message: "对象末尾多了逗号", line: 1, column: 19)

        #expect(diagnostic.displayMessage == "对象末尾多了逗号")
        #expect(diagnostic.workspaceMessage == "对象末尾多了逗号")
        #expect(diagnostic.line == 1)
        #expect(diagnostic.column == 19)
    }
}
