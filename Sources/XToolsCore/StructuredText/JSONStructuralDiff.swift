import Foundation

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
            if areStructurallyEquivalent(left: left, right: right) {
                return .comparable([])
            }

            try cancellation.check()
            let leftDisplayText = displayTextForDiff(left) ?? left
            try cancellation.check()
            let rightDisplayText = displayTextForDiff(right) ?? right
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

    private static func areStructurallyEquivalent(left: String, right: String) -> Bool {
        let leftTrimmed = left.trimmingCharacters(in: .whitespacesAndNewlines)
        let rightTrimmed = right.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !leftTrimmed.isEmpty && !rightTrimmed.isEmpty else {
            return false
        }

        do {
            return try canonicalJSON(leftTrimmed) == canonicalJSON(rightTrimmed)
        } catch {
            return false
        }
    }

    private static func canonicalJSON(_ text: String) throws -> String {
        try JSONFormatting.format(text, sortKeys: true, indentWidth: 2)
    }

    public static func displayTextForDiff(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return try? canonicalJSON(trimmed)
    }
}
