import Foundation

/// A formatter run keeps the existing serial worker; its cancellation probe is
/// supplied by that worker rather than by a second detached task.
public enum StructuredTextExecution {
    public static let maximumInputBytes = 15_000_000
    public static let maximumOutputBytes = 60_000_000

    @TaskLocal static var cancellationProbe: (@Sendable () -> Bool)?
    @TaskLocal static var outputByteLimit = maximumOutputBytes

    public static func withCancellation<Value>(
        _ shouldCancel: @escaping @Sendable () -> Bool,
        operation: () throws -> Value
    ) rethrows -> Value {
        try $cancellationProbe.withValue(shouldCancel, operation: operation)
    }

    static func checkCancellation() throws {
        if Task.isCancelled || cancellationProbe?() == true { throw CancellationError() }
    }

    static func checkpoint(_ offset: Int) throws {
        if offset & 1023 == 0 { try checkCancellation() }
    }

    static func validateInput(_ input: String, format: String) throws {
        try checkCancellation()
        // Match the existing file-import envelope for pasted and Core input too.
        // Reject explicitly; never substitute a preview/truncated document.
        guard input.utf8.count <= maximumInputBytes else {
            throw StructuredTextResourceError(format: format, reason: "输入超过 15 MB 处理上限")
        }
    }

    static func validateIndent(_ indent: Int, format: String) throws {
        guard indent <= 64 else {
            throw StructuredTextResourceError(format: format, reason: "缩进宽度超过 64 个空格")
        }
    }
}

struct StructuredTextResourceError: FormatDiagnosticProviding, Equatable {
    let format: String
    let reason: String

    var diagnostic: FormatDiagnostic {
        FormatDiagnostic(
            formatName: format,
            message: "\(format) \(reason)",
            suggestion: "请缩小输入或降低嵌套与缩进后重试；原文未被截断。"
        )
    }
}

/// Checks the remaining byte budget before extending storage. Rejected output
/// is never published, so copying/exporting can only see a complete result.
struct StructuredTextOutput {
    let format: String
    private(set) var text = ""
    private(set) var byteCount = 0

    mutating func append(_ value: String) throws {
        try StructuredTextExecution.checkCancellation()
        try reserve(value.utf8.count)
        text += value
    }

    mutating func spaces(_ count: Int) throws {
        try StructuredTextExecution.checkCancellation()
        try reserve(max(0, count))
        text += String(repeating: " ", count: max(0, count))
    }

    mutating func reserve(_ count: Int) throws {
        guard count >= 0, count <= StructuredTextExecution.outputByteLimit - byteCount else {
            throw StructuredTextResourceError(format: format, reason: "结果超过处理容量上限")
        }
        byteCount += count
    }
}
