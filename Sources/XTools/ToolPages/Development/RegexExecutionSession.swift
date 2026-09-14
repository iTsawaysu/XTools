import Combine
import XToolsCore
import Foundation

typealias RegexMatchOperation = @Sendable (
    _ pattern: String,
    _ text: String,
    _ flags: String
) throws -> RegexMatcher.Report

@MainActor
final class RegexExecutionSession: ObservableObject {
    @Published private(set) var report: RegexMatcher.Report?
    @Published private(set) var reportSourceText: String?
    @Published private(set) var error: String?
    @Published private(set) var isRunning = false

    private let workGate = AsyncWorkGate()

    func invalidate() {
        workGate.invalidate()
        report = nil
        reportSourceText = nil
        error = nil
        isRunning = false
    }

    func run(
        pattern: String,
        text: String,
        flags: String,
        operation: @escaping RegexMatchOperation = RegexExecutionSession.defaultOperation
    ) {
        invalidate()
        guard !pattern.isEmpty else { return }

        isRunning = true
        let token = workGate.token
        workGate.runDetached { [operation] in
            do {
                return Outcome.success(try operation(pattern, text, flags))
            } catch let error as RegexMatcher.MatcherError {
                return .failure(error)
            } catch {
                return .unknownFailure
            }
        } publish: { [weak self] outcome in
            guard let self, self.workGate.isCurrent(token) else { return }
            self.isRunning = false
            switch outcome {
            case .success(let report):
                self.reportSourceText = text
                self.report = report
                self.error = nil
            case .failure(let error):
                self.report = nil
                self.reportSourceText = nil
                self.error = error.errorDescription ?? "正则匹配失败。"
            case .unknownFailure:
                self.report = nil
                self.reportSourceText = nil
                self.error = "正则匹配失败。"
            }
        }
    }

    nonisolated private static func defaultOperation(
        pattern: String,
        text: String,
        flags: String
    ) throws -> RegexMatcher.Report {
        try RegexMatcher.analyze(pattern: pattern, in: text, flags: flags)
    }

    private enum Outcome: Sendable {
        case success(RegexMatcher.Report)
        case failure(RegexMatcher.MatcherError)
        case unknownFailure
    }
}
