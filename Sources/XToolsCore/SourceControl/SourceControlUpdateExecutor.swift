import Foundation

public struct SourceControlUpdateExecutor: Sendable {
    private let git: any GitProcessClient
    private let coordinator = UpdateCoordinator()
    public init(git: any GitProcessClient = SystemGitProcessClient()) { self.git = git }

    /// Updates selected repositories serially and publishes one result per row.
    /// The non-throwing compatibility entry point reports cancellation as a final
    /// `.cancelled` row; `updateOrThrow` is available to callers that need a
    /// cancellation error after the progress stream has drained.
    ///
    /// `force` relaxes only the clean-worktree precondition: the pull stays
    /// `git pull --ff-only`, so git itself still refuses when uncommitted
    /// changes would be overwritten or the branch cannot fast-forward.
    public func update(
        repositories: [SourceControlRepository],
        force: Bool = false,
        onResult: (@Sendable (SourceControlOperationResult) async -> Void)? = nil
    ) async -> [SourceControlOperationResult] {
        do { return try await updateOrThrow(repositories: repositories, force: force, onResult: onResult) }
        catch is CancellationError { return [] }
        catch { return [] }
    }

    func updateOrThrow(
        repositories: [SourceControlRepository],
        force: Bool = false,
        onResult: (@Sendable (SourceControlOperationResult) async -> Void)? = nil
    ) async throws -> [SourceControlOperationResult] {
        guard await coordinator.begin() else { return [] }
        var results: [SourceControlOperationResult] = []; results.reserveCapacity(repositories.count)
        for repository in repositories {
            if Task.isCancelled { await coordinator.end(); throw CancellationError() }
            guard repository.isFastForwardCandidate || force else { let result = SourceControlOperationResult(repository: repository, outcome: .skipped); results.append(result); await onResult?(result); continue }
            do {
                try await verifySnapshot(repository, allowDirtyWorktree: force)
            } catch is CancellationError {
                let result = SourceControlOperationResult(repository: repository, outcome: .cancelled)
                results.append(result)
                await onResult?(result)
                await coordinator.end()
                throw CancellationError()
            } catch let error as SourceControlError where error == .cancelled {
                let result = SourceControlOperationResult(repository: repository, outcome: .cancelled)
                results.append(result)
                await onResult?(result)
                await coordinator.end()
                throw CancellationError()
            } catch {
                let result = SourceControlOperationResult(repository: repository, outcome: .failed(SourceControlError.staleSnapshot.diagnostic)); results.append(result); await onResult?(result); continue
            }
            do {
                let output = try await git.run(GitCommandRequest(kind: .pullFastForward, repositoryPath: repository.path), timeout: .seconds(120))
                guard output.exitCode == 0 else {
                    let result = SourceControlOperationResult(repository: repository, outcome: .failed(SourceControlDiagnostic.pullFailure(standardError: output.standardError))); results.append(result); await onResult?(result); continue
                }
                let text = output.standardOutput.localizedLowercase
                let outcome: SourceControlOperationOutcome = text.contains("already up to date") || text.contains("already up-to-date") ? .upToDate : .updated
                let result = SourceControlOperationResult(repository: repository, outcome: outcome); results.append(result); await onResult?(result)
            } catch is CancellationError {
                let result = SourceControlOperationResult(repository: repository, outcome: .cancelled); results.append(result); await onResult?(result); await coordinator.end(); throw CancellationError()
            } catch let error as SourceControlError where error == .cancelled {
                let result = SourceControlOperationResult(repository: repository, outcome: .cancelled); results.append(result); await onResult?(result); await coordinator.end(); throw CancellationError()
            } catch let error as SourceControlError {
                let result = SourceControlOperationResult(repository: repository, outcome: .failed(error.diagnostic)); results.append(result); await onResult?(result)
            } catch {
                let result = SourceControlOperationResult(repository: repository, outcome: .failed(SourceControlError.commandFailed.diagnostic)); results.append(result); await onResult?(result)
            }
        }
        await coordinator.end(); return results
    }

    private func verifySnapshot(_ repository: SourceControlRepository, allowDirtyWorktree: Bool = false) async throws {
        // Unit fixtures often use virtual paths. Real repositories are always
        // re-read; a missing path is left to the Git command itself for compatibility.
        guard FileManager.default.fileExists(atPath: repository.path) else { return }
        let root = try await required(.repositoryRoot, repository.path)
        guard URL(fileURLWithPath: cleanLine(root.standardOutput)).standardizedFileURL.path == URL(fileURLWithPath: repository.path).standardizedFileURL.path else { throw SourceControlError.staleSnapshot }
        // 单次 porcelain v2 同时复核分支、HEAD、upstream 与工作区状态。
        let snapshot = GitStatusV2Snapshot(statusV2: try await required(.statusV2, repository.path).standardOutput)
        guard snapshot.branch == repository.branch else { throw SourceControlError.staleSnapshot }
        if let expected = repository.revision { guard snapshot.revision == expected else { throw SourceControlError.staleSnapshot } }
        if !allowDirtyWorktree {
            guard snapshot.worktreeStatus == .clean else { throw SourceControlError.staleSnapshot }
        }
        if repository.hasUpstream, let expectedUpstream = repository.upstream {
            guard snapshot.upstream == expectedUpstream else { throw SourceControlError.staleSnapshot }
        }
    }

    private func required(_ kind: GitCommandKind, _ path: String) async throws -> GitProcessOutput {
        let output = try await git.run(GitCommandRequest(kind: kind, repositoryPath: path), timeout: .seconds(30)); guard output.exitCode == 0 else { throw SourceControlError.staleSnapshot }; return output
    }
    private func cleanLine(_ value: String) -> String { value.split(whereSeparator: \.isNewline).first.map(String.init) ?? "" }
}

private actor UpdateCoordinator {
    private var active = false
    func begin() -> Bool { guard !active else { return false }; active = true; return true }
    func end() { active = false }
}
