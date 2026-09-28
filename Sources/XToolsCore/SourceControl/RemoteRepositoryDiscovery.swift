import Foundation

/// Which hosted service a user-entered remote points at. Detection is
/// host-based: `github.com` (and subdomains) are GitHub, everything else is
/// treated as GitLab — the common self-hosted case for this tool.
public enum RemoteRepositoryService: String, Sendable, Equatable, CaseIterable {
    case gitlab
    case github

    public static func detect(host: String?) -> RemoteRepositoryService {
        guard let host else { return .gitlab }
        let lowered = host.lowercased()
        if lowered == "github.com" || lowered.hasSuffix(".github.com") { return .github }
        return .gitlab
    }
}

/// One accessible remote project returned by discovery.
public struct RemoteRepositorySummary: Sendable, Equatable, Identifiable {
    public let service: RemoteRepositoryService
    public let name: String
    /// GitLab `path_with_namespace` / GitHub `full_name` — the exact form the
    /// merge-request form expects in its project path field.
    public let pathWithNamespace: String
    public let defaultBranch: String?
    public let webURL: URL?

    public var id: String { "\(service.rawValue)/\(pathWithNamespace)" }

    public init(
        service: RemoteRepositoryService,
        name: String,
        pathWithNamespace: String,
        defaultBranch: String? = nil,
        webURL: URL? = nil
    ) {
        self.service = service
        self.name = name
        self.pathWithNamespace = pathWithNamespace
        self.defaultBranch = defaultBranch
        self.webURL = webURL
    }
}

public struct RemoteRepositoryDiscoveryResult: Sendable, Equatable {
    public let service: RemoteRepositoryService
    public let projects: [RemoteRepositorySummary]

    public init(service: RemoteRepositoryService, projects: [RemoteRepositorySummary]) {
        self.service = service
        self.projects = projects
    }
}

/// Discovers the projects a token can see on a GitLab or GitHub host, so the
/// merge-request form can be filled by picking instead of typing. Reuses the
/// merge-request client's HTTP transport; tokens travel only in request
/// headers and are never persisted.
public struct RemoteRepositoryDiscoveryClient: Sendable {
    private let transport: any GitLabHTTPTransport
    private let requestTimeout: Duration
    /// Upper bound on page requests so a misbehaving host cannot loop forever.
    private static let maximumPages = 20
    private static let pageSize = 100

    public init(
        transport: any GitLabHTTPTransport = URLSessionGitLabHTTPTransport(),
        requestTimeout: Duration = .seconds(30)
    ) {
        self.transport = transport
        self.requestTimeout = requestTimeout
    }

    public func discover(hostURL: URL, token: String) async throws -> RemoteRepositoryDiscoveryResult {
        try Task.checkCancellation()
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else { throw SourceControlError.invalidToken }
        let base = try validatedHostURL(hostURL)
        guard let host = base.host else { throw SourceControlError.invalidGitLabURL }
        switch RemoteRepositoryService.detect(host: host) {
        case .gitlab:
            let projects = try await discoverGitLab(base: base, token: trimmedToken)
            return RemoteRepositoryDiscoveryResult(service: .gitlab, projects: projects)
        case .github:
            let projects = try await discoverGitHub(base: base, token: trimmedToken)
            return RemoteRepositoryDiscoveryResult(service: .github, projects: projects)
        }
    }

    // MARK: - GitLab

    private func discoverGitLab(base: URL, token: String) async throws -> [RemoteRepositorySummary] {
        var projects: [RemoteRepositorySummary] = []
        for page in 1...Self.maximumPages {
            try Task.checkCancellation()
            guard var components = URLComponents(url: base.appendingPathComponent("api/v4/projects"), resolvingAgainstBaseURL: false) else {
                throw SourceControlError.invalidGitLabURL
            }
            components.queryItems = [
                URLQueryItem(name: "membership", value: "true"),
                URLQueryItem(name: "simple", value: "true"),
                URLQueryItem(name: "order_by", value: "last_activity_at"),
                URLQueryItem(name: "sort", value: "desc"),
                URLQueryItem(name: "per_page", value: String(Self.pageSize)),
                URLQueryItem(name: "page", value: String(page)),
            ]
            guard let url = components.url else { throw SourceControlError.invalidGitLabURL }
            var request = URLRequest(url: url, timeoutInterval: requestTimeout.timeInterval)
            request.httpMethod = "GET"
            request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let response = try await send(request)
            guard response.statusCode == 200 else { throw SourceControlError.httpStatus(response.statusCode) }
            let payload = try decode([GitLabProjectPayload].self, from: response.data)
            projects.append(contentsOf: payload.map { $0.summary(service: .gitlab) })
            if payload.count < Self.pageSize { break }
        }
        return projects
    }

    // MARK: - GitHub

    private func discoverGitHub(base: URL, token: String) async throws -> [RemoteRepositorySummary] {
        // github.com serves its API from api.github.com; GitHub Enterprise
        // keeps a versioned path on the entered host.
        let apiBase: URL
        if base.host?.lowercased() == "github.com" {
            apiBase = URL(string: "https://api.github.com") ?? base
        } else {
            apiBase = base.appendingPathComponent("api/v3")
        }
        var projects: [RemoteRepositorySummary] = []
        for page in 1...Self.maximumPages {
            try Task.checkCancellation()
            guard var components = URLComponents(url: apiBase.appendingPathComponent("user/repos"), resolvingAgainstBaseURL: false) else {
                throw SourceControlError.invalidGitLabURL
            }
            components.queryItems = [
                URLQueryItem(name: "affiliation", value: "owner,collaborator"),
                URLQueryItem(name: "sort", value: "updated"),
                URLQueryItem(name: "per_page", value: String(Self.pageSize)),
                URLQueryItem(name: "page", value: String(page)),
            ]
            guard let url = components.url else { throw SourceControlError.invalidGitLabURL }
            var request = URLRequest(url: url, timeoutInterval: requestTimeout.timeInterval)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let response = try await send(request)
            guard response.statusCode == 200 else { throw SourceControlError.httpStatus(response.statusCode) }
            let payload = try decode([GitHubRepositoryPayload].self, from: response.data)
            projects.append(contentsOf: payload.map { $0.summary(service: .github) })
            if payload.count < Self.pageSize { break }
        }
        return projects
    }

    // MARK: - Shared plumbing

    private func send(_ request: URLRequest) async throws -> GitLabHTTPResponse {
        try Task.checkCancellation()
        return try await transport.send(request)
    }

    private func decode<Payload: Decodable>(_ type: Payload.Type, from data: Data) throws -> Payload {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw SourceControlError.invalidResponse }
    }

    private func validatedHostURL(_ value: URL) throws -> URL {
        guard let scheme = value.scheme?.lowercased(), scheme == "https", value.host != nil else {
            if value.scheme?.lowercased() == "http" { throw SourceControlError.insecureGitLabURL }
            throw SourceControlError.invalidGitLabURL
        }
        guard value.user == nil, value.password == nil, value.fragment == nil else {
            throw SourceControlError.invalidGitLabURL
        }
        // A pasted deep link (…/group/project) still discovers from the host.
        var components = URLComponents()
        components.scheme = scheme
        components.host = value.host
        components.port = value.port
        guard let normalized = components.url else {
            throw SourceControlError.invalidGitLabURL
        }
        return normalized
    }
}

private struct GitLabProjectPayload: Decodable {
    let name: String?
    let path_with_namespace: String?
    let default_branch: String?
    let web_url: String?

    func summary(service: RemoteRepositoryService) -> RemoteRepositorySummary {
        RemoteRepositorySummary(
            service: service,
            name: name ?? path_with_namespace ?? "",
            pathWithNamespace: path_with_namespace ?? "",
            defaultBranch: default_branch,
            webURL: web_url.flatMap(URL.init(string:))
        )
    }
}

private struct GitHubRepositoryPayload: Decodable {
    let name: String?
    let full_name: String?
    let default_branch: String?
    let html_url: String?

    func summary(service: RemoteRepositoryService) -> RemoteRepositorySummary {
        RemoteRepositorySummary(
            service: service,
            name: name ?? full_name ?? "",
            pathWithNamespace: full_name ?? "",
            defaultBranch: default_branch,
            webURL: html_url.flatMap(URL.init(string:))
        )
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
