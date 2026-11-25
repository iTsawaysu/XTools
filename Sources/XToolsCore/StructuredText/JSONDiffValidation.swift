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

    static func sideErrorMessage(label: String, diagnostic: FormatDiagnostic) -> String {
        "\(label) 格式错误：\(diagnostic.message)"
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

}
