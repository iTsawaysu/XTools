import Foundation
import Testing

enum ToolDiagnosticContract {
    static let maximumMessageCharacters = 180

    private static let forbiddenFragments = [
        "处理方式：",
        "建议：",
        "请检查",
        "请改",
        "请确认",
        "请尝试",
        "可尝试",
        "Error Domain",
        "NSCocoaErrorDomain",
        "NSURLErrorDomain",
        "The operation couldn’t be completed",
        "The operation could not be completed",
        "execution error",
        "System Events got an error",
        "Invalid index",
        "osascript",
        "screencapture",
        "/tmp/",
    ]

    static func violations(
        in message: String,
        sensitiveInputs: [String] = []
    ) -> [String] {
        var violations: [String] = []
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            violations.append("诊断不能为空")
        }
        if message.contains("\n") || message.contains("\r") {
            violations.append("诊断必须保持为一个段落")
        }
        if message.count > maximumMessageCharacters {
            violations.append("诊断超过 \(maximumMessageCharacters) 个字符")
        }

        for fragment in forbiddenFragments where message.localizedCaseInsensitiveContains(fragment) {
            violations.append("诊断包含禁用片段：\(fragment)")
        }

        if message.range(
            of: #"第\s*\d+\s*行(?:第?\s*\d+\s*列)?"#,
            options: .regularExpression
        ) != nil {
            violations.append("诊断不应显示源码式行列位置")
        }

        for input in sensitiveInputs {
            let candidate = input.trimmingCharacters(in: .whitespacesAndNewlines)
            guard candidate.count >= 8 else { continue }
            if sensitiveFragments(in: candidate).contains(where: message.contains) {
                violations.append("诊断回显了原始或敏感输入")
            }
        }

        return violations
    }

    private static func sensitiveFragments(in input: String) -> [String] {
        var fragments = [input]
        fragments += input
            .split(whereSeparator: \Character.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 16 }

        let words = input.split(whereSeparator: \Character.isWhitespace)
        guard words.count >= 3 else { return fragments }

        for start in words.indices.dropLast(2) {
            let end = words.index(start, offsetBy: 3)
            let fragment = words[start..<end].joined(separator: " ")
            if fragment.count >= 16 {
                fragments.append(fragment)
            }
        }
        return fragments
    }

    static func expectFactual(
        _ message: String,
        sensitiveInputs: [String] = [],
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let violations = violations(in: message, sensitiveInputs: sensitiveInputs)
        #expect(
            violations.isEmpty,
            Comment(rawValue: violations.joined(separator: "；")),
            sourceLocation: sourceLocation
        )
    }
}

struct ToolDiagnosticContractSupportTests {
    @Test func acceptsOneParagraphFactualMessages() {
        #expect(ToolDiagnosticContract.violations(
            in: "十进制数只能包含 0–9，可在开头使用正负号。"
        ).isEmpty)
        #expect(ToolDiagnosticContract.violations(
            in: "URL 返回 HTTP 404，无法转换。"
        ).isEmpty)
    }

    @Test func rejectsLogsRemediationSystemErrorsAndInputEchoes() {
        let terminalLog = "osascript -e 'tell application System Events' /tmp/capture.mov"
        let messages = [
            "第一行\n第二行",
            "处理方式：把输入改成十进制数字。",
            "转换失败，请检查输入。",
            "Error Domain=NSCocoaErrorDomain Code=4",
            "JSON第1行第18列：数字不能有前导零。",
            "「osascript -e 'tell application System Events'…」不是有效的十进制数",
        ]

        for message in messages {
            #expect(!ToolDiagnosticContract.violations(
                in: message,
                sensitiveInputs: [terminalLog]
            ).isEmpty)
        }
    }

    @Test func sharedAndEmojiCopyFailuresUseFactualCopy() throws {
        let shared = try readSource("Sources/XTools/ToolPages/Workbench/Controls/IndexControls.swift")
        let emoji = try readSource("Sources/XTools/ToolPages/Utility/EmojiPickerPage.swift")

        #expect(shared.contains("剪贴板写入失败。"))
        #expect(emoji.contains("剪贴板写入失败。"))
        #expect(!shared.contains("复制失败，请重试"))
        #expect(!emoji.contains("复制失败，请重试"))
        ToolDiagnosticContract.expectFactual("剪贴板写入失败。")
    }
}
