import Foundation

/// JSON 对比的分侧格式校验：把 SPEC §D1 的三态决策
///（两侧空则安静、只报非法侧、都合法才对比）收进一个可测接缝。
public enum JSONDiffValidation {
    public struct SideLabels: Equatable, Sendable {
        public let left: String
        public let right: String

        public init(left: String, right: String) {
            self.left = left
            self.right = right
        }
    }

    public enum Decision: Equatable, Sendable {
        case empty
        case invalid(String)
        case comparable
    }

    /// 对每个非空侧分别校验；空侧不校验（合法的「整体缺失」场景）。
    /// 只对非法侧提示，不报「为空」（SPEC §D1）。
    public static func evaluate(left: String, right: String, labels: SideLabels) -> Decision {
        let leftTrimmed = left.trimmingCharacters(in: .whitespacesAndNewlines)
        let rightTrimmed = right.trimmingCharacters(in: .whitespacesAndNewlines)

        if leftTrimmed.isEmpty && rightTrimmed.isEmpty {
            return .empty
        }

        var badSides: [String] = []

        if !leftTrimmed.isEmpty, let diagnostic = invalidJSONDiagnostic(for: leftTrimmed) {
            badSides.append(sideErrorMessage(label: labels.left, diagnostic: diagnostic))
        }

        if !rightTrimmed.isEmpty, let diagnostic = invalidJSONDiagnostic(for: rightTrimmed) {
            badSides.append(sideErrorMessage(label: labels.right, diagnostic: diagnostic))
        }

        if !badSides.isEmpty {
            return .invalid(badSides.joined(separator: "\n"))
        }

        return .comparable
    }

    public static func sideErrorMessage(label: String, diagnostic: FormatDiagnostic) -> String {
        "\(label) 格式错误：\(diagnostic.message)"
    }

    public static func comparisonWarning(left: String, right: String, labels: SideLabels) -> String? {
        let warningSides = [
            duplicateKeySideLabel(for: left, label: labels.left),
            duplicateKeySideLabel(for: right, label: labels.right)
        ].compactMap(\.self)

        switch warningSides.count {
        case 0:
            return nil
        case 1:
            return "\(warningSides[0]) 含重复 key。"
        default:
            return "\(warningSides[0]) 和 \(warningSides[1]) 均含重复 key。"
        }
    }

    /// 使用项目自己的有序 JSON parser 校验，避免 Foundation 宽松解析把尾逗号等
    /// 非标准输入误判为可比较 JSON，同时保留格式化器已有的行列和原因诊断。
    private static func invalidJSONDiagnostic(for value: String) -> FormatDiagnostic? {
        do {
            _ = try JSONFormatting.minify(value)
            return nil
        } catch let error as JSONFormatting.FormattingError {
            return error.diagnostic
        } catch {
            return FormatDiagnostic(
                formatName: "JSON",
                message: "JSON 语法错误"
            )
        }
    }

    private static func duplicateKeySideLabel(for value: String, label: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let result = try? JSONFormatting.formatResult(trimmed, sortKeys: true, indentWidth: 2),
              !result.duplicateKeys.isEmpty else {
            return nil
        }

        return label
    }
}
