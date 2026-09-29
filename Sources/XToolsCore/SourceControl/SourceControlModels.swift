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
    case invalidGitLabURL
    case insecureGitLabURL
    case invalidProjectPath
    case invalidBranch
    case invalidTitle
    case invalidToken
    case httpStatus(Int)
    case invalidResponse
    case mergeRequestAlreadyExists
    case pullRequestUnsupported
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
        case .invalidGitLabURL:
            return SourceControlDiagnostic(code: "invalid-gitlab-url", summary: "GitLab 地址无效。", recovery: "请输入包含主机名的 GitLab HTTPS 地址。")
        case .insecureGitLabURL:
            return SourceControlDiagnostic(code: "insecure-gitlab-url", summary: "GitLab 地址必须使用 HTTPS。", recovery: "请改用 https:// 开头的地址。")
        case .invalidProjectPath:
            return SourceControlDiagnostic(code: "invalid-project", summary: "项目路径无效。", recovery: "请输入 GitLab 项目的完整路径。")
        case .invalidBranch:
            return SourceControlDiagnostic(code: "invalid-branch", summary: "分支名称不能为空。", recovery: "请填写源分支和目标分支。")
        case .invalidTitle:
            return SourceControlDiagnostic(code: "invalid-title", summary: "Merge Request 标题不能为空。", recovery: "请填写一个简短明确的标题。")
        case .invalidToken:
            return SourceControlDiagnostic(code: "invalid-token", summary: "GitLab Token 不能为空。", recovery: "请输入有权限访问项目并创建 Merge Request 的 Token。")
        case let .httpStatus(status):
            return SourceControlDiagnostic(code: "http-status", summary: "GitLab 请求未成功。", recovery: "请检查地址、Token 和项目权限后重试。", statusCode: status)
        case .invalidResponse:
            return SourceControlDiagnostic(code: "invalid-response", summary: "GitLab 返回的数据无法识别。", recovery: "请确认服务器版本和网络状态后重试。")
        case .mergeRequestAlreadyExists:
            return SourceControlDiagnostic(code: "duplicate-merge-request", summary: "已经存在相同的开放 Merge Request。", recovery: "请打开现有请求，或修改源分支后再创建。")
        case .pullRequestUnsupported:
            return SourceControlDiagnostic(code: "pull-request-unsupported", summary: "GitHub 项目暂不支持创建 Pull Request。", recovery: "当前仅支持 GitLab Merge Request；GitHub 项目可以先扫描和选择，创建能力在后续版本提供。")
        }
    }
}
