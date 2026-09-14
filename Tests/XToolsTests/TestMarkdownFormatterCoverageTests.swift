import XToolsCore
import Testing

struct TestMarkdownFormatterCoverageTests {
    @Test(arguments: [
        "JSON-FMT-01", "JSON-FMT-02", "JSON-FMT-03", "JSON-FMT-04", "JSON-FMT-05",
        "JSON-FMT-06", "JSON-FMT-07", "JSON-FMT-08", "JSON-FMT-09", "JSON-FMT-10",
        "JSON-FMT-11", "JSON-FMT-12", "JSON-FMT-13", "JSON-FMT-14", "JSON-FMT-15",
        "JSON-FMT-16", "JSON-FMT-17", "JSON-FMT-18", "JSON-FMT-19", "JSON-FMT-20"
    ])
    func jsonFormatterCase(_ id: String) throws {
        let testCase = try TestMarkdownCaseSupport.testCase(id)

        switch id {
        case "JSON-FMT-01":
            let output = try JSONFormatting.format(try block(testCase, 0), sortKeys: false, indentWidth: 2)
            #expect(output.contains(#""id": 1"#))
            #expect(output.contains(#""active": true"#))
            #expect(output.contains(#""meta": null"#))
        case "JSON-FMT-02":
            let output = try JSONFormatting.format(try block(testCase, 0), sortKeys: false, indentWidth: 2)
            #expect(output.contains("开发者工具箱"))
            #expect(output.contains("emoji 🙂"))
            #expect(output.contains(#""value": {}"#))
            #expect(output.contains(#""value": []"#))
        case "JSON-FMT-03":
            let output = try JSONFormatting.format(try block(testCase, 0), sortKeys: false, indentWidth: 2)
            #expect(output.hasPrefix("[\n"))
            #expect(output.contains(#""score": -42"#))
        case "JSON-FMT-04":
            let diagnostic = try jsonDiagnostic(try block(testCase, 0))
            #expect(diagnostic.message == "对象末尾多了逗号")
            assertFactual(diagnostic)
        case "JSON-FMT-05":
            #expect(try jsonDiagnostic(try block(testCase, 0)).message.contains("对象键必须使用双引号"))
            #expect(try jsonDiagnostic(try block(testCase, 1)).message.contains("双引号"))
        case "JSON-FMT-06":
            #expect(try jsonDiagnostic(try block(testCase, 0)).message == "JSON 不支持注释")
            #expect(try jsonDiagnostic(try block(testCase, 1)).message == "JSON 不支持 NaN")
        case "JSON-FMT-07":
            #expect(try jsonDiagnostic(try block(testCase, 0)).message.contains("没有完整闭合"))
        case "JSON-FMT-08":
            let result = try JSONFormatting.formatResult(try block(testCase, 0), sortKeys: false, indentWidth: 2)
            #expect(result.warning?.contains("重复 key") == true)
            #expect(result.text.components(separatedBy: #""name":"#).count == 3)
        case "JSON-FMT-09":
            let expected = ["{}", "[]", #""just a string""#, "-123.45e+6", "true", "false", "null"]
            for (index, expectedOutput) in expected.enumerated() {
                #expect(try JSONFormatting.minify(try block(testCase, index)) == expectedOutput)
            }
        case "JSON-FMT-10":
            let input = try block(testCase, 0)
            let preserved = try JSONFormatting.format(input, sortKeys: false, indentWidth: 2)
            let sorted = try JSONFormatting.format(input, sortKeys: true, indentWidth: 4)
            let minified = try JSONFormatting.minify(input)
            #expect(preserved.firstIndex(of: "z")! < preserved.firstIndex(of: "a")!)
            #expect(sorted.firstIndex(of: "a")! < sorted.firstIndex(of: "m")!)
            #expect(sorted.contains("    \"a\""))
            #expect(!minified.contains("\n"))
        case "JSON-FMT-11":
            let expected = ["前导零", "加号", "十六进制", "Infinity"]
            for (index, fragment) in expected.enumerated() {
                #expect(try jsonDiagnostic(try block(testCase, index)).message.contains(fragment))
            }
        case "JSON-FMT-12":
            #expect(try jsonDiagnostic(try block(testCase, 0)).message.contains("4 位十六进制"))
            #expect(try jsonDiagnostic(try block(testCase, 1)).message.contains("缺少低位代理项"))
            #expect(try jsonDiagnostic(try block(testCase, 2)).message.contains("低位代理项不能单独出现"))
        case "JSON-FMT-13":
            #expect(try jsonDiagnostic(try block(testCase, 0)).message.contains("控制字符"))
            #expect(try jsonDiagnostic(try block(testCase, 1)).message.contains("半角"))
        case "JSON-FMT-14":
            let input = try block(testCase, 0)
            let minified = try JSONFormatting.minify(input)
            #expect(minified.contains("900719925474099312345678901234567890"))
            #expect(minified.contains("0.000000000000000000123456789"))
            #expect(minified.contains("-0"))
            #expect(minified.contains("1.2300e+45"))
        case "JSON-FMT-15":
            for blank in ["", "   ", "\t\n"] {
                #expect(FormatRunner.run(blank) { try JSONFormatting.format($0, sortKeys: false, indentWidth: 2) } == .empty)
            }
        case "JSON-FMT-16":
            let source = try TestMarkdownCaseSupport.testCase("JSON-FMT-04")
            let diagnostic = try jsonDiagnostic(try block(source, 0))
            #expect(diagnostic.workspaceMessage == "对象末尾多了逗号")
            #expect(diagnostic.line != nil)
            #expect(diagnostic.column != nil)
        case "JSON-FMT-17":
            let expected = ["数组末尾多了逗号", "数组元素之间多了逗号", "对象成员之间多了逗号"]
            for (index, fragment) in expected.enumerated() {
                #expect(try jsonDiagnostic(try block(testCase, index)).message.contains(fragment))
            }
        case "JSON-FMT-18":
            for index in 0..<2 {
                #expect(try jsonDiagnostic(try block(testCase, index)).message.contains("根值后还有额外内容"))
            }
        case "JSON-FMT-19":
            let expected = ["加号", "十六进制", "小数部分只能使用半角", "指数部分只能使用半角"]
            for (index, fragment) in expected.enumerated() {
                #expect(try jsonDiagnostic(try block(testCase, index)).message.contains(fragment))
            }
        case "JSON-FMT-20":
            for index in 0..<2 {
                let diagnostic = try jsonDiagnostic(try block(testCase, index))
                #expect(diagnostic.message == "对象键后缺少值")
            }
        default:
            Issue.record("Unhandled case \(id)")
        }
    }

    @Test(arguments: [
        "SQL-FMT-01", "SQL-FMT-02", "SQL-FMT-03", "SQL-FMT-04", "SQL-FMT-05",
        "SQL-FMT-06", "SQL-FMT-07", "SQL-FMT-08", "SQL-FMT-09", "SQL-FMT-10",
        "SQL-FMT-11", "SQL-FMT-12", "SQL-FMT-13", "SQL-FMT-14", "SQL-FMT-15",
        "SQL-FMT-16"
    ])
    func sqlFormatterCase(_ id: String) throws {
        let testCase = try TestMarkdownCaseSupport.testCase(id)

        switch id {
        case "SQL-FMT-01":
            let output = try SQLFormatting.format(try block(testCase, 0))
            #expect(output.contains("SELECT"))
            #expect(output.contains("ORDER BY"))
            #expect(output.contains("LIMIT 10"))
        case "SQL-FMT-02":
            let output = try SQLFormatting.format(try block(testCase, 0))
            for fragment in ["with", "left join", "row_number", "case", "group by", "having", "order by"] {
                #expect(output.lowercased().contains(fragment))
            }
            #expect(output.contains("%@example.com"))
        case "SQL-FMT-03":
            let output = try SQLFormatting.format(try block(testCase, 0))
            #expect(output.contains("CREATE TABLE"))
            #expect(output.contains("INSERT INTO"))
            #expect(output.contains(#"{"tool":"json","success":true}"#))
        case "SQL-FMT-04":
            let output = try SQLFormatting.format(try block(testCase, 0))
            #expect(output.contains("`user`"))
            #expect(output.contains("->>"))
            #expect(output.contains(#""users""#))
        case "SQL-FMT-05":
            #expect(try sqlDiagnostic(try block(testCase, 0)).message.contains("字符串"))
        case "SQL-FMT-06":
            #expect(try sqlDiagnostic(try block(testCase, 0)).message.contains("SELECT 缺少"))
        case "SQL-FMT-07":
            let output = try SQLFormatting.format(try block(testCase, 0))
            #expect(output.contains("-- 单行注释应保留"))
            #expect(output.contains("/* 块注释应保留 */"))
            #expect(output.contains(#""order""#))
        case "SQL-FMT-08":
            let output = try SQLFormatting.format(try block(testCase, 0))
            for fragment in ["BEGIN;", "INSERT INTO", "UPDATE", "DELETE FROM", "COMMIT;"] {
                #expect(output.contains(fragment))
            }
        case "SQL-FMT-09":
            let output = try SQLFormatting.format(try block(testCase, 0))
            #expect(output.contains("'it''s ok'"))
            #expect(output.contains(#""quoted""identifier""#))
            #expect(output.contains("`quoted``identifier`"))
            #expect(output.contains("'-- not a comment'"))
        case "SQL-FMT-10":
            #expect(try sqlDiagnostic(try block(testCase, 0)).message.contains("左括号"))
        case "SQL-FMT-11":
            #expect(try sqlDiagnostic(try block(testCase, 0)).message.contains("ORDER BY 缺少排序表达式"))
        case "SQL-FMT-12":
            let input = try block(testCase, 0)
            let upper = try SQLFormatting.format(input, options: .init(keywordCase: .upper))
            let lower = try SQLFormatting.format(input, options: .init(keywordCase: .lower))
            #expect(upper.contains("SELECT DISTINCT"))
            #expect(lower.contains("select distinct"))
            #expect(lower.contains("users"))
        case "SQL-FMT-13":
            #expect(try sqlDiagnostic(try block(testCase, 0)).message.contains("PostgreSQL dollar-quoted"))
        case "SQL-FMT-14":
            #expect(FormatRunner.run(" \n\t ") { try SQLFormatting.format($0) } == .empty)
        case "SQL-FMT-15":
            let ids = ["SQL-FMT-05", "SQL-FMT-06", "SQL-FMT-10", "SQL-FMT-11"]
            for relatedID in ids {
                let related = try TestMarkdownCaseSupport.testCase(relatedID)
                let diagnostic = try sqlDiagnostic(try block(related, 0))
                assertFactual(diagnostic)
            }
        case "SQL-FMT-16":
            let options = SQLFormatting.Options(keywordCase: .lower, indentWidth: 4, commaStyle: .leading)
            let output = try SQLFormatting.format(try block(testCase, 0), options: options)
            #expect(output.contains("select\n    id\n  , name\n  , email"))
            #expect(output.contains("where\n    id = 1"))
        default:
            Issue.record("Unhandled case \(id)")
        }
    }

    @Test(arguments: [
        "XML-FMT-01", "XML-FMT-02", "XML-FMT-03", "XML-FMT-04", "XML-FMT-05", "XML-FMT-06",
        "XML-FMT-07", "XML-FMT-08", "XML-FMT-09", "XML-FMT-10", "XML-FMT-11", "XML-FMT-12"
    ])
    func xmlFormatterCase(_ id: String) throws {
        let testCase = try TestMarkdownCaseSupport.testCase(id)

        switch id {
        case "XML-FMT-01":
            let output = try XMLFormatting.format(try block(testCase, 0))
            #expect(output.contains("<user id=\"1\">"))
            #expect(output.contains("<name>Alice</name>"))
        case "XML-FMT-02":
            let output = try XMLFormatting.format(try block(testCase, 0))
            #expect(output.contains("xmlns:app="))
            #expect(output.contains("<![CDATA["))
            #expect(output.contains("unicode-🙂"))
            #expect(output.contains("&amp;"))
        case "XML-FMT-03":
            let output = try XMLFormatting.format(try block(testCase, 0))
            #expect(output.contains("Hello <strong>world</strong>"))
            #expect(output.contains("this is <em>mixed</em> content."))
        case "XML-FMT-04":
            #expect(try xmlDiagnostic(try block(testCase, 0)).message.contains("标签不匹配"))
        case "XML-FMT-05":
            #expect(try xmlDiagnostic(try block(testCase, 0)).message.contains("重复属性"))
        case "XML-FMT-06":
            #expect(try xmlDiagnostic(try block(testCase, 0)).message.contains("&"))
        case "XML-FMT-07":
            #expect(try xmlDiagnostic(try block(testCase, 0)).message == "属性值必须使用引号")
        case "XML-FMT-08":
            let output = try XMLFormatting.format(try block(testCase, 0))
            #expect(output.contains("<?xml version="))
            #expect(output.contains("<?xml-stylesheet"))
            #expect(output.contains("<!-- keep this comment -->"))
            #expect(output.contains("<empty></empty>") || output.contains("<empty/>"))
        case "XML-FMT-09":
            #expect(try xmlDiagnostic(try block(testCase, 0)).message == "不支持 DOCTYPE 声明")
        case "XML-FMT-10":
            #expect(try xmlDiagnostic(try block(testCase, 0)).message.contains("根节点"))
        case "XML-FMT-11":
            #expect(FormatRunner.run(" \n\t ") { try XMLFormatting.format($0) } == .empty)
        case "XML-FMT-12":
            for relatedID in ["XML-FMT-04", "XML-FMT-05", "XML-FMT-06", "XML-FMT-07", "XML-FMT-10"] {
                let related = try TestMarkdownCaseSupport.testCase(relatedID)
                assertFactual(try xmlDiagnostic(try block(related, 0)))
            }
        default:
            Issue.record("Unhandled case \(id)")
        }
    }

    @Test(arguments: [
        "YAML-FMT-01", "YAML-FMT-02", "YAML-FMT-03", "YAML-FMT-04", "YAML-FMT-05",
        "YAML-FMT-06", "YAML-FMT-07", "YAML-FMT-08", "YAML-FMT-09", "YAML-FMT-10",
        "YAML-FMT-11", "YAML-FMT-12", "YAML-FMT-13", "YAML-FMT-14"
    ])
    func yamlFormatterCase(_ id: String) throws {
        let testCase = try TestMarkdownCaseSupport.testCase(id)

        switch id {
        case "YAML-FMT-01":
            let output = try YAMLPrettifier.formatValidated(try block(testCase, 0))
            #expect(output.contains("id: 1"))
            #expect(output.contains("tags: [dev, ops]"))
        case "YAML-FMT-02":
            let output = try YAMLPrettifier.formatValidated(try block(testCase, 0))
            #expect(output.contains("defaults: &defaults"))
            #expect(output.contains("<<: *defaults"))
            #expect(output.contains("release_notes: |"))
            #expect(output.contains("folded_text: >"))
            try YAMLPrettifier.validate(output)
        case "YAML-FMT-03":
            let output = try YAMLPrettifier.formatValidated(try block(testCase, 0))
            for fragment in ["yes_unquoted: yes", "no_unquoted: no", "on_unquoted: on", "off_unquoted: off", "date_unquoted: 2026-07-07", "quoted_yes: \"yes\""] {
                #expect(output.contains(fragment))
            }
        case "YAML-FMT-04":
            #expect(try yamlDiagnostic(try block(testCase, 0)).message.contains("缩进"))
        case "YAML-FMT-05":
            #expect(try yamlDiagnostic(try block(testCase, 0)).message.contains("制表符"))
        case "YAML-FMT-06":
            #expect(try yamlDiagnostic(try block(testCase, 0)).message.contains("冒号"))
        case "YAML-FMT-07":
            #expect(try yamlDiagnostic(try block(testCase, 0)).message.contains("未定义的锚点别名"))
        case "YAML-FMT-08":
            let output = try YAMLPrettifier.formatValidated(try block(testCase, 0))
            #expect(output.contains("list: [json, sql, xml]"))
            #expect(output.contains("path: \"/tmp/a:b\""))
            try YAMLPrettifier.validate(output)
        case "YAML-FMT-09":
            let output = try YAMLPrettifier.formatValidated(try block(testCase, 0))
            #expect(output.contains("echo \"start: $(date)\""))
            #expect(output.contains("{\"id\":1,\"ok\":true}"))
            #expect(output.contains("next: value"))
        case "YAML-FMT-10":
            #expect(try yamlDiagnostic(try block(testCase, 0)).message.contains("引号字符串没有闭合"))
        case "YAML-FMT-11":
            #expect(try yamlDiagnostic(try block(testCase, 0)).message.contains("只允许包含一个 YAML 文档"))
        case "YAML-FMT-12":
            #expect(try yamlDiagnostic(try block(testCase, 0)).message.contains("重复键"))
        case "YAML-FMT-13":
            #expect(FormatRunner.run(" \n\t ") { try YAMLPrettifier.formatValidated($0) } == .empty)
        case "YAML-FMT-14":
            for relatedID in ["YAML-FMT-04", "YAML-FMT-05", "YAML-FMT-07", "YAML-FMT-10", "YAML-FMT-11", "YAML-FMT-12"] {
                let related = try TestMarkdownCaseSupport.testCase(relatedID)
                assertFactual(try yamlDiagnostic(try block(related, 0)))
            }
        default:
            Issue.record("Unhandled case \(id)")
        }
    }

    private func block(_ testCase: MarkdownDevelopmentCase, _ index: Int) throws -> String {
        try TestMarkdownCaseSupport.block(testCase, index)
    }

    private func jsonDiagnostic(_ input: String) throws -> FormatDiagnostic {
        try TestMarkdownCaseSupport.jsonDiagnostic(input)
    }

    private func sqlDiagnostic(_ input: String) throws -> FormatDiagnostic {
        try TestMarkdownCaseSupport.sqlDiagnostic(input)
    }

    private func xmlDiagnostic(_ input: String) throws -> FormatDiagnostic {
        try TestMarkdownCaseSupport.xmlDiagnostic(input)
    }

    private func yamlDiagnostic(_ input: String) throws -> FormatDiagnostic {
        try TestMarkdownCaseSupport.yamlDiagnostic(input)
    }

    private func assertFactual(_ diagnostic: FormatDiagnostic) {
        TestMarkdownCaseSupport.assertFactual(diagnostic)
    }
}
