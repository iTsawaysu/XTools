import XToolsCore
import Testing

struct JSONDiffValidationTests {
    private let labels = JSONDiffValidation.SideLabels(left: "JSON A", right: "JSON B")

    @Test func bothEmptyStaysQuiet() {
        #expect(JSONDiffValidation.evaluate(left: "", right: "   \n ", labels: labels) == .empty)
    }

    @Test func bothValidIsComparable() {
        let decision = JSONDiffValidation.evaluate(
            left: #"{"a":1}"#,
            right: #"{"a":2}"#,
            labels: labels
        )
        #expect(decision == .comparable)
    }

    @Test func oneEmptySideIsStillComparable() {
        // 空侧不校验（合法的「整体缺失」场景）。
        let decision = JSONDiffValidation.evaluate(
            left: #"{"a":1}"#,
            right: "",
            labels: labels
        )
        #expect(decision == .comparable)
    }

    @Test func onlyBadSideIsReported() {
        // 左侧非法、右侧合法：只报左侧。
        let decision = JSONDiffValidation.evaluate(
            left: "{not json",
            right: #"{"a":1}"#,
            labels: labels
        )
        guard case .invalid(let message) = decision else {
            Issue.record("Expected invalid decision")
            return
        }
        #expect(message.contains("JSON A 格式错误"))
        #expect(message == "JSON A 格式错误：对象键必须使用双引号包裹")
        #expect(!message.contains("请修正该侧后再对比"))
        #expect(!message.contains("处理方式："))
    }

    @Test func trailingCommaIsRejected() {
        let decision = JSONDiffValidation.evaluate(
            left: #"{"a":1}"#,
            right: #"{"a":1,}"#,
            labels: labels
        )
        guard case .invalid(let message) = decision else {
            Issue.record("Expected invalid decision")
            return
        }
        #expect(message.contains("JSON B 格式错误"))
        #expect(message.contains("对象末尾多了逗号"))
        #expect(message == "JSON B 格式错误：对象末尾多了逗号")
        #expect(!message.contains("请修正该侧后再对比"))
        #expect(!message.contains("处理方式："))
    }

    @Test func bothBadSidesAreJoined() {
        let decision = JSONDiffValidation.evaluate(
            left: "{bad",
            right: "]also bad",
            labels: labels
        )
        guard case .invalid(let message) = decision else {
            Issue.record("Expected invalid decision")
            return
        }
        #expect(message.contains("JSON A 格式错误"))
        #expect(message.contains("JSON B 格式错误"))
        #expect(!message.contains("处理方式："))
        #expect(!message.contains("请修正该侧后再对比"))
        #expect(message.contains("\nJSON B 格式错误"))
        #expect(!message.contains("；"))
        #expect(message == "JSON A 格式错误：对象键必须使用双引号包裹\nJSON B 格式错误：遇到不能作为 JSON 值开头的字符 ]")
    }

    @Test func emptySideIsNotReportedEvenWhenOtherIsBad() {
        // 右侧空不报「为空」，只报左侧非法。
        let decision = JSONDiffValidation.evaluate(
            left: "{bad",
            right: "",
            labels: labels
        )
        guard case .invalid(let message) = decision else {
            Issue.record("Expected invalid decision")
            return
        }
        #expect(message.contains("JSON A 格式错误"))
        #expect(!message.contains("JSON B 格式错误"))
    }

    @Test func topLevelFragmentIsValid() {
        // fragmentsAllowed：裸字面量算合法。
        let decision = JSONDiffValidation.evaluate(left: "42", right: #""hi""#, labels: labels)
        #expect(decision == .comparable)
    }

    @Test func duplicateKeysProduceComparisonWarningWithoutBlockingDiff() {
        let warning = JSONDiffValidation.comparisonWarning(
            left: #"{"name":"first","name":"second"}"#,
            right: #"{"name":"second"}"#,
            labels: labels
        )

        #expect(JSONDiffValidation.evaluate(
            left: #"{"name":"first","name":"second"}"#,
            right: #"{"name":"second"}"#,
            labels: labels
        ) == .comparable)
        #expect(warning == "JSON A 含重复 key。")
    }

    @Test func duplicateKeyWarningKeepsBothSideLabelsWithoutImplementationDetails() {
        let warning = JSONDiffValidation.comparisonWarning(
            left: #"{"name":"first","name":"second"}"#,
            right: #"{"id":1,"id":2}"#,
            labels: labels
        )

        #expect(warning == "JSON A 和 JSON B 均含重复 key。")
    }

    @Test func labelsAreCallerProvided() {
        let decision = JSONDiffValidation.evaluate(
            left: "{bad",
            right: "",
            labels: JSONDiffValidation.SideLabels(left: "左", right: "右")
        )
        guard case .invalid(let message) = decision else {
            Issue.record("Expected invalid decision")
            return
        }
        #expect(message.contains("左 格式错误"))
    }
}
