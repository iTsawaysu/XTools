import Darwin
import Foundation

/// Host policy for outbound URL fetches performed by Core tools.
/// Rejects loopback, link-local, RFC1918, ULA, and well-known cloud metadata
/// endpoints before and after DNS resolution.
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

        if let ipv4 = parseIPv4(unbracketed), isBlockedIPv4(ipv4) {
            return .deny
        }

        if unbracketed.contains(":"), isBlockedIPv6Literal(unbracketed) {
            return .deny
        }

        return .allow
    }

    /// Resolves a hostname and rejects it when any returned address belongs to
    /// a local, private, link-local, or metadata range. A failed resolution is
    /// denied because the caller cannot prove that the destination is public.
    static func evaluateResolvedHost(_ rawHost: String) -> Decision {
        guard evaluate(host: rawHost) == .allow else { return .deny }

        let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return .deny }

        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM

        var results: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, nil, &hints, &results)
        guard status == 0, let first = results else { return .deny }
        defer { freeaddrinfo(first) }

        var addresses: [String] = []
        var current: UnsafeMutablePointer<addrinfo>? = first
        while let address = current {
            guard let numericHost = numericHost(for: address) else { return .deny }
            addresses.append(numericHost)
            current = address.pointee.ai_next
        }

        return evaluateResolvedAddresses(addresses)
    }

    static func evaluateResolvedAddresses(_ addresses: [String]) -> Decision {
        guard !addresses.isEmpty,
              addresses.allSatisfy({ evaluate(host: $0) == .allow }) else {
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
        return false
    }

    private static func isBlockedIPv6Literal(_ host: String) -> Bool {
        var value = host
        if let percent = value.firstIndex(of: "%") {
            value = String(value[..<percent])
        }
        let lowered = value.lowercased()

        if lowered == "::1" || lowered == "0:0:0:0:0:0:0:1" {
            return true
        }
        if lowered.hasPrefix("fe80:") {
            return true
        }
        // Unique local addresses fc00::/7
        if lowered.hasPrefix("fc") || lowered.hasPrefix("fd") {
            return true
        }
        if let mapped = extractIPv4Mapped(lowered), isBlockedIPv4(mapped) {
            return true
        }
        return false
    }

    private static func extractIPv4Mapped(_ host: String) -> (UInt8, UInt8, UInt8, UInt8)? {
        let marker = "::ffff:"
        guard let range = host.range(of: marker) else { return nil }
        return parseIPv4(String(host[range.upperBound...]))
    }
}
