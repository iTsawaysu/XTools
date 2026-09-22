public struct JSONExactTextIdentity: Hashable, Comparable, Sendable {
    private let bytes: [UInt8]

    public init(_ text: String) {
        bytes = Array(text.utf8)
    }

    /// 与构造两个 identity 后 `==` 完全等价的字节级比较，但不做任何拷贝。
    /// 大文本的"是否需要 setText"守卫应走这条零分配路径。
    public static func isExactlyEqual(_ left: String, _ right: String) -> Bool {
        left.utf8.elementsEqual(right.utf8)
    }

    public static func < (left: Self, right: Self) -> Bool {
        left.bytes.lexicographicallyPrecedes(right.bytes)
    }
}
