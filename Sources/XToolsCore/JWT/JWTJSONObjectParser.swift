import Foundation

/// JWT 分段 JSON 统一使用 UTF-8，先验证结构，再检测对象成员名重复。
///
/// 背景：`JSONSerialization` 不拒绝重复键，而 JWT 的
/// header 决定验证算法——重复的 `alg` 成员会让"取哪个算法"变得含糊，
/// 属于经典的算法混淆攻击面（RFC 7519 §4.1.1 要求成员名唯一）。
/// 扫描是正向检测：只有"确认发现重复"才抛错，任何看不懂的结构都
/// 静默放行交给序列化器，因此合法 JWT 的解析结果与既有行为逐字节一致。
enum JWTJSONObjectParser {
    enum ParseFailure: Error, Equatable {
        case invalidEncoding
        case duplicateKey
    }

    static func parse(_ data: Data) throws -> Any {
        // 原始 NUL 在 JSON 中无效，且会让 JSONSerialization 自行探测宽字符编码。
        guard !data.contains(0), let text = String(data: data, encoding: .utf8) else {
            throw ParseFailure.invalidEncoding
        }
        let value = try JSONSerialization.jsonObject(with: data)
        var scanner = DuplicateKeyScanner(text)
        try scanner.scan()
        return value
    }

    /// 单遍迭代扫描，深度沿用 Foundation 已验证的 JSON 上限；不能在
    /// 深层字段处静默退出，否则后续同级成员的重复键会漏检。
    private struct DuplicateKeyScanner {
        private let scalars: String.UnicodeScalarView
        private var index: String.UnicodeScalarView.Index
        private var stack: [Frame] = []

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
                    stack.append(Frame(isObject: true, keys: [], awaitingKey: true))
                case "[":
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
