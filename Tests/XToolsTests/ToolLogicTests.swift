import XToolsCore
import Foundation
import Testing

struct ToolLogicTests {
    /// Simulates a failing conversion inside a `ConverterModeBackfill` probe closure.
    private struct ConversionProbeError: Error {}

    @Test func basicAuthUsesUTF8CredentialEncoding() throws {
        let header = BasicAuthGenerator.authorizationHeader(username: "alice", password: "päss")

        #expect(header == "Authorization: Basic YWxpY2U6cMOkc3M=")
    }

    @Test func basicAuthReturnsNilForEmptyCredentials() throws {
        let header = BasicAuthGenerator.authorizationHeader(username: "", password: "")

        #expect(header == nil)
    }

    @Test func stringObfuscatorPreservesRequestedEdges() throws {
        let output = StringObfuscator.obfuscate(
            "abcdefghijkl",
            keepFirst: 4,
            keepLast: 4,
            keepSpaces: false,
            replacementCharacter: "*"
        )

        #expect(output == "abcd****ijkl")
    }

    @Test func stringObfuscatorCanPreserveSpaces() throws {
        let output = StringObfuscator.obfuscate(
            "ab cd ef",
            keepFirst: 2,
            keepLast: 2,
            keepSpaces: true,
            replacementCharacter: "*"
        )

        #expect(output == "ab ** ef")
    }

    @Test func jwtParserDecodesBase64URLHeaderAndPayload() throws {
        let token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiYWRtaW4iOnRydWV9.signature"
        let decoded = try JWTParser.parse(token)

        #expect(decoded.header.contains("\"alg\" : \"HS256\""))
        #expect(decoded.payload.contains("\"name\" : \"John Doe\""))
    }

    @Test func jwtParserRejectsMalformedSegments() throws {
        #expect(throws: JWTParser.ParseError.emptyPayload) {
            _ = try JWTParser.parse("eyJhbGciOiJIUzI1NiJ9..signature")
        }
    }

    @Test func textStatisticsCountsUnicodeText() throws {
        let stats = TextStatistics.analyze("Hi world\n你好！")

        #expect(stats.characters == 12)
        #expect(stats.nonWhitespaceCharacters == 10)
        #expect(stats.words == 4)
        #expect(stats.lines == 2)
        #expect(stats.sentences == 2)
        #expect(stats.bytes == 18)
    }

    @Test func chronometerFormatsMinutesSecondsAndCentiseconds() throws {
        let formatted = ChronometerFormatter.format(65.439)

        #expect(formatted == "01:05.43")
    }

    @Test func byteSizeFormatterSupportsBinaryUnits() throws {
        #expect(ByteSizeFormatter.format(bytes: 999) == "999 B")
        #expect(ByteSizeFormatter.format(bytes: 1_536) == "1.5 KB")
        #expect(ByteSizeFormatter.format(bytes: 5 * 1_048_576) == "5 MB")
        #expect(ByteSizeFormatter.format(bytes: 15 * 1_073_741_824) == "15 GB")
        #expect(ByteSizeFormatter.format(bytes: 1_649_267_441_664) == "1.5 TB")
    }

    @Test func deviceInfoFormattingUsesReadableUptime() throws {
        let uptime = DeviceInfoFormatter.formatUptime(90_061)

        #expect(uptime == "1 天 1 小时")
    }

    @Test func urlCoderModeBackfillUsesCurrentValidPercentEncodedOutput() throws {
        let backfill = ConverterModeBackfill.currentValidOutput(
            input: "路径?q=值",
            currentMode: "enc",
            hasError: false
        ) { input, mode in
            mode == "enc" ? URLPercentCoding.encodeComponent(input) : try URLPercentCoding.decode(input)
        }

        #expect(backfill == "%E8%B7%AF%E5%BE%84%3Fq%3D%E5%80%BC")
        #expect(try URLPercentCoding.decode(backfill ?? "") == "路径?q=值")
    }

    @Test func urlCoderModeBackfillRejectsEmptyOrErroredOutput() throws {
        let emptyOutput = ConverterModeBackfill.currentValidOutput(
            input: "路径",
            currentMode: "enc",
            hasError: false
        ) { _, _ in "" }

        let visibleError = ConverterModeBackfill.currentValidOutput(
            input: "路径",
            currentMode: "enc",
            hasError: true
        ) { input, _ in
            URLPercentCoding.encodeComponent(input)
        }

        let throwingConversion = ConverterModeBackfill.currentValidOutput(
            input: "%",
            currentMode: "dec",
            hasError: false
        ) { input, _ in
            try URLPercentCoding.decode(input)
        }

        #expect(emptyOutput == nil)
        #expect(visibleError == nil)
        #expect(throwingConversion == nil)
    }
}
