import XToolsCore
import Foundation
import Testing

struct StringObfuscatorTests {
    @Test func obfuscatesEmptyString() {
        let result = StringObfuscator.obfuscate("", keepFirst: 2, keepLast: 2, keepSpaces: true, replacementCharacter: "*")
        #expect(result == "")
    }

    @Test func obfuscatesWithKeepFirst() {
        let result = StringObfuscator.obfuscate("hello", keepFirst: 2, keepLast: 0, keepSpaces: false, replacementCharacter: "*")
        #expect(result == "he***")
    }

    @Test func obfuscatesWithKeepLast() {
        let result = StringObfuscator.obfuscate("hello", keepFirst: 0, keepLast: 2, keepSpaces: false, replacementCharacter: "*")
        #expect(result == "***lo")
    }

    @Test func obfuscatesWithKeepBoth() {
        let result = StringObfuscator.obfuscate("hello world", keepFirst: 2, keepLast: 2, keepSpaces: false, replacementCharacter: "*")
        #expect(result == "he*******ld")
    }

    @Test func preservesSpaces() {
        let result = StringObfuscator.obfuscate("hello world", keepFirst: 2, keepLast: 2, keepSpaces: true, replacementCharacter: "*")
        #expect(result == "he*** ***ld")
    }

    @Test func usesCustomReplacementChar() {
        let result = StringObfuscator.obfuscate("hello", keepFirst: 1, keepLast: 1, keepSpaces: false, replacementCharacter: "#")
        #expect(result == "h###o")
    }

    @Test func handlesShortStrings() {
        let result = StringObfuscator.obfuscate("ab", keepFirst: 5, keepLast: 5, keepSpaces: false, replacementCharacter: "*")
        #expect(result == "ab")
    }

    @Test func preservesExtendedGraphemeClusters() {
        let result = StringObfuscator.obfuscate(
            "👩🏽‍💻e\u{301}z",
            keepFirst: 1,
            keepLast: 1,
            keepSpaces: false,
            replacementCharacter: "#"
        )

        #expect(result == "👩🏽‍💻#z")
    }

    @Test func preservesUnicodeWhitespaceAndClampsNegativeCounts() {
        let result = StringObfuscator.obfuscate(
            "a\tb\nc",
            keepFirst: -2,
            keepLast: -3,
            keepSpaces: true,
            replacementCharacter: "*"
        )

        #expect(result == "*\t*\n*")
    }

    @Test func cancellationCanStopCharacterCollection() {
        let probe = CancellationProbe(cancelAfter: 2)

        let result = StringObfuscator.obfuscate(
            String(repeating: "x", count: 10_000),
            keepFirst: 4,
            keepLast: 4,
            keepSpaces: false,
            replacementCharacter: "*",
            shouldCancel: probe.shouldCancel
        )

        #expect(result == nil)
        #expect(probe.checkCount == 2)
    }

    @Test func cancellationCanStopResultConstruction() {
        let probe = CancellationProbe(cancelAfter: 4)

        let result = StringObfuscator.obfuscate(
            String(repeating: "x", count: 10_000),
            keepFirst: 4,
            keepLast: 4,
            keepSpaces: false,
            replacementCharacter: "*",
            shouldCancel: probe.shouldCancel
        )

        #expect(result == nil)
        #expect(probe.checkCount == 4)
    }
}

private final class CancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let cancelAfter: Int
    private var checks = 0

    init(cancelAfter: Int) {
        self.cancelAfter = cancelAfter
    }

    var checkCount: Int {
        lock.withLock { checks }
    }

    func shouldCancel() -> Bool {
        lock.withLock {
            checks += 1
            return checks >= cancelAfter
        }
    }
}
