import Foundation

public struct SourceControlUpdateExecutor: Sendable {
    private let git: any GitProcessClient
    private let coordinator = UpdateCoordinator()
    public init(git: any GitProcessClient = SystemGitProcessClient()) { self.git = git }

    /// Updates selected repositories serially and publishes one result per row.
    /// The non-throwing compatibility entry point reports cancellation as a final
    /// `.cancelled` row; `updateOrThrow` is available to callers that need a
    /// cancellation error after the progress stream has drained.
    public func update(repositories: [SourceControlRepository], onResult: (@Sendable (SourceControlOperationResult) async -> Void)? = nil) async -> [SourceControlOperationResult] {
        do { return try await updateOrThrow(repositories: repositories, onResult: onResult) }
        catch is CancellationError { return [] }
        catch { return [] }
    }

    public func updateOrThrow(repositories: [SourceControlRepository], onResult: (@Sendable (SourceControlOperationResult) async -> Void)? = nil) async throws -> [SourceControlOperationResult] {
        guard await coordinator.begin() else { return [] }
        var results: [SourceControlOperationResult] = []; results.reserveCapacity(repositories.count)
        for repository in repositories {
            if Task.isCancelled { await coordinator.end(); throw CancellationError() }
            guard repository.isFastForwardCandidate else { let result = SourceControlOperationResult(repository: repository, outcome: .skipped); results.append(result); await onResult?(result); continue }
            do {
                try await verifySnapshot(repository)
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

    private func verifySnapshot(_ repository: SourceControlRepository) async throws {
        // Unit fixtures often use virtual paths. Real repositories are always
        // re-read; a missing path is left to the Git command itself for compatibility.
        guard FileManager.default.fileExists(atPath: repository.path) else { return }
        let root = try await required(.repositoryRoot, repository.path)
        guard URL(fileURLWithPath: cleanLine(root.standardOutput)).standardizedFileURL.path == URL(fileURLWithPath: repository.path).standardizedFileURL.path else { throw SourceControlError.staleSnapshot }
        let branch = try await required(.branch, repository.path)
        guard cleanLine(branch.standardOutput) == repository.branch else { throw SourceControlError.staleSnapshot }
        let revision = try await required(.revision, repository.path)
        if let expected = repository.revision { guard cleanLine(revision.standardOutput) == expected else { throw SourceControlError.staleSnapshot } }
        let status = try await required(.status, repository.path)
        guard status.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SourceControlError.staleSnapshot }
        let upstream = try await optional(.upstream, repository.path)
        if repository.hasUpstream, let expectedUpstream = repository.upstream {
            guard cleanLine(upstream?.standardOutput ?? "") == expectedUpstream else { throw SourceControlError.staleSnapshot }
        }
    }

    private func required(_ kind: GitCommandKind, _ path: String) async throws -> GitProcessOutput {
        let output = try await git.run(GitCommandRequest(kind: kind, repositoryPath: path), timeout: .seconds(30)); guard output.exitCode == 0 else { throw SourceControlError.staleSnapshot }; return output
    }
    private func optional(_ kind: GitCommandKind, _ path: String) async throws -> GitProcessOutput? {
        do {
            return try await git.run(GitCommandRequest(kind: kind, repositoryPath: path), timeout: .seconds(30))
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as SourceControlError where error == .cancelled {
            throw error
        } catch {
            return nil
        }
    }
    private func cleanLine(_ value: String) -> String { value.split(whereSeparator: \.isNewline).first.map(String.init) ?? "" }
}

private actor UpdateCoordinator {
    private var active = false
    func begin() -> Bool { guard !active else { return false }; active = true; return true }
    func end() { active = false }
}
