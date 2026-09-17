import Foundation

public struct JSONDiffOptions: Equatable, Sendable {
    public let ignoreArrayOrder: Bool

    public init(ignoreArrayOrder: Bool = false) {
        self.ignoreArrayOrder = ignoreArrayOrder
    }
}

public enum JSONStructuralDiff {
    public enum Decision: Equatable, Sendable {
        case empty
        case invalid(String)
        case tooLarge(String)
        case comparable([DiffAlignedRow])
    }

    public static func cancellableAlignedDiff(
        left: String,
        right: String,
        labels: JSONDiffValidation.SideLabels,
        options: JSONDiffOptions = JSONDiffOptions(),
        budget: LineDiffBudget = .standard,
        shouldCancel: @escaping @Sendable () -> Bool = { Task.isCancelled }
    ) throws -> Decision {
        let cancellation = DiffCancellationChecker(shouldCancel: shouldCancel)
        try cancellation.check()

        switch JSONDiffValidation.evaluate(left: left, right: right, labels: labels) {
        case .empty:
            return .empty
        case .invalid(let message):
            return .invalid(message)
        case .comparable:
            try cancellation.check()
            if areStructurallyEquivalent(left: left, right: right, options: options) {
                return .comparable([])
            }

            try cancellation.check()
            let leftDisplayText = displayTextForDiff(left, options: options) ?? left
            try cancellation.check()
            let rightDisplayText = displayTextForDiff(right, options: options) ?? right
            try cancellation.check()

            do {
                return .comparable(try LineDiffer.safeAlignedDiff(
                    left: leftDisplayText,
                    right: rightDisplayText,
                    budget: budget,
                    shouldCancel: shouldCancel
                ))
            } catch let error as LineDiffError {
                return .tooLarge(error.errorDescription ?? LineDiffError.inputTooLargeMessage)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                return .tooLarge(LineDiffError.inputTooLargeMessage)
            }
        }
    }

    private static func areStructurallyEquivalent(left: String, right: String, options: JSONDiffOptions) -> Bool {
        let leftTrimmed = left.trimmingCharacters(in: .whitespacesAndNewlines)
        let rightTrimmed = right.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !leftTrimmed.isEmpty && !rightTrimmed.isEmpty else {
            return false
        }

        do {
            return try canonicalJSON(leftTrimmed, options: options) == canonicalJSON(rightTrimmed, options: options)
        } catch {
            return false
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
