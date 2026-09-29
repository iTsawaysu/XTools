import Foundation

public struct SourceControlScanner: Sendable {
    private let git: any GitProcessClient
    private let maximumConcurrentRepositories: Int
    private let homeDirectoryPath: @Sendable () -> String

    /// - Parameter homeDirectoryPath: root used by the `.machine` scope.
    ///   Injectable so behavior tests can point whole-machine discovery at a
    ///   fixture tree instead of the real home directory.
    public init(
        git: any GitProcessClient = SystemGitProcessClient(),
        maximumConcurrentRepositories: Int = 4,
        homeDirectoryPath: @escaping @Sendable () -> String = { NSHomeDirectory() }
    ) {
        self.git = git
        self.maximumConcurrentRepositories = max(1, maximumConcurrentRepositories)
        self.homeDirectoryPath = homeDirectoryPath
    }

    public func scan(
        scope: SourceControlScanScope,
        onRepository: (@Sendable (SourceControlRepository) async -> Void)? = nil
    ) async throws -> SourceControlScanSnapshot {
        try Task.checkCancellation()
        let paths = try discoverRepositoryPaths(scope: scope)
        guard !paths.isEmpty else {
            if scope.isSingleRepository { throw SourceControlError.notRepository }
            return SourceControlScanSnapshot(scope: scope, repositories: [])
        }

        var repositories: [SourceControlRepository] = []
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
                }
            }
        }

        repositories.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        return SourceControlScanSnapshot(scope: scope, repositories: repositories)
    }

    private func discoverRepositoryPaths(scope: SourceControlScanScope) throws -> [String] {
        let fileManager = FileManager.default
        let scopeRoot: String
        switch scope {
        case .machine: scopeRoot = homeDirectoryPath()
        case let .repository(path), let .directory(path): scopeRoot = path
        }
        let root = URL(fileURLWithPath: scopeRoot).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw SourceControlError.invalidScope
        }

        switch scope {
        case .repository:
            guard hasGitMarker(at: root) else { throw SourceControlError.notRepository }
            return [root.path]
        case .machine, .directory:
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
            var ignored = Set([".git", "node_modules", ".build", "build", "DerivedData", "Pods", ".swiftpm"])
            if case .machine = scope {
                // Whole-machine walks stay inside the user's data domain:
                // macOS system volumes are SIP/TCC-gated noise, and home
                // media/library trees hold no repositories but dominate the
                // walk cost. Toolchain caches duplicate dependency folders.
                ignored.formUnion(Self.machineExcludedDirectoryNames)
            }
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
                // `go` keeps module caches under `<go root>/pkg`; only that
                // subtree is dependency noise.
                let isGoPackageCache = item.lastPathComponent == "pkg" && item.deletingLastPathComponent().lastPathComponent == "go"
                if ignored.contains(item.lastPathComponent) || isGoPackageCache {
                    enumerator.skipDescendants()
                    continue
                }
                if hasGitMarker(at: item) {
                    result.insert(item.standardizedFileURL.path)
                    enumerator.skipDescendants()
                }
            }
            if result.isEmpty, rootIsRepository { result.insert(root.path) }
            return result.sorted()
        }
    }

    /// Directory names skipped by `.machine` discovery in addition to the
    /// shared workspace ignore list.
    private static let machineExcludedDirectoryNames: Set<String> = [
        // macOS data domains that never contain user repositories.
        "Library", "Applications", "Movies", "Music", "Pictures", "Public", "Sites", ".Trash",
        // Toolchain / package caches (multi-GB trees with nested VCS metadata).
        ".cache", ".npm", ".cargo", ".rustup", ".pyenv", ".rbenv", ".nvm",
        ".docker", ".colima", ".orbstack", ".gradle", ".m2", ".cocoapods",
        ".conda", ".venv", "venv", "site-packages",
    ]

    private func hasGitMarker(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path, isDirectory: &isDirectory)
    }
}

private func readRepository(path: String, git: any GitProcessClient) async throws -> SourceControlRepository {
    async let branchOutput = requiredOutput(git: git, kind: .branch, path: path)
    async let revisionOutput = requiredOutput(git: git, kind: .revision, path: path)
    async let remoteOutput = optionalOutput(git: git, kind: .remote, path: path)
    async let upstreamOutput = optionalOutput(git: git, kind: .upstream, path: path)
    async let statusOutput = requiredOutput(git: git, kind: .status, path: path)
    async let divergenceOutput = optionalOutput(git: git, kind: .divergence, path: path)
    async let branchesOutput = optionalOutput(git: git, kind: .branches, path: path)
    let branchResult = try await branchOutput
    let branch = cleanLine(branchResult.standardOutput)
    let fullRevision = cleanLine((try await revisionOutput).standardOutput)
    let remoteInfo = parseRemote(cleanLines((try await remoteOutput)?.standardOutput))
    let upstreamResult = try await upstreamOutput
    let upstream = cleanLine(upstreamResult?.standardOutput)
    let divergenceResult = try await divergenceOutput
    let hasUpstream = upstreamResult != nil || divergenceResult != nil
    let statusText = try await statusOutput.standardOutput
    let divergence = parseDivergence(divergenceResult?.standardOutput)
    let remoteRevision = upstream.isEmpty ? nil : cleanSHA((try await optionalOutput(git: git, kind: .remoteRevision, path: path, argument: upstream))?.standardOutput)
    let remoteState: SourceControlRemoteState
    if !hasUpstream { remoteState = .noUpstream }
    else if divergence.ahead > 0, divergence.behind > 0 { remoteState = .diverged }
    else if divergence.ahead > 0 { remoteState = .localAhead }
    else if divergence.behind > 0 { remoteState = .updateAvailable }
    else if let remoteRevision, !remoteRevision.isEmpty { remoteState = remoteRevision == fullRevision ? .upToDate : .unknown }
    else { remoteState = .unknown }
    var defaultBranch: String?
    if let name = remoteInfo.name {
        defaultBranch = cleanLine((try await optionalOutput(git: git, kind: .defaultBranch, path: path, argument: name))?.standardOutput)
        if defaultBranch?.hasPrefix("\(name)/") == true { defaultBranch = String(defaultBranch!.dropFirst(name.count + 1)) }
    }
    return SourceControlRepository(path: URL(fileURLWithPath: path).standardizedFileURL.path, branch: branch, shortRevision: String(fullRevision.prefix(8)), remote: remoteInfo.url, status: parseStatus(statusText, branch: branch), ahead: divergence.ahead, behind: divergence.behind, hasUpstream: hasUpstream, upstream: upstream.isEmpty ? nil : upstream, revision: fullRevision.isEmpty ? nil : fullRevision, remoteRevision: remoteRevision, remoteState: remoteState, branches: parseBranches((try await branchesOutput)?.standardOutput, remoteName: remoteInfo.name), defaultBranch: defaultBranch)
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

private func cleanSHA(_ value: String?) -> String? {
    guard let line = value?.split(whereSeparator: \.isNewline).first else { return nil }
    return line.split(whereSeparator: \.isWhitespace).first.map(String.init)
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

private func parseStatus(_ value: String, branch: String) -> SourceControlRepositoryStatus {
    if branch.isEmpty || branch == "HEAD" { return .detached }
    let lines = value.split(whereSeparator: \.isNewline)
    guard !lines.isEmpty else { return .clean }
    if lines.contains(where: { line in
        let text = String(line)
        guard text.count >= 2 else { return false }
        let pair = Array(text.prefix(2))
        return pair.contains("U") || text.hasPrefix("AA") || text.hasPrefix("DD")
    }) { return .conflicted }
    if lines.contains(where: { $0.hasPrefix("??") }) { return .untracked }
    return .modified
}

private func parseDivergence(_ value: String?) -> (behind: Int, ahead: Int) {
    guard let value else { return (0, 0) }
    let fields = value.split(whereSeparator: \.isWhitespace)
    guard fields.count >= 2, let behind = Int(fields[0]), let ahead = Int(fields[1]) else { return (0, 0) }
    return (max(0, behind), max(0, ahead))
}
