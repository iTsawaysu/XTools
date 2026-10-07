import Foundation
import Testing
@testable import XToolsCore

/// `JWTJSONObjectParser` 的重复成员名扫描器行为矩阵。合法输入必须零
/// 误报（与 `JSONSerialization` 单独解析逐字节一致），畸形输入静默放行
/// 交给序列化器报错，只有确认的重复成员名抛 `duplicateKey`。
struct JWTJSONObjectParserTests {
    private static func data(_ json: String) -> Data {
        Data(json.utf8)
    }

    @Test func acceptsDistinctMembers() throws {
        let object = try JWTJSONObjectParser.parse(Self.data(#"{"alg":"HS256","typ":"JWT","kid":"k1"}"#))
        #expect(object as? [String: Any]? != nil)
    }

    @Test func detectsTopLevelDuplicate() {
        #expect(throws: JWTJSONObjectParser.ParseFailure.duplicateKey) {
            _ = try JWTJSONObjectParser.parse(Self.data(#"{"alg":"none","alg":"HS256"}"#))
        }
    }

    @Test func detectsNestedDuplicate() {
        #expect(throws: JWTJSONObjectParser.ParseFailure.duplicateKey) {
            _ = try JWTJSONObjectParser.parse(Self.data(#"{"sub":"x","ctx":{"a":1,"a":2}}"#))
        }
    }

    @Test func sameKeyNameInDifferentObjectsIsNotDuplicate() throws {
        _ = try JWTJSONObjectParser.parse(Self.data(#"{"a":{"x":1},"b":{"x":2}}"#))
    }

    @Test func duplicateStringsInsideArraysAreNotDuplicate() throws {
        _ = try JWTJSONObjectParser.parse(Self.data(#"{"list":["x","x","x"]}"#))
    }

    @Test func escapeDecodedEquivalenceCountsAsDuplicate() {
        // \u0061 解码后是 a，与字面 "a" 同属重复成员名。
        #expect(throws: JWTJSONObjectParser.ParseFailure.duplicateKey) {
            _ = try JWTJSONObjectParser.parse(Self.data(#"{"a":1,"\u0061":2}"#))
        }
    }

    @Test func escapedKeyWithDifferentLiteralKeyIsNotDuplicate() throws {
        // \u0061 解码是 a，与字面 "b" 不同名，不得误报。
        _ = try JWTJSONObjectParser.parse(Self.data(#"{"\u0061":1,"b":2}"#))
    }

    @Test func astralKeyFromSurrogateEscapesDetectsDuplicate() {
        // 😀 的转义形式与字面形式解码一致，均计入成员名。
        #expect(throws: JWTJSONObjectParser.ParseFailure.duplicateKey) {
            _ = try JWTJSONObjectParser.parse(Self.data(#"{"😀":1,"\ud83d\ude00":2}"#))
        }
    }

    @Test func valueStringsMayRepeat() throws {
        _ = try JWTJSONObjectParser.parse(Self.data(#"{"a":"x","b":"x"}"#))
    }

    @Test func malformedJSONIsDeferredToSerialization() {
        // 截断/结构异常不抛 duplicateKey——解析错误由 JSONSerialization 报。
        for malformed in [#"{"a":1"#, #"{"a" 1}"#, #"{["x","x"]}"#, #"not json"#, ""] {
            do {
                _ = try JWTJSONObjectParser.parse(Self.data(malformed))
            } catch let failure as JWTJSONObjectParser.ParseFailure {
                Issue.record("畸形输入不应报重复键：\(malformed) → \(failure)")
            } catch {
                // JSONSerialization 的错误，符合预期。
            }
        }
    }

    @Test func nonObjectJSONPassesScan() throws {
        // 顶层数组没有成员名概念，扫描放行；顶层数字被 JSONSerialization
        // 拒绝（fragment 限制）属于既有行为，与重复键检测无关。
        _ = try JWTJSONObjectParser.parse(Self.data(#"[1,2,3]"#))
        do {
            _ = try JWTJSONObjectParser.parse(Self.data("123"))
        } catch let failure as JWTJSONObjectParser.ParseFailure {
            Issue.record("标量输入不应报重复键：\(failure)")
        } catch {
            // JSONSerialization 的 fragment 错误，符合预期。
        }
    }

    @Test func deeplyNestedInputDoesNotTrap() throws {
        let depth = 300
        let json = String(repeating: "{\"a\":", count: depth) + "1" + String(repeating: "}", count: depth)
        _ = try JWTJSONObjectParser.parse(Self.data(json))
    }
}
