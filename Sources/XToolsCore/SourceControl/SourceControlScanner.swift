import Foundation

public struct SourceControlScanner: Sendable {
    private let git: any GitProcessClient
    private let maximumConcurrentRepositories: Int

    public init(git: any GitProcessClient = SystemGitProcessClient(), maximumConcurrentRepositories: Int = 4) {
        self.git = git
        self.maximumConcurrentRepositories = max(1, maximumConcurrentRepositories)
    }

    public func scan(
        scope: SourceControlScanScope,
        onRepository: (@Sendable (SourceControlRepository) async -> Void)? = nil,
        onProgress: (@Sendable (SourceControlScanProgress) async -> Void)? = nil
    ) async throws -> SourceControlScanSnapshot {
        try Task.checkCancellation()
        let paths = try discoverRepositoryPaths(scope: scope) { discovered in
            let progress = SourceControlScanProgress(discoveredCount: discovered, readCompletedCount: 0, readTotalCount: nil)
            // The walk is synchronous on a background executor; hop to the
            // caller's context without blocking the enumeration.
            Task { await onProgress?(progress) }
        }
        guard !paths.isEmpty else {
            if scope.isSingleRepository { throw SourceControlError.notRepository }
            return SourceControlScanSnapshot(scope: scope, repositories: [])
        }

        var repositories: [SourceControlRepository] = []
        var readCompleted = 0
        var index = 0
        while index < paths.count {
            try Task.checkCancellation()
            let end = min(paths.count, index + maximumConcurrentRepositories)
            let batch = Array(paths[index..<end])
            index = end
            try await withThrowingTaskGroup(of: SourceControlRepository.self) { group in
                for path in batch {
                    group.addTask { [git] in
                        do {
                            return try await readRepository(path: path, git: git)
                        } catch is CancellationError {
                            throw SourceControlError.cancelled
                        } catch let error as SourceControlError {
                            if error == .cancelled { throw error }
                            return failedRepository(path: path, error: error)
                        } catch {
                            return failedRepository(path: path, error: .commandFailed)
                        }
                    }
                }
                for try await repository in group {
                    repositories.append(repository)
                    await onRepository?(repository)
                    readCompleted += 1
                    await onProgress?(SourceControlScanProgress(
                        discoveredCount: paths.count,
                        readCompletedCount: readCompleted,
                        readTotalCount: paths.count
                    ))
                }
            }
        }

        repositories.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        return SourceControlScanSnapshot(scope: scope, repositories: repositories)
    }

    private func discoverRepositoryPaths(
        scope: SourceControlScanScope,
        onDiscovery: ((Int) -> Void)? = nil
    ) throws -> [String] {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: scope.path).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw SourceControlError.invalidScope
        }

        switch scope {
        case .repository:
            guard hasGitMarker(at: root) else { throw SourceControlError.notRepository }
            return [root.path]
        case .directory:
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsPackageDescendants]
            ) else { return [] }

            // A selected workspace may itself be a repository while also
            // containing many nested repositories (for example a `work`
            // directory with one project per child directory). Walk through
            // the workspace repository, but prefer its nested projects when
            // any are found. The root remains available through single-repo
            // mode and is used as the directory result only when it has no
            // nested repositories.
            let ignored = Set([".git", "node_modules", ".build", "build", "DerivedData", "Pods", ".swiftpm"])
            let rootIsRepository = hasGitMarker(at: root)
            var result = Set<String>()
            while let item = enumerator.nextObject() as? URL {
                try Task.checkCancellation()
                let values = try item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values.isSymbolicLink == true {
                    if values.isDirectory == true { enumerator.skipDescendants() }
                    continue
                }
                guard values.isDirectory == true else { continue }
                if ignored.contains(item.lastPathComponent) {
                    enumerator.skipDescendants()
                    continue
                }
                if hasGitMarker(at: item) {
                    result.insert(item.standardizedFileURL.path)
                    onDiscovery?(result.count)
                    enumerator.skipDescendants()
                }
            }
            if result.isEmpty, rootIsRepository { result.insert(root.path) }
            return result.sorted()
        }
    }

    /// `.git` 可能是目录（普通仓库）也可能是文件（子模块/worktree 指针），存在即算仓库。
    private func hasGitMarker(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path)
    }
}

private func readRepository(path: String, git: any GitProcessClient) async throws -> SourceControlRepository {
    // 单次 porcelain v2 覆盖 branch/revision/upstream/ahead-behind/工作区状态，
    // 再并行取远端与分支列表：每仓 4 个子进程（旧形态 8 个）。
    async let statusOutput = requiredOutput(git: git, kind: .statusV2, path: path)
    async let remoteOutput = optionalOutput(git: git, kind: .remote, path: path)
    async let branchesOutput = optionalOutput(git: git, kind: .branches, path: path)
    let snapshot = GitStatusV2Snapshot(statusV2: try await statusOutput.standardOutput)
    let remoteInfo = parseRemote(cleanLines((try await remoteOutput)?.standardOutput))
    var defaultBranch: String?
    if let name = remoteInfo.name {
        defaultBranch = cleanLine((try await optionalOutput(git: git, kind: .defaultBranch, path: path, argument: name))?.standardOutput)
        if defaultBranch?.hasPrefix("\(name)/") == true { defaultBranch = String(defaultBranch!.dropFirst(name.count + 1)) }
    }
    // Scanning stays offline: no per-repository `ls-remote`. Divergence against
    // the local tracking refs classifies the row, and `git pull --ff-only`
    // reveals the true remote state at update time. One network round trip per
    // repository made large workspaces crawl when remotes were slow/unreachable.
    let hasUpstream = snapshot.upstream != nil
    let remoteState: SourceControlRemoteState
    if !hasUpstream { remoteState = .noUpstream }
    else if snapshot.ahead > 0, snapshot.behind > 0 { remoteState = .diverged }
    else if snapshot.ahead > 0 { remoteState = .localAhead }
    else if snapshot.behind > 0 { remoteState = .updateAvailable }
    else { remoteState = .upToDate }
    return SourceControlRepository(
        path: URL(fileURLWithPath: path).standardizedFileURL.path,
        branch: snapshot.branch,
        shortRevision: String(snapshot.revision?.prefix(8) ?? ""),
        remote: remoteInfo.url,
        status: snapshot.worktreeStatus,
        ahead: snapshot.ahead,
        behind: snapshot.behind,
        hasUpstream: hasUpstream,
        upstream: snapshot.upstream,
        revision: snapshot.revision,
        remoteState: remoteState,
        branches: parseBranches((try await branchesOutput)?.standardOutput, remoteName: remoteInfo.name),
        defaultBranch: defaultBranch
    )
}

private func requiredOutput(git: any GitProcessClient, kind: GitCommandKind, path: String) async throws -> GitProcessOutput {
    let output = try await git.run(GitCommandRequest(kind: kind, repositoryPath: path), timeout: .seconds(30))
    guard output.exitCode == 0 else { throw SourceControlError.commandFailed }
    return output
}

private func optionalOutput(git: any GitProcessClient, kind: GitCommandKind, path: String, argument: String? = nil) async throws -> GitProcessOutput? {
    let output = try await git.run(GitCommandRequest(kind: kind, repositoryPath: path, argument: argument), timeout: .seconds(30))
    return output.exitCode == 0 ? output : nil
}

private func failedRepository(path: String, error: SourceControlError) -> SourceControlRepository {
    SourceControlRepository(
        path: URL(fileURLWithPath: path).standardizedFileURL.path,
        branch: "",
        shortRevision: "",
        remote: nil,
        status: .unknown,
        hasUpstream: false,
        remoteState: .unknown,
        diagnostic: error.diagnostic
    )
}

private func cleanLine(_ value: String?) -> String {
    value?.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
}

private func cleanLines(_ value: String?) -> [String] { value?.split(whereSeparator: \.isNewline).map(String.init) ?? [] }

private func parseRemote(_ lines: [String]) -> (name: String?, url: String?) {
    for line in lines {
        let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
        if fields.count >= 2, fields.last == "(fetch)" { return (fields[0], fields[1]) }
        if !line.isEmpty { return (nil, line) }
    }
    return (nil, nil)
}

private func parseBranches(_ value: String?, remoteName: String?) -> [String] {
    cleanLines(value).map { value in
        let parts = value.split(separator: "/", maxSplits: 1).map(String.init)
        return parts.count == 2 && parts[0] == (remoteName ?? "origin") ? parts[1] : value
    }.filter { !$0.isEmpty && !$0.contains("->") }
}
