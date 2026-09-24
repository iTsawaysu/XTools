import Darwin
import Foundation

/// Host policy for outbound URL fetches performed by Core tools.
/// Rejects local addresses and well-known metadata hosts before a request.
/// DNS preflight cannot pin URLSession's later connection to the checked IP.
public enum URLFetchHostPolicy: Sendable {
    public enum Decision: Equatable, Sendable {
        case allow
        case deny
    }

    public static func evaluate(host rawHost: String) -> Decision {
        let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !host.isEmpty else { return .deny }

        if host == "localhost" || host.hasSuffix(".localhost") {
            return .deny
        }

        if metadataHostNames.contains(host) {
            return .deny
        }

        // Bracketed IPv6 literals from URLComponents.host usually omit brackets,
        // but accept both forms.
        let unbracketed: String = {
            if host.hasPrefix("["), host.hasSuffix("]"), host.count >= 2 {
                return String(host.dropFirst().dropLast())
            }
            return host
        }()

        if let ipv4 = parseIPv4(unbracketed) {
            return isBlockedIPv4(ipv4) ? .deny : .allow
        }

        if unbracketed.contains(":") {
            guard let ipv6 = parseIPv6(unbracketed) else { return .deny }
            return isBlockedIPv6(ipv6) ? .deny : .allow
        }

        return .allow
    }

    enum ResolvedHostDecision: Equatable, Sendable {
        case allow
        case deny
        case unavailable
    }

    typealias Resolver = @Sendable (String, TimeInterval) async -> [String]?

    static func evaluateResolvedHost(
        _ host: String,
        timeout: TimeInterval,
        resolver: Resolver = { host, timeout in
            await resolveAddresses(host, timeout: timeout)
        }
    ) async -> ResolvedHostDecision {
        guard evaluate(host: host) == .allow else { return .deny }
        guard let addresses = await resolver(host, timeout) else { return .unavailable }
        guard !addresses.isEmpty else { return .unavailable }
        return evaluateResolvedAddresses(addresses) == .allow ? .allow : .deny
    }

    // getaddrinfo cannot be interrupted; one worker bounds stuck resolutions.
    private static let resolverQueue = DispatchQueue(label: "XTools.URLFetchHostPolicy.DNS")

    static func resolveAddresses(
        _ host: String,
        timeout: TimeInterval,
        lookup: @escaping @Sendable (String) -> [String]? = { host in
            resolveAddressesSynchronously(host)
        }
    ) async -> [String]? {
        let gate = DNSResolutionGate()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                gate.install(continuation)
                resolverQueue.async {
                    guard !gate.isFinished else { return }
                    gate.finish(lookup(host))
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + max(0, timeout)) {
                    gate.finish(nil)
                }
            }
        } onCancel: {
            gate.finish(nil)
        }
    }

    private static func resolveAddressesSynchronously(_ host: String) -> [String]? {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM

        var results: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &results) == 0,
              let first = results else {
            return nil
        }
        defer { freeaddrinfo(first) }

        var addresses: [String] = []
        var current: UnsafeMutablePointer<addrinfo>? = first
        while let address = current {
            guard let numericHost = numericHost(for: address) else {
                return nil
            }
            addresses.append(numericHost)
            current = address.pointee.ai_next
        }
        return addresses
    }

    static func evaluateResolvedAddresses(_ addresses: [String]) -> Decision {
        guard !addresses.isEmpty,
              addresses.allSatisfy({ address in
                  (parseIPv4(address) != nil || parseIPv6(address) != nil)
                      && evaluate(host: address) == .allow
              }) else {
            return .deny
        }
        return .allow
    }

    private static func numericHost(for address: UnsafeMutablePointer<addrinfo>) -> String? {
        guard let socketAddress = address.pointee.ai_addr else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let status = getnameinfo(
            socketAddress,
            address.pointee.ai_addrlen,
            &buffer,
            socklen_t(buffer.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        guard status == 0 else { return nil }
        let bytes = buffer.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
    }

    private static let metadataHostNames: Set<String> = [
        "metadata.google.internal",
        "metadata",
        "instance-data",
    ]

    private static func parseIPv4(_ host: String) -> (UInt8, UInt8, UInt8, UInt8)? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }

        var octets: [UInt8] = []
        octets.reserveCapacity(4)
        for part in parts {
            guard let value = UInt8(part) else { return nil }
            octets.append(value)
        }
        return (octets[0], octets[1], octets[2], octets[3])
    }

    private static func isBlockedIPv4(_ ip: (UInt8, UInt8, UInt8, UInt8)) -> Bool {
        let (a, b, _, _) = ip
        if a == 0 { return true }
        if a == 10 { return true }
        if a == 127 { return true }
        if a == 169 && b == 254 { return true }
        if a == 172 && (16...31).contains(b) { return true }
        if a == 192 && b == 168 { return true }
        if a == 100 && (64...127).contains(b) { return true }
        if a == 192 && b == 0 { return true }
        if a == 198 && (b == 18 || b == 19 || (b == 51 && ip.2 == 100)) { return true }
        if a == 203 && b == 0 && ip.2 == 113 { return true }
        if a >= 224 { return true }
        return false
    }

    private static func parseIPv6(_ host: String) -> [UInt8]? {
        var address = in6_addr()
        guard host.withCString({ inet_pton(AF_INET6, $0, &address) }) == 1 else {
            return nil
        }
        return withUnsafeBytes(of: address) { Array($0) }
    }

    private static func isBlockedIPv6(_ bytes: [UInt8]) -> Bool {
        let mapped = bytes.prefix(10).allSatisfy { $0 == 0 }
            && bytes[10] == 0xff && bytes[11] == 0xff
        if mapped {
            return isBlockedIPv4((bytes[12], bytes[13], bytes[14], bytes[15]))
        }
        // Only global unicast is eligible. This also rejects loopback, ULA,
        // link-local, multicast, unspecified and IPv4-compatible addresses.
        guard bytes[0] & 0xe0 == 0x20 else { return true }
        // Transition ranges can tunnel an IPv4 destination past this policy.
        if bytes[0] == 0x20 && bytes[1] == 0x02 { return true } // 6to4
        if bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0 && bytes[3] == 0 {
            return true // Teredo
        }
        return false
    }
}

private final class DNSResolutionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[String]?, Never>?
    private var completed = false
    private var result: [String]?

    var isFinished: Bool { lock.withLock { completed } }

    func install(_ continuation: CheckedContinuation<[String]?, Never>) {
        let completedResult = lock.withLock { () -> (Bool, [String]?) in
            if completed { return (true, result) }
            self.continuation = continuation
            return (false, nil)
        }
        if completedResult.0 { continuation.resume(returning: completedResult.1) }
    }

    func finish(_ addresses: [String]?) {
        let pending = lock.withLock { () -> CheckedContinuation<[String]?, Never>? in
            guard !completed else { return nil }
            completed = true
            result = addresses
            let pending = continuation
            continuation = nil
            return pending
        }
        pending?.resume(returning: addresses)
    }
}
