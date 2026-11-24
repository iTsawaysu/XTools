import Foundation

public struct HTMLToMarkdownFetchedDocument: Equatable, Sendable {
    public let html: String
    public let responseURL: URL

    public init(html: String, responseURL: URL) {
        self.html = html
        self.responseURL = responseURL
    }
}

public struct HTMLToMarkdownURLFetchOptions: Equatable, Sendable {
    public static let defaultTimeout: TimeInterval = 15
    public static let defaultResponseBodyByteLimit = 5 * 1024 * 1024

    public var timeout: TimeInterval
    public var responseBodyByteLimit: Int

    public init(
        timeout: TimeInterval = Self.defaultTimeout,
        responseBodyByteLimit: Int = Self.defaultResponseBodyByteLimit
    ) {
        self.timeout = timeout
        self.responseBodyByteLimit = responseBodyByteLimit
    }
}

public enum HTMLToMarkdownURLFetchError: Error, Equatable, Sendable {
    case emptyURL
    case invalidURL
    case unsupportedScheme(String)
    case privateNetworkDisallowed
    case requestFailed
    case nonHTTPResponse
    case unacceptableStatusCode(Int)
    case unsupportedContentType
    case responseTooLarge(Int)
    case emptyResponse
    case undecodableText
}

public protocol HTMLToMarkdownURLFetchClient: Sendable {
    func fetchData(
        for request: URLRequest,
        byteLimit: Int
    ) async throws -> (Data, URLResponse)
}

public struct LiveHTMLToMarkdownURLFetchClient: HTMLToMarkdownURLFetchClient {
    private let resolver: URLFetchHostPolicy.Resolver
    private let configurationFactory: @Sendable () -> URLSessionConfiguration

    public init() {
        resolver = { host, timeout in
            await URLFetchHostPolicy.resolveAddresses(host, timeout: timeout)
        }
        configurationFactory = { URLSessionConfiguration.ephemeral }
    }

    init(
        resolver: @escaping URLFetchHostPolicy.Resolver,
        configurationFactory: @escaping @Sendable () -> URLSessionConfiguration
            = { URLSessionConfiguration.ephemeral }
    ) {
        self.resolver = resolver
        self.configurationFactory = configurationFactory
    }

    public func fetchData(
        for request: URLRequest,
        byteLimit: Int
    ) async throws -> (Data, URLResponse) {
        guard let url = request.url else {
            throw HTMLToMarkdownURLFetchError.invalidURL
        }
        let host = try HTMLToMarkdownURLFetchService.validateDestination(url)
        try Task.checkCancellation()
        let destination = await URLFetchHostPolicy.evaluateResolvedHost(
            host,
            timeout: request.timeoutInterval,
            resolver: resolver
        )
        try Task.checkCancellation()
        switch destination {
        case .allow: break
        case .deny: throw HTMLToMarkdownURLFetchError.privateNetworkDisallowed
        case .unavailable: throw HTMLToMarkdownURLFetchError.requestFailed
        }
        try Task.checkCancellation()

        let configuration = configurationFactory()
        // Fetches are explicit public-resource reads, with no shared browser
        // credentials or cookies. The caller owns any bounded in-memory cache.
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = request.timeoutInterval
        configuration.timeoutIntervalForResource = request.timeoutInterval

        let delegate = HTMLToMarkdownURLSessionDelegate(
            resolver: resolver,
            timeout: request.timeoutInterval,
            byteLimit: byteLimit
        )
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let response = try await delegate.fetch(session.dataTask(with: request))
        try Task.checkCancellation()
        return response
    }
}

/// Each fetch owns one session and one data task. URLSession delivers chunks;
/// the lock also protects state from the caller's cancellation handler.
final class HTMLToMarkdownURLSessionDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private typealias Completion = CheckedContinuation<(Data, URLResponse), any Error>
    private static let maximumRedirects = 5
    private let resolver: URLFetchHostPolicy.Resolver
    private let timeout: TimeInterval
    private let byteLimit: Int
    private let lock = NSLock()
    private var redirectCount = 0
    private var failure: HTMLToMarkdownURLFetchError?
    private var body = Data()
    private var completion: Completion?
    private var cancelled = false

    init(
        resolver: @escaping URLFetchHostPolicy.Resolver,
        timeout: TimeInterval,
        byteLimit: Int = HTMLToMarkdownURLFetchOptions.defaultResponseBodyByteLimit
    ) {
        self.resolver = resolver
        self.timeout = timeout
        self.byteLimit = byteLimit
    }

    var rejection: HTMLToMarkdownURLFetchError? {
        lock.withLock { failure }
    }

    func fetch(_ task: URLSessionDataTask) async throws -> (Data, URLResponse) {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { completion in
                let shouldStart = lock.withLock {
                    guard !cancelled else { return false }
                    self.completion = completion
                    return true
                }
                if shouldStart {
                    task.resume()
                } else {
                    completion.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            let completion = self.lock.withLock {
                self.cancelled = true
                self.body = Data()
                return self.takeCompletion()
            }
            task.cancel()
            completion?.resume(throwing: CancellationError())
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        completionHandler(rejection == nil ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let isOverLimit = lock.withLock {
            guard completion != nil, failure == nil else { return false }
            guard data.count <= max(0, byteLimit) - body.count else {
                failure = .responseTooLarge(byteLimit)
                return true
            }
            body.append(data)
            return false
        }
        if isOverLimit { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let outcome: (Completion, Result<(Data, URLResponse), any Error>)? = lock.withLock {
            guard let completion = takeCompletion() else { return nil }
            defer { body = Data() }
            if let failure { return (completion, .failure(failure)) }
            if let error { return (completion, .failure(error)) }
            guard let response = task.response else {
                return (completion, .failure(HTMLToMarkdownURLFetchError.nonHTTPResponse))
            }
            return (completion, .success((body, response)))
        }
        if let (completion, result) = outcome { completion.resume(with: result) }
    }

    private func takeCompletion() -> Completion? {
        defer { completion = nil }
        return completion
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        let withinLimit = lock.withLock { () -> Bool in
            redirectCount += 1
            return redirectCount <= Self.maximumRedirects
        }
        guard withinLimit else {
            return reject(.requestFailed)
        }
        guard let url = request.url else {
            return reject(.invalidURL)
        }
        let host: String
        do {
            host = try HTMLToMarkdownURLFetchService.validateDestination(url)
        } catch {
            return reject(error)
        }

        let decision = await URLFetchHostPolicy.evaluateResolvedHost(
            host,
            timeout: timeout,
            resolver: resolver
        )
        switch decision {
        case .allow: return request
        case .deny: return reject(.privateNetworkDisallowed)
        case .unavailable: return reject(.requestFailed)
        }
    }

    private func reject(_ error: HTMLToMarkdownURLFetchError) -> URLRequest? {
        lock.withLock { failure = error }
        return nil
    }
}

public struct HTMLToMarkdownURLFetchService: Sendable {
    private let client: any HTMLToMarkdownURLFetchClient

    public init(client: any HTMLToMarkdownURLFetchClient = LiveHTMLToMarkdownURLFetchClient()) {
        self.client = client
    }

    public func fetchHTML(
        from urlText: String,
        options: HTMLToMarkdownURLFetchOptions = HTMLToMarkdownURLFetchOptions()
    ) async throws -> HTMLToMarkdownFetchedDocument {
        let url = try Self.normalizedURL(from: urlText)
        var request = URLRequest(url: url, timeoutInterval: options.timeout)
        request.httpMethod = "GET"
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("XTools HTMLToMarkdown/1.0", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await client.fetchData(for: request, byteLimit: options.responseBodyByteLimit)
        } catch let fetchError as HTMLToMarkdownURLFetchError {
            throw fetchError
        } catch {
            throw HTMLToMarkdownURLFetchError.requestFailed
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTMLToMarkdownURLFetchError.nonHTTPResponse
        }

        guard let responseURL = httpResponse.url,
              let responseHost = responseURL.host,
              let responseScheme = responseURL.scheme?.lowercased(),
              (responseScheme == "http" || responseScheme == "https"),
              URLFetchHostPolicy.evaluate(host: responseHost) == .allow else {
            throw HTMLToMarkdownURLFetchError.privateNetworkDisallowed
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw HTMLToMarkdownURLFetchError.unacceptableStatusCode(httpResponse.statusCode)
        }

        guard !data.isEmpty else {
            throw HTMLToMarkdownURLFetchError.emptyResponse
        }

        guard data.count <= options.responseBodyByteLimit else {
            throw HTMLToMarkdownURLFetchError.responseTooLarge(options.responseBodyByteLimit)
        }

        guard Self.isHTMLResponse(httpResponse, data: data) else {
            throw HTMLToMarkdownURLFetchError.unsupportedContentType
        }

        guard let html = Self.decodeText(data, response: httpResponse) else {
            throw HTMLToMarkdownURLFetchError.undecodableText
        }

        return HTMLToMarkdownFetchedDocument(html: html, responseURL: responseURL)
    }

    public static func normalizedURL(from urlText: String) throws -> URL {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw HTMLToMarkdownURLFetchError.emptyURL
        }

        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URLComponents(string: candidate)?.url else {
            throw HTMLToMarkdownURLFetchError.invalidURL
        }
        _ = try validateDestination(url)
        return url
    }

    fileprivate static func validateDestination(_ url: URL) throws(HTMLToMarkdownURLFetchError) -> String {
        guard let scheme = url.scheme?.lowercased() else { throw .invalidURL }
        guard scheme == "http" || scheme == "https" else {
            throw .unsupportedScheme(scheme)
        }
        guard let host = url.host, !host.isEmpty else {
            throw .invalidURL
        }

        if let port = url.port, !(1...65535).contains(port) {
            throw .invalidURL
        }

        if URLFetchHostPolicy.evaluate(host: host) == .deny {
            throw .privateNetworkDisallowed
        }

        guard isValidHost(host) else {
            throw .invalidURL
        }

        return host
    }

    public static func isValidHost(_ rawHost: String) -> Bool {
        let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !host.isEmpty else { return false }

        let unbracketed: String = {
            if host.hasPrefix("["), host.hasSuffix("]"), host.count >= 2 {
                return String(host.dropFirst().dropLast())
            }
            return host
        }()

        if unbracketed.contains(":") {
            return isValidIPv6(unbracketed)
        }

        if isValidIPv4(unbracketed) {
            return true
        }

        // Single integers or dot-separated numbers that are not valid 4-octet IPv4 (e.g. "123", "123.456")
        // cannot be valid domain names since domain TLDs cannot be numeric.
        if unbracketed.allSatisfy({ $0.isNumber || $0 == "." }) {
            return false
        }

        return isValidDomainName(unbracketed)
    }

    private static func isValidIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        for part in parts {
            guard let val = UInt8(part), String(val) == part else {
                return false
            }
        }
        return true
    }

    private static func isValidIPv6(_ host: String) -> Bool {
        var sin6 = sockaddr_in6()
        return host.withCString { cstr in
            inet_pton(AF_INET6, cstr, &sin6.sin6_addr) == 1
        }
    }

    private static func isValidDomainName(_ host: String) -> Bool {
        guard host.count <= 253 else { return false }

        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }

        for label in labels {
            guard !label.isEmpty, label.count <= 63 else { return false }
            guard label.first != "-", label.last != "-" else { return false }
            guard label.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else {
                return false
            }
        }

        guard let tld = labels.last else { return false }
        guard tld.count >= 2 else { return false }

        if tld.hasPrefix("xn--") {
            let punycodeSuffix = tld.dropFirst(4)
            guard !punycodeSuffix.isEmpty,
                  punycodeSuffix.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }),
                  punycodeSuffix.last != "-" else {
                return false
            }
        } else {
            guard tld.allSatisfy({ $0.isLetter }) else {
                return false
            }
        }

        return true
    }

    private static func decodeText(_ data: Data, response: HTTPURLResponse) -> String? {
        if let charset = charsetName(from: response) ?? htmlDeclaredCharset(in: data),
           let encoding = String.Encoding(ianaCharsetName: charset),
           let decoded = String(data: data, encoding: encoding) {
            return decoded
        }

        if let decoded = String(data: data, encoding: .utf8) {
            return decoded
        }

        return String(data: data, encoding: .isoLatin1)
    }

    private static func isHTMLResponse(_ response: HTTPURLResponse, data: Data) -> Bool {
        if let mimeType = response.mimeType?.lowercased(), !mimeType.isEmpty {
            return mimeType == "text/html"
                || mimeType == "application/xhtml+xml"
                || mimeType.hasSuffix("+html")
        }

        guard let prefix = String(
            data: data.prefix(512),
            encoding: .isoLatin1
        )?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }
        return prefix.hasPrefix("<!doctype html")
            || prefix.hasPrefix("<html")
            || prefix.hasPrefix("<head")
            || prefix.hasPrefix("<body")
            || prefix.hasPrefix("<article")
            || prefix.hasPrefix("<main")
            || prefix.hasPrefix("<div")
            || prefix.hasPrefix("<p")
    }

    private static let charsetRegex: NSRegularExpression = {
        let pattern = #"(?i)charset\s*=\s*[\"']?\s*([A-Za-z0-9._:-]+)"#
        return try! NSRegularExpression(pattern: pattern)
    }()

    private static let quoteCharacterSet = CharacterSet(charactersIn: "\"'")

    private static func htmlDeclaredCharset(in data: Data) -> String? {
        guard let prefix = String(
            data: data.prefix(16 * 1024),
            encoding: .isoLatin1
        ) else {
            return nil
        }

        guard let match = charsetRegex.firstMatch(
            in: prefix,
            range: NSRange(prefix.startIndex..., in: prefix)
        ),
        let range = Range(match.range(at: 1), in: prefix) else {
            return nil
        }
        return String(prefix[range])
    }

    private static func charsetName(from response: HTTPURLResponse) -> String? {
        guard let contentType = response.value(forHTTPHeaderField: "Content-Type") else {
            return nil
        }

        for part in contentType.split(separator: ";") {
            let pieces = part.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if pieces.count == 2, pieces[0].lowercased() == "charset" {
                return pieces[1].trimmingCharacters(in: quoteCharacterSet)
            }
        }
        return nil
    }
}

private extension String.Encoding {
    init?(ianaCharsetName: String) {
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(ianaCharsetName as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else {
            return nil
        }

        self.init(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
    }
}
