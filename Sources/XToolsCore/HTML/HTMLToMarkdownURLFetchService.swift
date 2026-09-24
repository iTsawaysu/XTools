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
        guard let url = request.url, let scheme = url.scheme?.lowercased(), let host = url.host else {
            throw HTMLToMarkdownURLFetchError.invalidURL
        }
        guard scheme == "http" || scheme == "https" else {
            throw HTMLToMarkdownURLFetchError.unsupportedScheme(scheme)
        }
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
        configuration.timeoutIntervalForRequest = request.timeoutInterval
        configuration.timeoutIntervalForResource = request.timeoutInterval

        let delegate = HTMLToMarkdownURLSessionDelegate(
            resolver: resolver,
            timeout: request.timeoutInterval
        )
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        return try await withTaskCancellationHandler {
            let (bytes, response): (URLSession.AsyncBytes, URLResponse)
            do {
                (bytes, response) = try await session.bytes(for: request)
            } catch {
                if let rejection = delegate.rejection { throw rejection }
                throw error
            }
            if let rejection = delegate.rejection {
                bytes.task.cancel()
                throw rejection
            }
            var data = Data()
            data.reserveCapacity(min(max(0, byteLimit), 64 * 1024))

            for try await byte in bytes {
                if data.count >= byteLimit {
                    bytes.task.cancel()
                    throw HTMLToMarkdownURLFetchError.responseTooLarge(byteLimit)
                }
                data.append(byte)
            }

            if let rejection = delegate.rejection { throw rejection }
            return (data, response)
        } onCancel: {
            session.invalidateAndCancel()
        }
    }
}

final class HTMLToMarkdownURLSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private static let maximumRedirects = 5
    private let resolver: URLFetchHostPolicy.Resolver
    private let timeout: TimeInterval
    private let lock = NSLock()
    private var redirectCount = 0
    private var rejectedRedirect: HTMLToMarkdownURLFetchError?

    init(resolver: @escaping URLFetchHostPolicy.Resolver, timeout: TimeInterval) {
        self.resolver = resolver
        self.timeout = timeout
    }

    var rejection: HTMLToMarkdownURLFetchError? {
        lock.withLock { rejectedRedirect }
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
        guard let url = request.url, let scheme = url.scheme?.lowercased(), let host = url.host else {
            return reject(.invalidURL)
        }
        guard scheme == "http" || scheme == "https" else {
            return reject(.unsupportedScheme(scheme))
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
        lock.withLock { rejectedRedirect = error }
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

    public static func isValidURL(_ urlText: String) -> Bool {
        (try? normalizedURL(from: urlText)) != nil
    }

    public static func normalizedURL(from urlText: String) throws -> URL {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw HTMLToMarkdownURLFetchError.emptyURL
        }

        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased() else {
            throw HTMLToMarkdownURLFetchError.invalidURL
        }

        guard scheme == "http" || scheme == "https" else {
            throw HTMLToMarkdownURLFetchError.unsupportedScheme(scheme)
        }

        guard let host = components.host,
              let url = components.url,
              !host.isEmpty else {
            throw HTMLToMarkdownURLFetchError.invalidURL
        }

        if let port = components.port, !(1...65535).contains(port) {
            throw HTMLToMarkdownURLFetchError.invalidURL
        }

        if URLFetchHostPolicy.evaluate(host: host) == .deny {
            throw HTMLToMarkdownURLFetchError.privateNetworkDisallowed
        }

        guard isValidHost(host) else {
            throw HTMLToMarkdownURLFetchError.invalidURL
        }

        return url
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
