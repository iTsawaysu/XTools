public struct JSONExactTextIdentity: Hashable, Comparable, Sendable {
    private let bytes: [UInt8]

    public init(_ text: String) {
        bytes = Array(text.utf8)
    }

    public static func < (left: Self, right: Self) -> Bool {
        left.bytes.lexicographicallyPrecedes(right.bytes)
    }
}
