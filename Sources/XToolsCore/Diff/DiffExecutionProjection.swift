import Foundation

public enum DiffExecutionKind: Equatable, Sendable {
    case text(options: TextDiffOptions = TextDiffOptions())
    case json(labels: JSONDiffValidation.SideLabels)

    public static var text: DiffExecutionKind {
        .text()
    }
}

public struct DiffExecutionRequest: Equatable, Sendable {
    public let kind: DiffExecutionKind
    public let left: String
    public let right: String

    public init(kind: DiffExecutionKind, left: String, right: String) {
        self.kind = kind
        self.left = left
        self.right = right
    }
}

public struct DiffExecutionBinding: Equatable, Sendable {
    public let leftDisplayText: String?
    public let rightDisplayText: String?
    public let rows: [DiffAlignedRow]
    public let error: String?
    public let warning: String?

    public init(
        leftDisplayText: String? = nil,
        rightDisplayText: String? = nil,
        rows: [DiffAlignedRow] = [],
        error: String? = nil,
        warning: String? = nil
    ) {
        self.leftDisplayText = leftDisplayText
        self.rightDisplayText = rightDisplayText
        self.rows = rows
        self.error = error
        self.warning = warning
    }
}

public typealias DiffExecutionOperation = @Sendable (
    _ request: DiffExecutionRequest
) throws -> DiffExecutionBinding

public enum DiffExecution {
    public static func project(_ request: DiffExecutionRequest) throws -> DiffExecutionBinding {
        switch request.kind {
        case .text(let options):
            do {
                return DiffExecutionBinding(rows: try LineDiffer.safeAlignedDiff(
                    left: request.left,
                    right: request.right,
                    options: options
                ))
            } catch let error as LineDiffError {
                return DiffExecutionBinding(
                    error: error.errorDescription ?? LineDiffError.inputTooLargeMessage
                )
            }

        case .json(let labels):
            let decision = try JSONStructuralDiff.cancellableAlignedDiff(
                left: request.left,
                right: request.right,
                labels: labels
            )
            try Task.checkCancellation()

            switch decision {
            case .empty:
                return DiffExecutionBinding()
            case .invalid(let message), .tooLarge(let message):
                return DiffExecutionBinding(error: message)
            case .comparable(let rows):
                let leftDisplayText = JSONStructuralDiff.displayTextForDiff(request.left)
                try Task.checkCancellation()
                let rightDisplayText = JSONStructuralDiff.displayTextForDiff(request.right)
                try Task.checkCancellation()
                let warning = JSONDiffValidation.comparisonWarning(
                    left: request.left,
                    right: request.right,
                    labels: labels
                )
                try Task.checkCancellation()
                return DiffExecutionBinding(
                    leftDisplayText: leftDisplayText,
                    rightDisplayText: rightDisplayText,
                    rows: rows,
                    warning: warning
                )
            }
        }
    }

    public static func failureBinding() -> DiffExecutionBinding {
        DiffExecutionBinding(error: LineDiffError.inputTooLargeMessage)
    }
}
