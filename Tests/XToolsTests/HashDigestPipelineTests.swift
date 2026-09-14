import XToolsCore
import Testing

struct HashDigestPipelineTests {
    @Test func descriptorsUseSecureFirstOrderAndTypedCompatibilityMetadata() {
        #expect(HashDigestAlgorithm.allCases.map(\.displayName) == [
            "SHA-256", "SHA-512", "SHA-384", "SHA-224",
            "SHA3-512", "RIPEMD-160", "SHA-1", "MD5"
        ])
        #expect(HashDigestAlgorithm.allCases.filter(\.isCompatibilityOnly) == [.sha1, .md5])
    }

    @Test func computeProducesEightTypedDigestsInDescriptorOrder() throws {
        let items = try HashDigestPipeline.compute(text: "abc")
        #expect(items.map(\.algorithm) == HashDigestAlgorithm.allCases)
        #expect(items.map(\.name) == HashDigestAlgorithm.allCases.map(\.displayName))
        #expect(items.count == 8)
        #expect(!items[0].isCompatibilityOnly)
        #expect(items[6].isCompatibilityOnly && items[7].isCompatibilityOnly)
    }

    @Test func allAlgorithmsMatchStandardAbcVectors() throws {
        let expected = [
            "SHA-256": "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            "SHA-512": "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f",
            "SHA-384": "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7",
            "SHA-224": "23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7",
            "SHA3-512": "b751850b1a57168a5693cd924b6b096e08f621827444f70d884f5d0240d2712e10e116e9192af3c91a7ec57647e3934057340b4cf408d5a56592f8274eec53f0",
            "RIPEMD-160": "8eb208f7e05d987a9b044a8e98c6b087f15a0bfc",
            "SHA-1": "a9993e364706816aba3e25717850c26c9cd0d89d",
            "MD5": "900150983cd24fb0d6963f7d28e17f72"
        ]

        for item in try HashDigestPipeline.compute(text: "abc") {
            #expect(DigestEncoding.format(item.bytes, mode: "hex") == expected[item.name])
        }
    }

    @Test func cancellationIsCheckedAtAlgorithmBoundaries() {
        var checkCount = 0

        #expect(throws: CancellationError.self) {
            _ = try HashDigestPipeline.compute(Array("abc".utf8)) {
                checkCount += 1
                return checkCount == 3
            }
        }
        #expect(checkCount == 3)
    }

    @Test func emptyInputStillHashesEmptyBytesWithStandardRIPEMD() throws {
        let items = try HashDigestPipeline.compute(text: "")
        let ripemd160 = items.first { $0.algorithm == .ripemd160 }
        #expect(items.count == 8)
        #expect(ripemd160.map { DigestEncoding.format($0.bytes, mode: "hex") }
            == "9c1185a5c5e9fc54612808977ee8f548b2258d31")
    }

    @Test func ripemd160MatchesPublishedVectors() {
        let vectors = [
            ("", "9c1185a5c5e9fc54612808977ee8f548b2258d31"),
            ("a", "0bdc9d2d256b3ee9daae347be6f4dc835a467ffe"),
            ("abc", "8eb208f7e05d987a9b044a8e98c6b087f15a0bfc"),
            ("message digest", "5d0689ef49d2fae572b881b123a85ffa21595f36"),
            ("abcdefghijklmnopqrstuvwxyz", "f71c27109c692c1b56bbdceb5b9d2865b3708dbc"),
            (String(repeating: "1234567890", count: 8), "9b752e45573d4b39f4dbd3323cab82bf63326bfb")
        ]

        for (input, expected) in vectors {
            let actual = DigestEncoding.format(RIPEMD160.hash(Array(input.utf8)), mode: "hex")
            #expect(actual == expected)
        }
    }

    @Test func md5OfEmptyIsKnownValue() throws {
        let md5 = try HashDigestPipeline.compute(text: "").first { $0.algorithm == .md5 }
        #expect(DigestEncoding.format(md5!.bytes, mode: "hex") == "d41d8cd98f00b204e9800998ecf8427e")
    }

    @Test func sha256OfAbcIsKnownValue() throws {
        let sha = try HashDigestPipeline.compute(text: "abc").first { $0.algorithm == .sha256 }
        #expect(
            DigestEncoding.format(sha!.bytes, mode: "hex")
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }
}
