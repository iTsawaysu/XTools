import Foundation
import XCTest
@testable import XToolsCore

final class SourceControlDiscoveryTests: XCTestCase {
    func testGitLabDiscoveryReturnsAccessibleProjectsWithTokenHeader() async throws {
        let transport = MockDiscoveryTransport { request in
            XCTAssertEqual(request.url?.host, "gitlab.example.com")
            XCTAssertEqual(request.url?.path, "/api/v4/projects")
            XCTAssertEqual(request.value(forHTTPHeaderField: "PRIVATE-TOKEN"), "glpat-test")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            let query = request.url?.query ?? ""
            XCTAssertTrue(query.contains("membership=true"))
            XCTAssertTrue(query.contains("simple=true"))
            XCTAssertTrue(query.contains("page=1"))
            let body = """
            [
              {"name": "Mobile App", "path_with_namespace": "acme/mobile", "default_branch": "main", "web_url": "https://gitlab.example.com/acme/mobile"},
              {"name": "Web", "path_with_namespace": "acme/web", "default_branch": "develop", "web_url": "https://gitlab.example.com/acme/web"}
            ]
            """
            return GitLabHTTPResponse(statusCode: 200, data: Data(body.utf8))
        }

        let result = try await RemoteRepositoryDiscoveryClient(transport: transport)
            .discover(hostURL: URL(string: "https://gitlab.example.com")!, token: "glpat-test")

        XCTAssertEqual(result.service, .gitlab)
        XCTAssertEqual(result.projects.map(\.pathWithNamespace), ["acme/mobile", "acme/web"])
        XCTAssertEqual(result.projects.first?.defaultBranch, "main")
        XCTAssertEqual(result.projects.first?.id, "gitlab/acme/mobile")
    }

    func testGitLabDiscoveryFollowsFullPages() async throws {
        // 每页 100 条上限：第一页返回满页时才继续翻页，第二页不满则停止。
        let transport = MockDiscoveryTransport { request in
            let query = request.url?.query ?? ""
            let isSecondPage = query.contains("page=2")
            let count = isSecondPage ? 2 : 100
            let projects = (0..<count).map { index in
                "{\"name\": \"p\(index)\", \"path_with_namespace\": \"acme/p\(index)\", \"default_branch\": \"main\"}"
            }
            return GitLabHTTPResponse(statusCode: 200, data: Data("[\(projects.joined(separator: ","))]".utf8))
        }

        let result = try await RemoteRepositoryDiscoveryClient(transport: transport)
            .discover(hostURL: URL(string: "https://gitlab.example.com")!, token: "tok")

        XCTAssertEqual(result.projects.count, 102)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
    }

    func testGitHubHostRoutesToAPIGitHubComWithBearerAuth() async throws {
        let transport = MockDiscoveryTransport { request in
            XCTAssertEqual(request.url?.absoluteString.hasPrefix("https://api.github.com/user/repos"), true)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer ghp-test")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
            XCTAssertTrue(request.url?.query?.contains("affiliation=owner,collaborator") ?? false)
            let body = """
            [
              {"name": "cli", "full_name": "acme/cli", "default_branch": "main", "html_url": "https://github.com/acme/cli"}
            ]
            """
            return GitLabHTTPResponse(statusCode: 200, data: Data(body.utf8))
        }

        let result = try await RemoteRepositoryDiscoveryClient(transport: transport)
            .discover(hostURL: URL(string: "https://github.com")!, token: "ghp-test")

        XCTAssertEqual(result.service, .github)
        XCTAssertEqual(result.projects.first?.pathWithNamespace, "acme/cli")
        XCTAssertEqual(result.projects.first?.id, "github/acme/cli")
    }

    func testPlainHTTPHostIsRejectedBeforeAnyRequest() async throws {
        let transport = MockDiscoveryTransport { _ in
            GitLabHTTPResponse(statusCode: 200, data: Data("[]".utf8))
        }

        do {
            _ = try await RemoteRepositoryDiscoveryClient(transport: transport)
                .discover(hostURL: URL(string: "http://gitlab.example.com")!, token: "tok")
            XCTFail("Expected insecure URL rejection")
        } catch let error as SourceControlError {
            XCTAssertEqual(error, .insecureGitLabURL)
        }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testEmptyTokenIsRejectedBeforeAnyRequest() async throws {
        let transport = MockDiscoveryTransport { _ in
            GitLabHTTPResponse(statusCode: 200, data: Data("[]".utf8))
        }

        do {
            _ = try await RemoteRepositoryDiscoveryClient(transport: transport)
                .discover(hostURL: URL(string: "https://gitlab.example.com")!, token: "   ")
            XCTFail("Expected empty token rejection")
        } catch let error as SourceControlError {
            XCTAssertEqual(error, .invalidToken)
        }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testHTTPErrorSurfacesHTTPStatusDiagnostic() async throws {
        let transport = MockDiscoveryTransport { _ in
            GitLabHTTPResponse(statusCode: 401, data: Data())
        }

        do {
            _ = try await RemoteRepositoryDiscoveryClient(transport: transport)
                .discover(hostURL: URL(string: "https://gitlab.example.com")!, token: "tok")
            XCTFail("Expected 401 to surface as httpStatus")
        } catch let error as SourceControlError {
            XCTAssertEqual(error, .httpStatus(401))
        }
    }
}

private actor MockDiscoveryTransport: GitLabHTTPTransport {
    private let handler: @Sendable (URLRequest) throws -> GitLabHTTPResponse
    private(set) var requests: [URLRequest] = []

    init(handler: @escaping @Sendable (URLRequest) throws -> GitLabHTTPResponse) {
        self.handler = handler
    }

    func send(_ request: URLRequest) async throws -> GitLabHTTPResponse {
        requests.append(request)
        return try handler(request)
    }
}
