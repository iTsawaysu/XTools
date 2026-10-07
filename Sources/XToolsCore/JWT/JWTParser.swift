import Foundation

public enum JWTParser {
    public struct DecodedToken: Equatable {
        public let header: String
        public let payload: String

        public init(header: String, payload: String) {
            self.header = header
            self.payload = payload
        }
    }

    public enum ParseError: Error, Equatable, LocalizedError {
        case invalidSegmentCount(Int)
        case emptyHeader
        case emptyPayload
        case invalidBase64
        case invalidJSON
        case duplicateJSONMember

        public var errorDescription: String? {
            switch self {
            case .invalidSegmentCount(let count) where count > 3:
                return "JWT 只能包含 header.payload.signature 三段（当前有 \(count) 段）。"
            case .invalidSegmentCount:
                return "JWT 必须包含 header.payload.signature 三段。"
            case .emptyHeader:
                return "JWT Header 不能为空。"
            case .emptyPayload:
                return "JWT Payload 不能为空。"
            case .invalidBase64:
                return "JWT 包含无效的 Base64URL 内容。"
            case .invalidJSON:
                return "JWT Header 或 Payload 不是有效的 JSON 对象。"
            case .duplicateJSONMember:
                return "JWT Header 或 Payload 的成员名存在重复，无法明确判定取值。"
            }
        }
    }

    public static func parse(_ token: String) throws -> DecodedToken {
        let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = value.split(separator: ".", omittingEmptySubsequences: false).map(String.init)

        guard parts.count == 3 else {
            throw ParseError.invalidSegmentCount(parts.count)
        }
        guard !parts[0].isEmpty else {
            throw ParseError.emptyHeader
        }
        guard !parts[1].isEmpty else {
            throw ParseError.emptyPayload
        }

        return DecodedToken(
            header: try decodeJSONSegment(parts[0]),
            payload: try decodeJSONSegment(parts[1])
        )
    }

    private static func decodeJSONSegment(_ segment: String) throws -> String {
        let data: Data
        do {
            data = try Base64Conversion.decodeBase64URLData(segment)
        } catch {
            throw ParseError.invalidBase64
        }

        let object: [String: Any]
        do {
            guard let decoded = try JWTJSONObjectParser.parse(data) as? [String: Any] else {
                throw ParseError.invalidJSON
            }
            object = decoded
        } catch JWTJSONObjectParser.ParseFailure.duplicateKey {
            throw ParseError.duplicateJSONMember
        } catch {
            throw ParseError.invalidJSON
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            guard let text = String(data: data, encoding: .utf8) else {
                throw ParseError.invalidJSON
            }
            return text
        } catch let error as ParseError {
            throw error
        } catch {
            throw ParseError.invalidJSON
        }
    }
}
