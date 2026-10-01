public struct JSONExactTextIdentity: Hashable, Comparable, Sendable {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    /// 与构造两个 identity 后 `==` 完全等价的字节级比较，但不做任何拷贝。
    /// 大文本的"是否需要 setText"守卫应走这条零分配路径。
    public static func isExactlyEqual(_ left: String, _ right: String) -> Bool {
        // O(1) 长度早退：每键守卫的常见情形是「长度不同 → 必不等」（输入框
        // 旧值 vs 编辑器新值），先比计数可把原 O(文档) 的逐字节遍历降为 O(1)；
        // 等长时再走逐字节，语义与原实现完全一致。
        guard left.utf8.count == right.utf8.count else { return false }
        return left.utf8.elementsEqual(right.utf8)
    }

    public static func == (left: Self, right: Self) -> Bool {
        isExactlyEqual(left.text, right.text)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text.utf8.count)
        for byte in text.utf8 {
            hasher.combine(byte)
        }
    }

    public static func < (left: Self, right: Self) -> Bool {
        left.text.utf8.lexicographicallyPrecedes(right.text.utf8)
    }
}
