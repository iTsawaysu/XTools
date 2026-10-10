import Foundation

/// 字节级 UTF-8 标识与快速等价性比较。
/// 与构造两个 identity 后 `==` 完全等价的字节级比较，零分配且支持 O(1) 长度早退。
public struct ExactUTF8Identity: Hashable, Comparable, Sendable {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    /// 与构造两个 identity 后 `==` 完全等价的字节级比较，但不做任何拷贝。
    /// 大文本的"是否需要 setText"守卫应走这条零分配路径。
    public static func isExactlyEqual(_ left: String, _ right: String) -> Bool {
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

/// 兼容别名：保持全库现有调用点无感知
public typealias JSONExactTextIdentity = ExactUTF8Identity
