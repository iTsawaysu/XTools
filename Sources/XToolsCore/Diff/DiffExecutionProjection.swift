import Foundation

public enum DiffExecutionKind: Equatable, Sendable {
    case text(options: TextDiffOptions = TextDiffOptions())
    case json(labels: JSONDiffValidation.SideLabels, options: JSONDiffOptions = JSONDiffOptions())

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
    _ request: DiffExecutionRequest,
    _ shouldCancel: @escaping @Sendable () -> Bool
) throws -> DiffExecutionBinding

public enum DiffExecution {
    public static func project(
        _ request: DiffExecutionRequest,
        shouldCancel: @escaping @Sendable () -> Bool = { Task.isCancelled }
    ) throws -> DiffExecutionBinding {
        try project(
            request,
            shouldCancel: shouldCancel,
            jsonParserDidStart: nil
        )
    }

    static func project(
        _ request: DiffExecutionRequest,
        shouldCancel: @escaping @Sendable () -> Bool,
        jsonParserDidStart: (@Sendable () -> Void)?
    ) throws -> DiffExecutionBinding {
        if shouldCancel() {
            throw CancellationError()
        }
        switch request.kind {
        case .text(let options):
            do {
                return DiffExecutionBinding(rows: try LineDiffer.safeAlignedDiff(
                    left: request.left,
                    right: request.right,
                    options: options,
                    shouldCancel: shouldCancel
                ))
            } catch let error as LineDiffError {
                return DiffExecutionBinding(
                    error: error.errorDescription ?? LineDiffError.inputTooLargeMessage
                )
            }

        case .json(let labels, let options):
            let prepared = try JSONStructuralDiff.cancellablePreparedDiff(
                left: request.left,
                right: request.right,
                labels: labels,
                options: options,
                shouldCancel: shouldCancel,
                parserDidStart: jsonParserDidStart
            )
            if shouldCancel() { throw CancellationError() }

            switch prepared.decision {
            case .empty:
                return DiffExecutionBinding()
            case .invalid(let message), .tooLarge(let message):
                return DiffExecutionBinding(error: message)
            case .comparable(let rows):
                // Folding is a view-mode projection: the binding always
                // carries the full canonical rows and display text, and the
                // editable diff workspace re-projects them through
                // DiffFoldProjection with its per-region expansion state.
                return DiffExecutionBinding(
                    leftDisplayText: prepared.leftDisplayText,
                    rightDisplayText: prepared.rightDisplayText,
                    rows: rows,
                    warning: prepared.warning
                )
            }
        }
    }

    public static func failureBinding() -> DiffExecutionBinding {
        DiffExecutionBinding(error: LineDiffError.inputTooLargeMessage)
    }
}
