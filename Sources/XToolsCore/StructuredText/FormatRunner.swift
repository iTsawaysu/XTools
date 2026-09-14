import Foundation

public protocol FormatDiagnosticProviding: Error {
    var diagnostic: FormatDiagnostic { get }
}

public enum FormatOutcome<Value> {
    case empty
    case produced(Value)
    case failed(FormatDiagnostic)
}

extension FormatOutcome: Equatable where Value: Equatable {}
extension FormatOutcome: Sendable where Value: Sendable {}

public enum FormatRunner {
    /// 运行一次格式化：输入去除首尾空白后为空则返回 `.empty`（不调用 `produce`）；
    /// 否则调用 `produce`，成功返回 `.produced`，抛出携带诊断的错误返回 `.failed`
    /// 并保留完整 `FormatDiagnostic`，其他错误回退为仅含消息的诊断。
    public static func run<Value>(
        _ input: String,
        produce: (String) throws -> Value
    ) -> FormatOutcome<Value> {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .empty
        }

        do {
            return .produced(try produce(input))
        } catch let error as FormatDiagnosticProviding {
            return .failed(error.diagnostic)
        } catch {
            return .failed(FormatDiagnostic(formatName: "", message: "格式化失败，输入内容无法解析"))
        }
    }
}

/// 一次格式化运行归约到页面状态的三元组：输出文本、错误诊断、警告。
/// 把「empty → 清空、produced → 写输出(可带 warning)、failed → 写错误诊断」
/// 的赋值阶梯收进一个可测的接缝，页面不再各自重写同一 switch。
public struct FormatBinding: Equatable, Sendable {
    public var output: String
    public var error: String?
    public var warning: String?

    public init(output: String = "", error: String? = nil, warning: String? = nil) {
        self.output = output
        self.error = error
        self.warning = warning
    }
}

public extension FormatOutcome {
    /// 把三态结果归约为页面状态三元组。`text` 从产出值取输出文本，
    /// `warning` 从产出值取可选警告（默认无警告）。失败态携带适合工作区展示的诊断文案。
    func binding(
        text: (Value) -> String,
        warning: (Value) -> String? = { _ in nil }
    ) -> FormatBinding {
        switch self {
        case .empty:
            return FormatBinding(output: "", error: nil, warning: nil)
        case .produced(let value):
            return FormatBinding(output: text(value), error: nil, warning: warning(value))
        case .failed(let diagnostic):
            return FormatBinding(output: "", error: diagnostic.workspaceMessage, warning: nil)
        }
    }
}

extension JSONFormatting.FormattingError: FormatDiagnosticProviding {}
extension XMLFormatting.FormattingError: FormatDiagnosticProviding {}
extension YAMLPrettifier.ValidationError: FormatDiagnosticProviding {}
extension SQLFormatting.ValidationError: FormatDiagnosticProviding {}
