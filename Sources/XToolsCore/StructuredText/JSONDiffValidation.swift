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
        return decision(
            leftIsEmpty: leftTrimmed.isEmpty,
            rightIsEmpty: rightTrimmed.isEmpty,
            leftDiagnostic: leftTrimmed.isEmpty ? nil : invalidJSONDiagnostic(for: leftTrimmed),
            rightDiagnostic: rightTrimmed.isEmpty ? nil : invalidJSONDiagnostic(for: rightTrimmed),
            labels: labels
        )
    }

    public static func sideErrorMessage(label: String, diagnostic: FormatDiagnostic) -> String {
        "\(label) 格式错误：\(diagnostic.message)"
    }

    public static func comparisonWarning(left: String, right: String, labels: SideLabels) -> String? {
        comparisonWarning(
            leftHasDuplicateKeys: duplicateKeySideLabel(for: left, label: labels.left) != nil,
            rightHasDuplicateKeys: duplicateKeySideLabel(for: right, label: labels.right) != nil,
            labels: labels
        )
    }

    static func decision(
        leftIsEmpty: Bool,
        rightIsEmpty: Bool,
        leftDiagnostic: FormatDiagnostic?,
        rightDiagnostic: FormatDiagnostic?,
        labels: SideLabels
    ) -> Decision {
        if leftIsEmpty && rightIsEmpty {
            return .empty
        }

        switch (leftDiagnostic, rightDiagnostic) {
        case (nil, nil):
            return .comparable
        case (let left?, nil):
            return .invalid(sideErrorMessage(label: labels.left, diagnostic: left))
        case (nil, let right?):
            return .invalid(sideErrorMessage(label: labels.right, diagnostic: right))
        case (let left?, let right?):
            return .invalid(bothSidesErrorMessage(left: left, right: right, labels: labels))
        }
    }

    /// 顶栏通栏横幅只承载单段文案，因此两侧同时格式错误时不能用换行拼接。
    /// 优先给出双侧原因；总长超出可读上限时退化为不指明具体原因的双侧结论。
    static func bothSidesErrorMessage(
        left: FormatDiagnostic,
        right: FormatDiagnostic,
        labels: SideLabels
    ) -> String {
        let detailed = "\(labels.left) 与 \(labels.right) 均有格式错误；"
            + "\(labels.left)：\(left.message)；"
            + "\(labels.right)：\(right.message)"
        guard detailed.count > maximumMessageCharacters else {
            return detailed
        }
        return "\(labels.left) 与 \(labels.right) 均有格式错误。"
    }

    /// 与 `ToolDiagnosticContract.maximumMessageCharacters` 保持一致的可读上限。
    static let maximumMessageCharacters = 180

    static func comparisonWarning(
        leftHasDuplicateKeys: Bool,
        rightHasDuplicateKeys: Bool,
        labels: SideLabels
    ) -> String? {
        let warningSides = [
            leftHasDuplicateKeys ? labels.left : nil,
            rightHasDuplicateKeys ? labels.right : nil
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
