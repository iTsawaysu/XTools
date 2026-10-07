import Foundation

/// JWT 分段 JSON 的统一解析入口：先用宽容扫描器检测对象成员名重复，
/// 再交给 `JSONSerialization` 取值。
///
/// 背景：`JSONSerialization` 对重复键按后者覆盖前者处理，而 JWT 的
/// header 决定验证算法——重复的 `alg` 成员会让"取哪个算法"变得含糊，
/// 属于经典的算法混淆攻击面（RFC 7519 §4.1.1 要求成员名唯一）。
/// 扫描是正向检测：只有"确认发现重复"才抛错，任何看不懂的结构都
/// 静默放行交给序列化器，因此合法 JWT 的解析结果与既有行为逐字节一致。
enum JWTJSONObjectParser {
    enum ParseFailure: Error, Equatable {
        case duplicateKey
    }

    static func parse(_ data: Data) throws -> Any {
        // 先由序列化器把关合法性，扫描器只处理合法 JSON，杜绝把畸形
        // 输入误报成"成员名重复"。
        let value = try JSONSerialization.jsonObject(with: data)
        try ensureNoDuplicateKeys(in: data)
        return value
    }

    static func ensureNoDuplicateKeys(in data: Data) throws {
        guard let text = String(data: data, encoding: .utf8) else {
            return
        }
        var scanner = DuplicateKeyScanner(text)
        try scanner.scan()
    }

    /// 单遍标量扫描。深度超过上限等极端输入静默放行——这里的职责
    /// 只有一件事：在合法 JSON 里抓重复成员名。
    private struct DuplicateKeyScanner {
        private let scalars: String.UnicodeScalarView
        private var index: String.UnicodeScalarView.Index
        private var stack: [Frame] = []
        private static let maximumDepth = 256

        private struct Frame {
            var isObject: Bool
            var keys: Set<String>
            var awaitingKey: Bool
        }

        init(_ text: String) {
            scalars = text.unicodeScalars
            index = scalars.startIndex
        }

        mutating func scan() throws {
            var inString = false
            var escape = false
            // 仅当"处于对象内且正等待成员名"时，字符串内容才需要解码留证。
            var capturingKey = false
            var decodedKeyUnits: [UInt16] = []

            while index < scalars.endIndex {
                let scalar = scalars[index]
                index = scalars.index(after: index)

                if inString {
                    if escape {
                        escape = false
                        guard capturingKey else { continue }
                        switch scalar {
                        case "\"", "\\", "/":
                            decodedKeyUnits.append(UInt16(scalar.value))
                        case "b":
                            decodedKeyUnits.append(8)
                        case "f":
                            decodedKeyUnits.append(12)
                        case "n":
                            decodedKeyUnits.append(10)
                        case "r":
                            decodedKeyUnits.append(13)
                        case "t":
                            decodedKeyUnits.append(9)
                        case "u":
                            guard index < scalars.endIndex else { return }
                            var value: UInt16 = 0
                            for _ in 0..<4 {
                                guard index < scalars.endIndex else { return }
                                let hexScalar = scalars[index]
                                index = scalars.index(after: index)
                                guard let digit = UInt16(String(hexScalar), radix: 16) else { return }
                                value = value << 4 | digit
                            }
                            decodedKeyUnits.append(value)
                        default:
                            return
                        }
                        continue
                    }
                    switch scalar {
                    case "\\":
                        escape = true
                    case "\"":
                        inString = false
                        if capturingKey {
                            if let top = stack.last, top.isObject, top.awaitingKey {
                                let key = String(decoding: decodedKeyUnits, as: UTF16.self)
                                guard insert(key: key) else {
                                    throw ParseFailure.duplicateKey
                                }
                            }
                            capturingKey = false
                            decodedKeyUnits = []
                        }
                    default:
                        if capturingKey {
                            if scalar.isASCII {
                                decodedKeyUnits.append(UInt16(scalar.value))
                            } else {
                                decodedKeyUnits.append(contentsOf: String(scalar).utf16)
                            }
                        }
                    }
                    continue
                }

                switch scalar {
                case "\"":
                    inString = true
                    if let top = stack.last, top.isObject, top.awaitingKey {
                        capturingKey = true
                        decodedKeyUnits = []
                    }
                case "{":
                    guard stack.count < Self.maximumDepth else { return }
                    stack.append(Frame(isObject: true, keys: [], awaitingKey: true))
                case "[":
                    guard stack.count < Self.maximumDepth else { return }
                    stack.append(Frame(isObject: false, keys: [], awaitingKey: false))
                case "}":
                    guard stack.last?.isObject == true else { return }
                    stack.removeLast()
                case "]":
                    guard stack.last?.isObject == false else { return }
                    stack.removeLast()
                case ":":
                    if let last = stack.indices.last {
                        stack[last].awaitingKey = false
                    }
                case ",":
                    if let last = stack.indices.last, stack[last].isObject {
                        stack[last].awaitingKey = true
                    }
                default:
                    break
                }
            }
        }

        /// 向栈顶对象登记成员名；返回 false 表示重复。
        private mutating func insert(key: String) -> Bool {
            guard let last = stack.indices.last, stack[last].isObject else { return true }
            if stack[last].keys.contains(key) {
                return false
            }
            stack[last].keys.insert(key)
            stack[last].awaitingKey = false
            return true
        }
    }
}
