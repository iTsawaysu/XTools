import Foundation

/// A repository discovered within a user-selected scope.
public struct SourceControlRepository: Identifiable, Hashable, Sendable {
    public let path: String
    public let branch: String
    public let shortRevision: String
    public let remote: String?
    public let status: SourceControlRepositoryStatus
    public let ahead: Int
    public let behind: Int
    public let hasUpstream: Bool
    /// The configured upstream ref (for example `origin/main`).
    public let upstream: String?
    /// Full local revision captured during scanning. Kept separate from the UI short SHA.
    public let revision: String?
    /// SHA reported by a read-only `git ls-remote` check.
    public let remoteRevision: String?
    public let remoteState: SourceControlRemoteState
    public let branches: [String]
    public let defaultBranch: String?
    /// A scan failure is retained on the row instead of silently dropping the repository.
    public let diagnostic: SourceControlDiagnostic?

    public var id: String { path }

    public var isFastForwardCandidate: Bool {
        guard status == .clean, !branch.isEmpty, branch != "HEAD", remote != nil, hasUpstream, ahead == 0 else { return false }
        switch remoteState {
        case .updateAvailable, .upToDate: return true
        case .unknown:
            // Preserve the original initializer's behaviour for older clients;
            // scanned rows always carry `revision` and use the explicit state.
            return behind > 0 || (revision == nil && upstream == nil && branches.isEmpty && remoteRevision == nil)
        default: return false
        }
    }

    public init(
        path: String,
        branch: String,
        shortRevision: String,
        remote: String?,
        status: SourceControlRepositoryStatus,
        ahead: Int = 0,
        behind: Int = 0,
        hasUpstream: Bool = true,
        upstream: String? = nil,
        revision: String? = nil,
        remoteRevision: String? = nil,
        remoteState: SourceControlRemoteState? = nil,
        branches: [String] = [],
        defaultBranch: String? = nil,
        diagnostic: SourceControlDiagnostic? = nil
    ) {
        self.path = path
        self.branch = branch
        self.shortRevision = shortRevision
        self.remote = remote
        self.status = status
        self.ahead = max(0, ahead)
        self.behind = max(0, behind)
        self.hasUpstream = hasUpstream
        self.upstream = upstream
        self.revision = revision
        self.remoteRevision = remoteRevision
        self.remoteState = remoteState ?? (hasUpstream ? (behind > 0 ? .updateAvailable : .unknown) : .noUpstream)
        self.branches = Array(Set(branches)).sorted()
        self.defaultBranch = defaultBranch
        self.diagnostic = diagnostic
    }
}

public enum SourceControlRemoteState: String, Codable, Hashable, Sendable {
    case unknown
    case noUpstream
    case upToDate
    case updateAvailable
    case diverged
    case localAhead
}

public enum SourceControlRepositoryStatus: String, Codable, CaseIterable, Sendable {
    case clean
    case modified
    case untracked
    case conflicted
    case detached
    case unknown
}

/// `git status --porcelain=v2 --branch` 的单次解析结果。一条命令同时给出
/// 分支、HEAD、upstream、ahead/behind 与工作区状态，取代过去五个独立
/// 子进程（branch/revision/upstream/status/divergence）。
/// LC_ALL=C 保证头行以 `# ` 前缀稳定输出。
public struct GitStatusV2Snapshot: Sendable, Equatable {
    public var branch: String
    /// 尚无提交的仓库为 nil（`# branch.oid (initial)`）。
    public var revision: String?
    public var upstream: String?
    public var ahead: Int
    public var behind: Int
    public var worktreeStatus: SourceControlRepositoryStatus

    public init(statusV2 output: String) {
        var branch = ""
        var revision: String?
        var upstream: String?
        var ahead = 0
        var behind = 0
        var sawUnmerged = false
        var sawUntracked = false
        var sawModified = false
        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            if line.hasPrefix("# branch.oid ") {
                let value = String(line.dropFirst("# branch.oid ".count))
                revision = value == "(initial)" ? nil : value.split(whereSeparator: \.isWhitespace).first.map(String.init)
            } else if line.hasPrefix("# branch.head ") {
                let value = String(line.dropFirst("# branch.head ".count)).trimmingCharacters(in: .whitespaces)
                branch = value == "(detached)" ? "HEAD" : value
            } else if line.hasPrefix("# branch.upstream ") {
                upstream = line.dropFirst("# branch.upstream ".count)
                    .split(whereSeparator: \.isWhitespace).first.map(String.init)
            } else if line.hasPrefix("# branch.ab ") {
                let fields = line.split(whereSeparator: \.isWhitespace)
                if fields.count >= 4 {
                    ahead = Int(fields[2].dropFirst()) ?? 0
                    behind = Int(fields[3].dropFirst()) ?? 0
                }
            } else if line.hasPrefix("u ") {
                sawUnmerged = true
            } else if line.hasPrefix("? ") {
                sawUntracked = true
            } else if line.hasPrefix("1 ") || line.hasPrefix("2 ") {
                sawModified = true
            }
        }
        self.branch = branch
        self.revision = revision
        self.upstream = (upstream?.isEmpty == true) ? nil : upstream
        self.ahead = max(0, ahead)
        self.behind = max(0, behind)
        // 与旧 v1 解析保持一致：分离头指针优先于任何工作区条目。
        if branch.isEmpty || branch == "HEAD" {
            self.worktreeStatus = .detached
        } else if sawUnmerged {
            self.worktreeStatus = .conflicted
        } else if sawUntracked {
            self.worktreeStatus = .untracked
        } else if sawModified {
            self.worktreeStatus = .modified
        } else {
            self.worktreeStatus = .clean
        }
    }
}

public enum SourceControlScanScope: Hashable, Sendable {
    case repository(path: String)
    case directory(path: String)

    public var path: String {
        switch self {
        case let .repository(path), let .directory(path): return path
        }
    }

    public var isSingleRepository: Bool {
        if case .repository = self { return true }
        return false
    }
}

public struct SourceControlScanSnapshot: Sendable, Equatable {
    public let scope: SourceControlScanScope
    public let repositories: [SourceControlRepository]
    public let diagnostics: [SourceControlDiagnostic]

    public init(scope: SourceControlScanScope, repositories: [SourceControlRepository], diagnostics: [SourceControlDiagnostic] = []) {
        self.scope = scope
        self.repositories = repositories
        self.diagnostics = diagnostics
    }
}

/// Live scan telemetry for progress surfaces. `readTotalCount` stays nil while
/// the directory walk is still discovering repositories; once the walk ends it
/// is fixed and `readCompletedCount` climbs toward it.
public struct SourceControlScanProgress: Sendable, Equatable {
    public let discoveredCount: Int
    public let readCompletedCount: Int
    public let readTotalCount: Int?

    public init(discoveredCount: Int, readCompletedCount: Int, readTotalCount: Int?) {
        self.discoveredCount = discoveredCount
        self.readCompletedCount = readCompletedCount
        self.readTotalCount = readTotalCount
    }
}

public enum SourceControlOperationOutcome: Sendable, Equatable {
    case updated
    case upToDate
    case skipped
    case cancelled
    case failed(SourceControlDiagnostic)
}

public struct SourceControlOperationResult: Sendable, Equatable, Identifiable {
    public let repository: SourceControlRepository
    public let outcome: SourceControlOperationOutcome

    public var id: String { repository.id }

    public init(repository: SourceControlRepository, outcome: SourceControlOperationOutcome) {
        self.repository = repository
        self.outcome = outcome
    }
}

public struct SourceControlDiagnostic: Error, Codable, Equatable, Hashable, Sendable {
    public let domain: String
    public let code: String
    public let summary: String
    public let recovery: String
    public let statusCode: Int?

    public init(
        domain: String = "source-control",
        code: String,
        summary: String,
        recovery: String,
        statusCode: Int? = nil
    ) {
        self.domain = domain
        self.code = code
        self.summary = summary
        self.recovery = recovery
        self.statusCode = statusCode
    }

    /// Classifies a failed `git pull --ff-only` from the process stderr so the
    /// failure summary can state an actionable cause instead of a generic
    /// "command failed". Matching is on git's stable LC_ALL=C phrasing.
    public static func pullFailure(standardError: String) -> SourceControlDiagnostic {
        let message = standardError.localizedLowercase
        if message.contains("would be overwritten by merge")
            || message.contains("your local changes to the following files would be overwritten")
            || message.contains("please commit your changes or stash them before you merge") {
            return SourceControlDiagnostic(
                code: "pull-dirty-worktree",
                summary: "工作区有未提交改动，拉取会被覆盖。",
                recovery: "请在仓库中提交或暂存改动后重试。"
            )
        }
        if message.contains("not possible to fast-forward") || message.contains("diverged") {
            return SourceControlDiagnostic(
                code: "pull-diverged",
                summary: "本地与远端分叉，无法快进合并。",
                recovery: "请先手动合并或变基该仓库，再回来同步。"
            )
        }
        if message.contains("authentication failed")
            || message.contains("could not read from remote repository")
            || message.contains("permission denied")
            || message.contains("fatal: unable to access")
            || message.contains("connection was closed")
            || message.contains("timed out") {
            return SourceControlDiagnostic(
                code: "pull-remote-unavailable",
                summary: "无法访问远端仓库（网络或认证失败）。",
                recovery: "请检查网络、SSH 密钥或凭据后重试。"
            )
        }
        if message.contains("conflict") || message.contains("merge conflict") {
            return SourceControlDiagnostic(
                code: "pull-conflict",
                summary: "合并时出现冲突。",
                recovery: "请手动解决冲突后重试。"
            )
        }
        let firstLine = standardError
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        let suffix = firstLine.map { "（\($0.prefix(160))）" } ?? ""
        return SourceControlDiagnostic(
            code: "pull-failed",
            summary: "拉取未完成\(suffix)。",
            recovery: "请检查仓库状态和远端配置后重试。"
        )
    }

    /// One-look Chinese reason chip for list rows and the failure sheet.
    public var shortLabel: String {
        switch code {
        case "pull-dirty-worktree": return "本地改动会被覆盖"
        case "pull-diverged": return "与远端分叉"
        case "pull-remote-unavailable": return "远端不可达"
        case "pull-conflict": return "合并冲突"
        case "pull-failed": return "拉取失败"
        case "stale-snapshot": return "仓库已变化"
        case "command-failed": return "执行失败"
        case "git-unavailable": return "Git 不可用"
        case "timed-out": return "超时"
        default: return "失败"
        }
    }
}

public enum SourceControlError: Error, Equatable, Sendable {
    case invalidScope
    case notRepository
    case gitUnavailable
    case commandFailed
    case staleSnapshot
    case operationInProgress
    case timedOut
    case cancelled
}

public extension SourceControlError {
    var diagnostic: SourceControlDiagnostic {
        switch self {
        case .invalidScope:
            return SourceControlDiagnostic(code: "invalid-scope", summary: "所选目录无法扫描。", recovery: "请选择一个存在的仓库或工作目录。")
        case .notRepository:
            return SourceControlDiagnostic(code: "not-repository", summary: "所选目录不是 Git 仓库。", recovery: "请选择包含 .git 的仓库目录。")
        case .gitUnavailable:
            return SourceControlDiagnostic(code: "git-unavailable", summary: "找不到可用的 Git。", recovery: "请确认已安装 Git，并在终端运行 git --version。")
        case .commandFailed:
            return SourceControlDiagnostic(code: "command-failed", summary: "Git 操作未完成。", recovery: "请检查仓库状态和远端配置后重试。")
        case .staleSnapshot:
            return SourceControlDiagnostic(code: "stale-snapshot", summary: "扫描后仓库有变化，已停止更新。", recovery: "重新扫描后再更新。")
        case .operationInProgress:
            return SourceControlDiagnostic(code: "operation-in-progress", summary: "已有 Git 操作正在进行。", recovery: "请等待当前操作结束后重试。")
        case .timedOut:
            return SourceControlDiagnostic(code: "timed-out", summary: "操作超时。", recovery: "请检查网络或仓库状态后重试。")
        case .cancelled:
            return SourceControlDiagnostic(code: "cancelled", summary: "操作已取消。", recovery: "可以从当前页面重新开始。")
        }
    }
}
