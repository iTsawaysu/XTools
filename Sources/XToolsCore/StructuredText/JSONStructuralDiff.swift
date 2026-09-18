import Foundation

public struct JSONDiffOptions: Equatable, Sendable {
    public let ignoreArrayOrder: Bool
    public let foldUnchanged: Bool

    public init(ignoreArrayOrder: Bool = false, foldUnchanged: Bool = false) {
        self.ignoreArrayOrder = ignoreArrayOrder
        self.foldUnchanged = foldUnchanged
    }
}

public enum JSONStructuralDiff {
    public enum Decision: Equatable, Sendable {
        case empty
        case invalid(String)
        case tooLarge(String)
        case comparable([DiffAlignedRow])
    }

    public struct PreparedResult: Equatable, Sendable {
        public let decision: Decision
        public let leftDisplayText: String?
        public let rightDisplayText: String?
        public let warning: String?

        init(
            decision: Decision,
            leftDisplayText: String? = nil,
            rightDisplayText: String? = nil,
            warning: String? = nil
        ) {
            self.decision = decision
            self.leftDisplayText = leftDisplayText
            self.rightDisplayText = rightDisplayText
            self.warning = warning
        }
    }

    private struct PreparedSide: Equatable, Sendable {
        let isEmpty: Bool
        let displayText: String?
        let exactIdentity: JSONExactTextIdentity?
        let duplicateKeys: [String]
        let diagnostic: FormatDiagnostic?
    }

    public static func cancellableAlignedDiff(
        left: String,
        right: String,
        labels: JSONDiffValidation.SideLabels,
        options: JSONDiffOptions = JSONDiffOptions(),
        budget: LineDiffBudget = .standard,
        shouldCancel: @escaping @Sendable () -> Bool = { Task.isCancelled }
    ) throws -> Decision {
        try cancellablePreparedDiff(
            left: left,
            right: right,
            labels: labels,
            options: options,
            budget: budget,
            shouldCancel: shouldCancel
        ).decision
    }

    public static func cancellablePreparedDiff(
        left: String,
        right: String,
        labels: JSONDiffValidation.SideLabels,
        options: JSONDiffOptions = JSONDiffOptions(),
        budget: LineDiffBudget = .standard,
        shouldCancel: @escaping @Sendable () -> Bool = { Task.isCancelled }
    ) throws -> PreparedResult {
        try cancellablePreparedDiff(
            left: left,
            right: right,
            labels: labels,
            options: options,
            budget: budget,
            shouldCancel: shouldCancel,
            parserDidStart: nil
        )
    }

    /// Internal instrumentation seam for proving that one diff request starts
    /// the ordered parser at most once per non-empty side.
    static func cancellablePreparedDiff(
        left: String,
        right: String,
        labels: JSONDiffValidation.SideLabels,
        options: JSONDiffOptions = JSONDiffOptions(),
        budget: LineDiffBudget = .standard,
        shouldCancel: @escaping @Sendable () -> Bool = { Task.isCancelled },
        parserDidStart: (@Sendable () -> Void)?
    ) throws -> PreparedResult {
        let cancellation = DiffCancellationChecker(shouldCancel: shouldCancel)
        try cancellation.check()

        do {
            // This gate deliberately precedes trimming, parser construction,
            // canonical rendering, and line preprocessing.
            try budget.validateInputBytes(
                leftByteCount: left.utf8.count,
                rightByteCount: right.utf8.count
            )
        } catch let error as LineDiffError {
            return PreparedResult(
                decision: .tooLarge(error.errorDescription ?? LineDiffError.inputTooLargeMessage)
            )
        }
        try cancellation.check()

        let preparedLeft = try prepareSide(
            left,
            options: options,
            cancellation: cancellation,
            parserDidStart: parserDidStart
        )
        let preparedRight = try prepareSide(
            right,
            options: options,
            cancellation: cancellation,
            parserDidStart: parserDidStart
        )

        switch JSONDiffValidation.decision(
            leftIsEmpty: preparedLeft.isEmpty,
            rightIsEmpty: preparedRight.isEmpty,
            leftDiagnostic: preparedLeft.diagnostic,
            rightDiagnostic: preparedRight.diagnostic,
            labels: labels
        ) {
        case .empty:
            return PreparedResult(decision: .empty)
        case .invalid(let message):
            return PreparedResult(decision: .invalid(message))
        case .comparable:
            try cancellation.check()
            let warning = JSONDiffValidation.comparisonWarning(
                leftHasDuplicateKeys: !preparedLeft.duplicateKeys.isEmpty,
                rightHasDuplicateKeys: !preparedRight.duplicateKeys.isEmpty,
                labels: labels
            )
            let commonResult = PreparedResult(
                decision: .comparable([]),
                leftDisplayText: preparedLeft.displayText,
                rightDisplayText: preparedRight.displayText,
                warning: warning
            )

            if let leftIdentity = preparedLeft.exactIdentity,
               let rightIdentity = preparedRight.exactIdentity,
               leftIdentity == rightIdentity {
                return commonResult
            }

            do {
                let rows = try LineDiffer.safeAlignedDiff(
                    left: preparedLeft.displayText ?? left,
                    right: preparedRight.displayText ?? right,
                    budget: budget,
                    shouldCancel: shouldCancel
                )
                return PreparedResult(
                    decision: .comparable(rows),
                    leftDisplayText: preparedLeft.displayText,
                    rightDisplayText: preparedRight.displayText,
                    warning: warning
                )
            } catch let error as LineDiffError {
                return PreparedResult(
                    decision: .tooLarge(error.errorDescription ?? LineDiffError.inputTooLargeMessage)
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                return PreparedResult(decision: .tooLarge(LineDiffError.inputTooLargeMessage))
            }
        }
    }

    private static func prepareSide(
        _ text: String,
        options: JSONDiffOptions,
        cancellation: DiffCancellationChecker,
        parserDidStart: (@Sendable () -> Void)?
    ) throws -> PreparedSide {
        try cancellation.check()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return PreparedSide(
                isEmpty: true,
                displayText: nil,
                exactIdentity: nil,
                duplicateKeys: [],
                diagnostic: nil
            )
        }

        do {
            let result = try JSONFormatting.formatResult(
                trimmed,
                sortKeys: true,
                sortArrays: options.ignoreArrayOrder,
                indentWidth: 2,
                parserDidStart: parserDidStart
            )
            try cancellation.check()
            return PreparedSide(
                isEmpty: false,
                displayText: result.text,
                exactIdentity: result.exactTextIdentity,
                duplicateKeys: result.duplicateKeys,
                diagnostic: nil
            )
        } catch let error as JSONFormatting.FormattingError {
            return PreparedSide(
                isEmpty: false,
                displayText: nil,
                exactIdentity: nil,
                duplicateKeys: [],
                diagnostic: error.diagnostic
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return PreparedSide(
                isEmpty: false,
                displayText: nil,
                exactIdentity: nil,
                duplicateKeys: [],
                diagnostic: FormatDiagnostic(formatName: "JSON", message: "JSON 语法错误")
            )
        }
    }

    private static func canonicalJSON(_ text: String, options: JSONDiffOptions) throws -> String {
        try JSONFormatting.format(text, sortKeys: true, sortArrays: options.ignoreArrayOrder, indentWidth: 2)
    }

    public static func displayTextForDiff(_ text: String, options: JSONDiffOptions = JSONDiffOptions()) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return try? canonicalJSON(trimmed, options: options)
    }

}
