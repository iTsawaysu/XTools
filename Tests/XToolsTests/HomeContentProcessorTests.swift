import Foundation
import Testing
@testable import XToolsCore

struct HomeContentProcessorTests {
    @Test func exposesExactlyTheThreeApprovedActions() {
        #expect(HomeContentAction.allCases == [.jsonFormat, .base64Decode, .urlDecode])
    }

    @Test func preferredActionsCoverOnlyTheThreeHomeDetections() {
        #expect(HomeContentProcessor.preferredAction(for: .json) == .jsonFormat)
        #expect(HomeContentProcessor.preferredAction(for: .base64) == .base64Decode)
        #expect(HomeContentProcessor.preferredAction(for: .urlEncoded) == .urlDecode)

        for kind in SmartPasteDetector.Kind.allCases
            where ![.json, .base64, .urlEncoded].contains(kind) {
            #expect(HomeContentProcessor.preferredAction(for: kind) == nil)
        }
    }

    @Test func safeDetectorRecognizesTheThreeSupportedInputShapes() {
        #expect(HomeContentProcessor.detect(#"{"value":1}"#) == .json)
        #expect(HomeContentProcessor.detect("5L2g5aW9IFhUb29scw==") == .base64)
        #expect(HomeContentProcessor.detect("hello%20world%21") == .urlEncoded)
        #expect(HomeContentProcessor.detect("ordinary text") == nil)
    }

    @Test func homeDetectorSupportsPrototypeShortBase64AndSingleURLEscape() {
        #expect(HomeContentProcessor.detect("SGVsbG8=") == .base64)
        #expect(HomeContentProcessor.detect("name=XTools%20Workbench") == .urlEncoded)
    }

    @Test func homeDetectorRejectsInvalidEncodingsAndOrdinaryWords() {
        #expect(HomeContentProcessor.detect("value%2G") == nil)
        #expect(HomeContentProcessor.detect("value%20bad%GG") == nil)
        #expect(HomeContentProcessor.detect("trailing%") == nil)
        #expect(HomeContentProcessor.detect("password") == nil)
        #expect(HomeContentProcessor.detect("ordinary") == nil)
        #expect(HomeContentProcessor.detect("//79/A==") == nil)
    }

    @Test func approvedActionsUseExistingCoreTransformations() throws {
        #expect(
            try output(.jsonFormat, #"{"name":"XTools","count":2}"#)
                == "{\n  \"name\": \"XTools\",\n  \"count\": 2\n}"
        )
        #expect(try output(.base64Decode, "5L2g5aW9IFhUb29scw==") == "你好 XTools")
        #expect(try output(.urlDecode, "%E4%BD%A0%E5%A5%BD%20XTools%2F1") == "你好 XTools/1")
    }

    @Test func duplicateJSONKeyWarningSurvivesFormatting() throws {
        let result = try success(.jsonFormat, #"{"id":1,"id":2}"#)
        #expect(result.warning == "JSON 含重复 key。")
        #expect(result.text.contains(#""id": 1"#))
        #expect(result.text.contains(#""id": 2"#))
    }

    @Test func malformedInputsReturnReadableTypedFailures() {
        let invalidJSON = HomeContentProcessor.run(.jsonFormat, input: #"{"name":}"#)
        guard case .failure(.processingFailed(let jsonMessage)) = invalidJSON else {
            Issue.record("Expected a JSON processing failure")
            return
        }
        #expect(!jsonMessage.isEmpty)

        #expect(
            HomeContentProcessor.run(.base64Decode, input: "not base64")
                == .failure(.processingFailed("输入不是有效的 Base64。"))
        )
        #expect(
            HomeContentProcessor.run(.urlDecode, input: "%GG")
                == .failure(.processingFailed("百分号后只能使用两位十六进制数字。"))
        )
    }

    @Test func emptyAndCharacterLimitBoundariesAreEnforced() throws {
        #expect(HomeContentProcessor.run(.urlDecode, input: " \n ") == .failure(.emptyInput))

        let boundary = String(repeating: "a", count: HomeContentProcessor.maximumCharacterCount)
        #expect(try output(.urlDecode, boundary) == boundary)

        let oversized = boundary + "a"
        #expect(
            HomeContentProcessor.run(.urlDecode, input: oversized)
                == .failure(
                    .inputTooLong(
                        maximumCharacterCount: HomeContentProcessor.maximumCharacterCount
                    )
                )
        )
        #expect(HomeContentProcessor.detect(oversized) == nil)
    }

    @Test func characterLimitUsesExtendedGraphemeClusters() throws {
        let grapheme = "👨‍👩‍👧‍👦"
        let boundary = String(
            repeating: grapheme,
            count: HomeContentProcessor.maximumCharacterCount
        )
        #expect(try output(.urlDecode, boundary) == boundary)

        let oversized = boundary + grapheme
        #expect(
            HomeContentProcessor.run(.urlDecode, input: oversized)
                == .failure(
                    .inputTooLong(
                        maximumCharacterCount: HomeContentProcessor.maximumCharacterCount
                    )
                )
        )
    }

    @Test func JSONDepthGuardRejectsOnlyStructuralNesting() throws {
        let allowedDepth = HomeContentProcessor.maximumJSONNestingDepth
        let allowed = String(repeating: "[", count: allowedDepth)
            + "0"
            + String(repeating: "]", count: allowedDepth)
        #expect(try output(.jsonFormat, allowed).hasPrefix("[\n"))

        let rejectedDepth = allowedDepth + 1
        let rejected = String(repeating: "[", count: rejectedDepth)
            + "0"
            + String(repeating: "]", count: rejectedDepth)
        #expect(HomeContentProcessor.detect(rejected) == nil)
        #expect(
            HomeContentProcessor.run(.jsonFormat, input: rejected)
                == .failure(.inputTooDeep(maximumNestingDepth: allowedDepth))
        )

        let bracketsInsideString = #"{"value":"[[[[[[[[[[[[[[[[[[[["}"#
        #expect(try output(.jsonFormat, bracketsInsideString).contains("[[[["))
    }

    private func output(_ action: HomeContentAction, _ input: String) throws -> String {
        try success(action, input).text
    }

    private func success(_ action: HomeContentAction, _ input: String) throws -> HomeContentResult {
        switch HomeContentProcessor.run(action, input: input) {
        case .success(let result):
            return result
        case .failure(let failure):
            Issue.record("Unexpected failure: \(failure.message)")
            throw failure
        }
    }
}
