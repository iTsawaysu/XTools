import Foundation
import Testing
@testable import XToolsCore

@Suite(.serialized)
struct URLFetchSecurityTests {
    @Test func classifiesBinaryIPAddresses() {
        let blocked = [
            "0:0:0:0:0:0:0:1", "::", "fe90::1", "febf::1",
            "ff02::1", "2002:c0a8:101::1", "2001:0::1",
            "::ffff:127.0.0.1", "::ffff:192.168.1.1", "[fe80::1]",
            "192.0.0.1", "198.18.0.1", "224.0.0.1"
        ]
        for host in blocked {
            #expect(URLFetchHostPolicy.evaluate(host: host) == .deny, "\(host)")
        }
        #expect(URLFetchHostPolicy.evaluate(host: "2606:4700:4700::1111") == .allow)
        #expect(URLFetchHostPolicy.evaluate(host: "::ffff:8.8.8.8") == .allow)
    }

    @Test func separatesDNSFailureFromPrivateAnswers() async {
        let failed = await URLFetchHostPolicy.evaluateResolvedHost(
            "example.com", timeout: 1, resolver: { _, _ in nil }
        )
        let empty = await URLFetchHostPolicy.evaluateResolvedHost(
            "example.com", timeout: 1, resolver: { _, _ in [] }
        )
        let privateAnswer = await URLFetchHostPolicy.evaluateResolvedHost(
            "example.com", timeout: 1,
            resolver: { _, _ in ["93.184.216.34", "192.168.1.5"] }
        )
        let publicAnswer = await URLFetchHostPolicy.evaluateResolvedHost(
            "example.com", timeout: 1,
            resolver: { _, _ in ["93.184.216.34", "2606:4700:4700::1111"] }
        )
        #expect(failed == .unavailable)
        #expect(empty == .unavailable)
        #expect(privateAnswer == .deny)
        #expect(publicAnswer == .allow)
    }

    @Test func cancellationStopsWaitingForDNS() async {
        let paused = PausedDNSLookup()
        defer { paused.release.signal() }
        let pending = Task {
            await URLFetchHostPolicy.resolveAddresses(
                "example.com", timeout: 5,
                lookup: { _ in
                    paused.started.signal()
                    paused.release.wait()
                    return ["93.184.216.34"]
                }
            )
        }
        let started = await Task.detached { paused.waitUntilStarted() }.value
        #expect(started)
        guard started else {
            pending.cancel()
            return
        }
        pending.cancel()
        #expect(await pending.value == nil)
    }

    @Test func blocksLiteralBeforeURLProtocolStarts() async throws {
        RecordingURLProtocol.state.configure(data: Data("<p>ok</p>".utf8), finish: true)
        let client = makeClient(resolver: { _, _ in ["93.184.216.34"] })
        let request = URLRequest(url: try #require(URL(string: "http://127.0.0.1/admin")))
        await #expect(throws: HTMLToMarkdownURLFetchError.privateNetworkDisallowed) {
            _ = try await client.fetchData(for: request, byteLimit: 100)
        }
        #expect(RecordingURLProtocol.state.started == 0)
    }

    @Test func mapsDNSFailureWithoutStartingTransport() async throws {
        RecordingURLProtocol.state.configure(data: Data("<p>ok</p>".utf8), finish: true)
        let client = makeClient(resolver: { _, _ in nil })
        let request = URLRequest(url: try #require(URL(string: "https://example.com/")))
        await #expect(throws: HTMLToMarkdownURLFetchError.requestFailed) {
            _ = try await client.fetchData(for: request, byteLimit: 100)
        }
        #expect(RecordingURLProtocol.state.started == 0)
    }

    @Test func allowsPublicTransportAndCancelsOversizedStream() async throws {
        let request = URLRequest(url: try #require(URL(string: "https://example.com/")))
        let client = makeClient(resolver: { _, _ in ["93.184.216.34"] })
        RecordingURLProtocol.state.configure(data: Data("<p>ok</p>".utf8), finish: true)
        let (data, _) = try await client.fetchData(for: request, byteLimit: 100)
        #expect(String(decoding: data, as: UTF8.self) == "<p>ok</p>")
        #expect(RecordingURLProtocol.state.started == 1)

        RecordingURLProtocol.state.configure(data: Data(repeating: 65, count: 64), finish: false)
        await #expect(throws: HTMLToMarkdownURLFetchError.responseTooLarge(3)) {
            _ = try await client.fetchData(for: request, byteLimit: 3)
        }
        #expect(RecordingURLProtocol.state.started == 1)
        for _ in 0..<20 where RecordingURLProtocol.state.stopped == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(RecordingURLProtocol.state.stopped > 0)
    }

    @Test func redirectDelegateChecksDestinationBeforeFollowing() async throws {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let source = try #require(URL(string: "https://example.com/start"))
        let task = session.dataTask(with: source)
        let response = try #require(HTTPURLResponse(
            url: source, statusCode: 302, httpVersion: nil,
            headerFields: ["Location": "https://next.example.com/"]
        ))

        let publicDelegate = HTMLToMarkdownURLSessionDelegate(
            resolver: { _, _ in ["93.184.216.34"] }, timeout: 1
        )
        let publicURL = try #require(URL(string: "https://next.example.com/"))
        let accepted = await redirect(
            publicDelegate, session: session, task: task, response: response,
            request: URLRequest(url: publicURL)
        )
        #expect(accepted?.url == publicURL)
        #expect(publicDelegate.rejection == nil)

        let privateDelegate = HTMLToMarkdownURLSessionDelegate(
            resolver: { _, _ in ["10.0.0.2"] }, timeout: 1
        )
        let rejected = await redirect(
            privateDelegate, session: session, task: task, response: response,
            request: URLRequest(url: publicURL)
        )
        #expect(rejected == nil)
        #expect(privateDelegate.rejection == .privateNetworkDisallowed)

        let literal = try #require(URL(string: "http://127.0.0.1/admin"))
        let literalRejected = await redirect(
            publicDelegate, session: session, task: task, response: response,
            request: URLRequest(url: literal)
        )
        #expect(literalRejected == nil)
        #expect(publicDelegate.rejection == .privateNetworkDisallowed)

        let limitedDelegate = HTMLToMarkdownURLSessionDelegate(
            resolver: { _, _ in ["93.184.216.34"] }, timeout: 1
        )
        for _ in 0..<5 {
            let next = await redirect(
                limitedDelegate, session: session, task: task, response: response,
                request: URLRequest(url: publicURL)
            )
            #expect(next?.url == publicURL)
        }
        let sixth = await redirect(
            limitedDelegate, session: session, task: task, response: response,
            request: URLRequest(url: publicURL)
        )
        #expect(sixth == nil)
        #expect(limitedDelegate.rejection == .requestFailed)
    }

    private func makeClient(
        resolver: @escaping URLFetchHostPolicy.Resolver
    ) -> LiveHTMLToMarkdownURLFetchClient {
        return LiveHTMLToMarkdownURLFetchClient(
            resolver: resolver,
            configurationFactory: {
                let configuration = URLSessionConfiguration.ephemeral
                configuration.protocolClasses = [RecordingURLProtocol.self]
                return configuration
            }
        )
    }

    private func redirect(
        _ delegate: HTMLToMarkdownURLSessionDelegate,
        session: URLSession,
        task: URLSessionTask,
        response: HTTPURLResponse,
        request: URLRequest
    ) async -> URLRequest? {
        await delegate.urlSession(
            session, task: task, willPerformHTTPRedirection: response,
            newRequest: request
        )
    }
}

private final class PausedDNSLookup: @unchecked Sendable {
    let started = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)

    func waitUntilStarted() -> Bool {
        started.wait(timeout: .now() + 2) == .success
    }
}

private final class RecordingURLProtocol: URLProtocol {
    static let state = RecordingURLProtocolState()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.state.recordStart()
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url, statusCode: 200, httpVersion: nil,
                  headerFields: ["Content-Type": "text/html"]
              ) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.state.data)
        if Self.state.shouldFinish { client?.urlProtocolDidFinishLoading(self) }
    }

    override func stopLoading() { Self.state.recordStop() }
}

private final class RecordingURLProtocolState: @unchecked Sendable {
    private let lock = NSLock()
    private var starts = 0
    private var stops = 0
    private var body = Data()
    private var finish = true

    var started: Int { lock.withLock { starts } }
    var stopped: Int { lock.withLock { stops } }
    var data: Data { lock.withLock { body } }
    var shouldFinish: Bool { lock.withLock { finish } }

    func configure(data: Data, finish: Bool) {
        lock.withLock {
            starts = 0
            stops = 0
            body = data
            self.finish = finish
        }
    }

    func recordStart() { lock.withLock { starts += 1 } }
    func recordStop() { lock.withLock { stops += 1 } }
}
