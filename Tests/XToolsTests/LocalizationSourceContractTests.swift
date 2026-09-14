import Foundation
import Testing

/// v3 anti-regression contract: every user-facing CJK string literal in the
/// app target must exist as a key in `Localizable.xcstrings`, so the catalog
/// stays the complete translation surface. Interpolated literals are exempt
/// until the translation phase defines a formatting convention for them.
///
/// The scanner mirrors the one-shot sweep generator: comment-stripping is
/// string-aware, interpolation (`\(...)`) exempts the whole literal, and Swift
/// escapes are unescaped before the catalog lookup.
struct LocalizationSourceContractTests {
    private struct CatalogShapeError: Error {}

    @Test func everyCJKLiteralIsAStringCatalogKey() throws {
        let catalogKeys = try Self.stringCatalogKeys()
        let missing = try Self.cjkLiteralsInAppSources().subtracting(catalogKeys)

        #expect(
            missing.isEmpty,
            Comment(rawValue: "CJK literals missing from Localizable.xcstrings: \(missing.sorted().prefix(20))")
        )
    }

    @Test func stringCatalogKeepsStructuredShape() throws {
        let object = try Self.catalogObject()

        #expect(object?["sourceLanguage"] as? String == "zh-Hans")
        #expect(object?["version"] as? String == "1.0")
        #expect((object?["strings"] as? [String: Any])?.isEmpty == false)
    }
}

// MARK: - Scanner

private extension LocalizationSourceContractTests {
    static func catalogObject() throws -> [String: Any]? {
        let url = try sourcePackageRoot()
            .appendingPathComponent("Sources/XTools/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CatalogShapeError()
        }
        return object
    }

    static func stringCatalogKeys() throws -> Set<String> {
        guard let strings = try catalogObject()?["strings"] as? [String: Any] else {
            throw CatalogShapeError()
        }
        return Set(strings.keys)
    }

    static func cjkLiteralsInAppSources() throws -> Set<String> {
        let sourceRoot = try sourcePackageRoot()
            .appendingPathComponent("Sources/XTools")
        let enumerator = FileManager.default.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: nil
        )
        var literals: Set<String> = []
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            literals.formUnion(cjkLiterals(in: stripComments(source)))
        }
        return literals
    }

    /// Removes // and /* */ comments without touching comment markers that
    /// appear inside string literals.
    static func stripComments(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        var inString = false
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            if inString {
                out.append(c)
                if c == "\\" {
                    let next = text.index(after: i)
                    if next < text.endIndex {
                        out.append(text[next])
                        i = text.index(after: next)
                        continue
                    }
                }
                if c == "\"" {
                    inString = false
                }
                i = text.index(after: i)
                continue
            }
            if c == "\"" {
                inString = true
                out.append(c)
                i = text.index(after: i)
                continue
            }
            if c == "/", text.index(after: i) < text.endIndex {
                let next = text.index(after: i)
                if text[next] == "/" {
                    i = next
                    while i < text.endIndex, text[i] != "\n" {
                        i = text.index(after: i)
                    }
                    continue
                }
                if text[next] == "*" {
                    i = text.index(after: next)
                    while i < text.endIndex {
                        if text[i] == "*", text.index(after: i) < text.endIndex,
                           text[text.index(after: i)] == "/" {
                            i = text.index(i, offsetBy: 2)
                            break
                        }
                        i = text.index(after: i)
                    }
                    continue
                }
            }
            out.append(c)
            i = text.index(after: i)
        }
        return out
    }

    static func cjkLiterals(in source: String) -> Set<String> {
        var literals: Set<String> = []
        var current = ""
        var inString = false
        var containsCJK = false
        var isInterpolated = false

        func flush() {
            if inString, containsCJK, !isInterpolated {
                literals.insert(unescapeSwiftLiteral(current))
            }
            inString = false
            containsCJK = false
            isInterpolated = false
            current = ""
        }

        var i = source.startIndex
        while i < source.endIndex {
            let c = source[i]
            if inString {
                if c == "\\" {
                    let next = source.index(after: i)
                    if next < source.endIndex {
                        if source[next] == "(" {
                            // Whole literal is exempt once interpolation appears.
                            isInterpolated = true
                        }
                        current.append(c)
                        current.append(source[next])
                        i = source.index(after: next)
                        continue
                    }
                }
                if c == "\"" {
                    flush()
                    i = source.index(after: i)
                    continue
                }
                if !isInterpolated, c.isCJKHan {
                    containsCJK = true
                }
                current.append(c)
                i = source.index(after: i)
                continue
            }
            if c == "\"" {
                inString = true
                i = source.index(after: i)
                continue
            }
            i = source.index(after: i)
        }
        flush()
        return literals
    }

    /// Unescapes the Swift escape forms the UI copy actually uses.
    static func unescapeSwiftLiteral(_ body: String) -> String {
        var result = ""
        result.reserveCapacity(body.count)
        var i = body.startIndex
        while i < body.endIndex {
            let c = body[i]
            guard c == "\\", body.index(after: i) < body.endIndex else {
                result.append(c)
                i = body.index(after: i)
                continue
            }
            let next = body[body.index(after: i)]
            switch next {
            case "\"":
                result.append("\"")
                i = body.index(i, offsetBy: 2)
            case "\\":
                result.append("\\")
                i = body.index(i, offsetBy: 2)
            case "n":
                result.append("\n")
                i = body.index(i, offsetBy: 2)
            case "r":
                result.append("\r")
                i = body.index(i, offsetBy: 2)
            case "t":
                result.append("\t")
                i = body.index(i, offsetBy: 2)
            case "0":
                result.append("\0")
                i = body.index(i, offsetBy: 2)
            case "u":
                let afterU = body.index(i, offsetBy: 2)
                if afterU < body.endIndex, body[afterU] == "{",
                   let close = body[afterU...].firstIndex(of: "}") {
                    let hex = String(body[body.index(after: afterU)..<close])
                    if let scalar = UInt32(hex, radix: 16), let unicode = Unicode.Scalar(scalar) {
                        result.append(Character(unicode))
                    }
                    i = body.index(after: close)
                } else {
                    result.append(c)
                    i = body.index(after: i)
                }
            default:
                // Unknown escapes stay verbatim so the catalog lookup matches.
                result.append(c)
                result.append(next)
                i = body.index(i, offsetBy: 2)
            }
        }
        return result
    }
}

private extension Character {
    /// Same Han range the sweep generator used (U+4E00...U+9FFF).
    var isCJKHan: Bool {
        guard let scalar = unicodeScalars.first, unicodeScalars.count == 1 else {
            return false
        }
        return scalar.value >= 0x4E00 && scalar.value <= 0x9FFF
    }
}
