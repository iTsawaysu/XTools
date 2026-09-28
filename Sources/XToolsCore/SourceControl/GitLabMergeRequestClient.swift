import Foundation

public struct GitLabHTTPResponse: Sendable, Equatable {
    public let statusCode: Int
    public let data: Data

    public init(statusCode: Int, data: Data = Data()) {
        self.statusCode = statusCode
        self.data = data
    }
}

public protocol GitLabHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> GitLabHTTPResponse
}

public struct URLSessionGitLabHTTPTransport: GitLabHTTPTransport, Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> GitLabHTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SourceControlError.invalidResponse
        }
        return GitLabHTTPResponse(statusCode: httpResponse.statusCode, data: data)
    }
}

public struct GitLabMergeRequestInput: Sendable, Equatable {
    public let gitLabURL: URL
    public let projectPath: String
    public let sourceBranch: String
    public let targetBranch: String
    public let title: String
    public let description: String

    public init(
        gitLabURL: URL,
        projectPath: String,
        sourceBranch: String,
        targetBranch: String,
        title: String,
        description: String = ""
    ) {
        self.gitLabURL = gitLabURL
        self.projectPath = projectPath
        self.sourceBranch = sourceBranch
        self.targetBranch = targetBranch
        self.title = title
        self.description = description
    }
}

public struct GitLabMergeRequest: Codable, Sendable, Equatable, Identifiable {
    public let iid: Int
    public let title: String?
    public let sourceBranch: String?
    public let targetBranch: String?
    public let webURL: URL?

    public var id: Int { iid }

    public init(iid: Int, title: String? = nil, sourceBranch: String? = nil, targetBranch: String? = nil, webURL: URL? = nil) {
        self.iid = iid
        self.title = title
        self.sourceBranch = sourceBranch
        self.targetBranch = targetBranch
        self.webURL = webURL
    }

    enum CodingKeys: String, CodingKey {
        case iid
        case title
        case sourceBranch = "source_branch"
        case targetBranch = "target_branch"
        case webURL = "web_url"
    }
}

public enum GitLabPreflightResult: Sendable, Equatable {
    case ready
    case duplicate(GitLabMergeRequest)
}

public struct GitLabMergeRequestClient: Sendable {
    private let transport: any GitLabHTTPTransport
    private let requestTimeout: Duration

    public init(
        transport: any GitLabHTTPTransport = URLSessionGitLabHTTPTransport(),
        requestTimeout: Duration = .seconds(30)
    ) {
        self.transport = transport
        self.requestTimeout = requestTimeout
    }

    public func preflight(
        _ input: GitLabMergeRequestInput,
        token: String
    ) async throws -> GitLabPreflightResult {
        try validate(input)
        try validateToken(token)
        try await checkProject(input, token: token)
        try await checkBranch(input.sourceBranch, input: input, token: token)
        try await checkBranch(input.targetBranch, input: input, token: token)
        let existing = try await openMergeRequests(input, token: token)
        return existing.first.map(GitLabPreflightResult.duplicate) ?? .ready
    }

    public func create(
        _ input: GitLabMergeRequestInput,
        token: String
    ) async throws -> GitLabMergeRequest {
        try validate(input)
        try validateToken(token)
        let request = try makeRequest(input, token: token, method: "POST", endpoint: "merge_requests")
        do {
            let response = try await send(request)
            guard (200..<300).contains(response.statusCode) else {
                if response.statusCode == 409 { throw SourceControlError.mergeRequestAlreadyExists }
                throw SourceControlError.httpStatus(response.statusCode)
            }
            return try decodeMergeRequest(response.data)
        } catch let error as URLError where error.code == .timedOut {
            // A timeout may happen after GitLab accepted the POST. Reconcile by
            // querying the same source/target pair before surfacing the failure.
            if let existing = try? await openMergeRequests(input, token: token).first {
                return existing
            }
            throw SourceControlError.timedOut
        }
    }

    private func checkProject(_ input: GitLabMergeRequestInput, token: String) async throws {
        let request = try makeRequest(input, token: token, method: "GET", endpoint: "")
        let response = try await send(request)
        guard response.statusCode == 200 else { throw SourceControlError.httpStatus(response.statusCode) }
    }

    private func checkBranch(_ branch: String, input: GitLabMergeRequestInput, token: String) async throws {
        let request = try makeRequest(input, token: token, method: "GET", endpoint: "repository/branches/\(encodePath(branch))")
        let response = try await send(request)
        guard response.statusCode == 200 else { throw SourceControlError.httpStatus(response.statusCode) }
    }

    private func openMergeRequests(_ input: GitLabMergeRequestInput, token: String) async throws -> [GitLabMergeRequest] {
        var request = try makeRequest(input, token: token, method: "GET", endpoint: "merge_requests")
        guard let requestURL = request.url,
              var components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false) else {
            throw SourceControlError.invalidGitLabURL
        }
        components.queryItems = [
            URLQueryItem(name: "state", value: "opened"),
            URLQueryItem(name: "source_branch", value: input.sourceBranch),
            URLQueryItem(name: "target_branch", value: input.targetBranch),
            URLQueryItem(name: "per_page", value: "100"),
        ]
        request.url = components.url
        let response = try await send(request)
        guard response.statusCode == 200 else { throw SourceControlError.httpStatus(response.statusCode) }
        do {
            return try JSONDecoder().decode([GitLabMergeRequest].self, from: response.data)
        } catch {
            throw SourceControlError.invalidResponse
        }
    }

    private func makeRequest(
        _ input: GitLabMergeRequestInput,
        token: String,
        method: String,
        endpoint: String
    ) throws -> URLRequest {
        let base = try validatedBaseURL(input.gitLabURL)
        let encodedProject = input.projectPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { encodePath(String($0)) }
            .joined(separator: "%2F")
        let suffix = endpoint.isEmpty ? "" : "/\(endpoint)"
        guard let url = URL(string: "\(base.absoluteString)/api/v4/projects/\(encodedProject)\(suffix)") else {
            throw SourceControlError.invalidGitLabURL
        }
        var request = URLRequest(url: url, timeoutInterval: requestTimeout.timeInterval)
        request.httpMethod = method
        request.setValue(token.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "PRIVATE-TOKEN")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if method == "POST" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "source_branch": input.sourceBranch,
                "target_branch": input.targetBranch,
                "title": input.title,
                "description": input.description,
            ], options: [])
        }
        return request
    }

    private func send(_ request: URLRequest) async throws -> GitLabHTTPResponse {
        try Task.checkCancellation()
        return try await transport.send(request)
    }

    private func validate(_ input: GitLabMergeRequestInput) throws {
        _ = try validatedBaseURL(input.gitLabURL)
        let path = input.projectPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, !path.split(separator: "/", omittingEmptySubsequences: true).isEmpty else { throw SourceControlError.invalidProjectPath }
        guard !input.sourceBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !input.targetBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SourceControlError.invalidBranch
        }
        guard !input.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SourceControlError.invalidTitle
        }
    }

    private func validateToken(_ token: String) throws {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SourceControlError.invalidToken
        }
    }

    private func validatedBaseURL(_ value: URL) throws -> URL {
        guard let scheme = value.scheme?.lowercased(), scheme == "https", value.host != nil else {
            if value.scheme?.lowercased() == "http" { throw SourceControlError.insecureGitLabURL }
            throw SourceControlError.invalidGitLabURL
        }
        guard value.user == nil, value.password == nil, value.query == nil, value.fragment == nil else {
            throw SourceControlError.invalidGitLabURL
        }
        guard let normalized = URL(string: value.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) else {
            throw SourceControlError.invalidGitLabURL
        }
        return normalized
    }

    private func decodeMergeRequest(_ data: Data) throws -> GitLabMergeRequest {
        do { return try JSONDecoder().decode(GitLabMergeRequest.self, from: data) }
        catch { throw SourceControlError.invalidResponse }
    }
}

private func encodePath(_ value: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
