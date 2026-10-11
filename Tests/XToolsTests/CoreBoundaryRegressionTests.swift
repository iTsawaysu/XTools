import CoreGraphics
import Foundation
import Testing
import Yams
@testable import XToolsCore

struct CoreBoundaryRegressionTests {
    @Test func regexPreservesScalarMatchesInsideGraphemes() throws {
        let source = "e\u{301}👩‍💻\r\nx"
        let report = try RegexMatcher.analyze(pattern: ".", in: source, flags: "gs")
        #expect(report.matches.map(\.value) == ["e", "\u{301}", "👩", "\u{200D}", "💻", "\r\n", "x"])
        #expect(report.matches.compactMap(\.utf16Range) == [
            NSRange(location: 0, length: 1), NSRange(location: 1, length: 1),
            NSRange(location: 2, length: 2), NSRange(location: 4, length: 1),
            NSRange(location: 5, length: 2), NSRange(location: 7, length: 2),
            NSRange(location: 9, length: 1)
        ])
        #expect(report.matches.map(\.index) == [0, 0, 1, 1, 1, 2, 3])
        #expect(report.matches.map(\.end) == [0, 1, 1, 1, 2, 3, 4])
        let captures = try RegexMatcher.analyze(pattern: "(?<accent>\u{301})", in: source)
        #expect(captures.matches.first?.groups.map(\.name) == ["accent"])
        #expect(captures.matches.first?.groups.first?.utf16Range == NSRange(location: 1, length: 1))
        #expect(captures.matches.first?.captures.first?.value == "\u{301}")
        #expect(captures.matches.first?.captures.first?.utf16Range == NSRange(location: 1, length: 1))
        let graphemes = try RegexMatcher.analyze(pattern: #"\X"#, in: source)
        #expect(graphemes.matches.map(\.value) == ["e\u{301}", "👩‍💻", "\r\n", "x"])
    }

    @Test func regexASCIICRLFOffsetsRemainCharacterBased() throws {
        let report = try RegexMatcher.analyze(pattern: "x", in: "a\r\nx\r\nx")
        #expect(report.matches.map(\.index) == [2, 4])
        #expect(report.matches.compactMap(\.utf16Range) == [NSRange(location: 3, length: 1), NSRange(location: 6, length: 1)])
    }

    @Test func jwtDetectsDuplicateMembersAfterDeepValidValues() throws {
        for depth in [255, 256, 300] {
            let padding = String(repeating: "[", count: depth) + "0" + String(repeating: "]", count: depth)
            let valid = "{\"pad\":\(padding),\"exp\":0}"
            let parsed = try #require(JWTJSONObjectParser.parse(Data(valid.utf8)) as? [String: Any])
            #expect((parsed["exp"] as? NSNumber)?.intValue == 0)
            for member in ["exp", "alg"] {
                let duplicate = "{\"pad\":\(padding),\"\(member)\":0,\"\(member)\":1}"
                #expect(throws: JWTJSONObjectParser.ParseFailure.duplicateKey) {
                    _ = try JWTJSONObjectParser.parse(Data(duplicate.utf8))
                }
            }
        }
    }

    @Test func imageInspectionDoesNotHideSparseTransparencyInLongImages() throws {
        for width in [2_048, 2_049, 8_192] {
            let png = try rgbaPNG(width: width, height: 16, transparentPixel: 0)
            #expect(try ImageProcessor.inspect(data: png, filenameExtension: "png").transparency == .transparent)
            #expect(throws: ImageProcessorError.missingTransparencyFill) {
                _ = try ImageProcessor.convert(data: png, to: .jpeg, quality: 0.8, maxPixelLength: nil)
            }
            let output = try ImageProcessor.convert(data: png, to: .jpeg, quality: 0.8, maxPixelLength: nil, transparencyFill: .white)
            #expect(output.pixelWidth == width)
        }
        let opaque = try rgbaPNG(width: 8_192, height: 16)
        #expect(try ImageProcessor.inspect(data: opaque, filenameExtension: "png").transparency == .opaque)
        #expect(try ImageProcessor.convert(data: opaque, to: .jpeg, quality: 0.8, maxPixelLength: nil).format == .jpeg)
    }

    @Test func downsampledOpaqueProbeRemainsUnknownWithoutForcingOpaqueConversionFill() throws {
        let opaque = try rgbaPNG(width: 2_049, height: 2_049)
        #expect(try ImageProcessor.inspect(data: opaque, filenameExtension: "png").transparency == .unknown)
        #expect(try ImageProcessor.convert(data: opaque, to: .jpeg, quality: 0.8, maxPixelLength: nil).format == .jpeg)
    }

    @Test func diffAlgorithmFreshnessAndNativeRangesShareLineBoundaries() throws {
        for separator in ["\r\n", "\r", "\n", "\u{85}", "\u{2028}", "\u{2029}"] {
            let source = "👩🏽‍💻" + separator + "e\u{301}" + separator
            let isNewline = ["\r\n", "\r", "\n"].contains(separator)
            let expected = isNewline ? ["👩🏽‍💻", "e\u{301}", ""] : [source]
            #expect(DiffSourceText.sourceLines(in: source) == expected)
            #expect(DiffSourceText.lineRanges(in: source).map { (source as NSString).substring(with: $0) } == expected)
            let rows = try LineDiffer.safeAlignedDiff(left: source, right: source)
            #expect(DiffDecorationFreshness.rowsMatchVisibleText(rows: rows, side: .left, text: source))
            #expect(DiffDecorationFreshness.rowsMatchVisibleText(rows: rows, side: .right, text: source))
        }
    }

    @Test func malformedCronSlashFieldsReturnDiagnostics() {
        for invalid in ["/", "//", "/1", "1/", "*/", "1,/"] {
            for index in 0..<5 {
                var fields = Array(repeating: "*", count: 5)
                fields[index] = invalid
                let expression = fields.joined(separator: " ")
                #expect(CronScheduler.validationMessage(expression) != nil)
                #expect(CronScheduler.nextRuns(expression, count: 1, after: Date(timeIntervalSince1970: 0), calendar: Calendar(identifier: .gregorian)).isEmpty)
            }
        }
    }

    @Test func cronStarStepsStillConstrainCalendarDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let after = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        let oddDays = CronScheduler.nextRuns("0 0 */2 * *", count: 5, after: after, calendar: calendar)
        #expect(oddDays.map { calendar.component(.day, from: $0) } == [3, 5, 7, 9, 11])
        let mondays = CronScheduler.nextRuns("0 0 */2 * MON", count: 3, after: after, calendar: calendar)
        #expect(mondays.map { calendar.component(.day, from: $0) } == [5, 19, 9])
        #expect(mondays.map { calendar.component(.month, from: $0) } == [10, 10, 11])
        #expect(mondays.allSatisfy { calendar.component(.weekday, from: $0) == 2 })
        #expect(CronScheduler.expressionSummary("0 0 */2 * *") == nil)
    }

    @Test func oversizedHTMLListStartsHaveSafeExplicitFallback() {
        for start in [String(Int.max), "999999999999999999999999"] {
            let result = HTMLToMarkdownConverter.convert("<ol start=\"\(start)\"><li>a</li><li>b</li></ol>", options: .init())
            #expect(result.markdown == "1. a\n2. b")
            #expect(result.warnings.contains(.orderedListStartOutOfRange))
            #expect(HTMLToMarkdownDiagnostics.conversionWarningMessage(for: result.warnings)?.contains("9 位") == true)
        }
        #expect(HTMLToMarkdownConverter.convert("<ol start=\"7\"><li>a</li><li>b</li></ol>") == "7. a\n8. b")
        #expect(HTMLToMarkdownConverter.convert("<ol start=\"999999999\"><li>a</li><li>b</li></ol>") == "999999999. a\n999999999. b")
    }

    @Test func yamlQuotedContinuationsDoNotBecomeAnchorsOrCrash() throws {
        let input = "value: \"line \\\n  &literal *literal\"\n"
        for sort in [false, true] {
            let output = try YAMLPrettifier.formatValidated(input, options: .init(indent: 4, sortKeys: sort))
            let value = try #require(Yams.load(yaml: output) as? [String: String])
            #expect(value["value"] == "line &literal *literal")
        }
        let unusedAnchor = "value: &anchor \"text\"\n"
        #expect(throws: YAMLPrettifier.ValidationError.self) {
            _ = try YAMLPrettifier.formatValidated(unusedAnchor, options: .init(sortKeys: true))
        }
    }

    @Test func yamlCommentIndentationPreservesBlockScalarValuesAndSiblings() throws {
        for indicator in ["|", "|-", "|+", ">-", "|2-"] {
            let input = "# retain\nroot:\n  text: \(indicator)\n    hello\n      indented\n\n  sibling: value\n"
            let before = try #require(Yams.load(yaml: input) as? NSDictionary)
            for indent in [1, 4] {
                let output = try YAMLPrettifier.formatValidated(input, options: .init(indent: indent))
                let after = try #require(Yams.load(yaml: output) as? NSDictionary)
                #expect(before == after)
                #expect(output.contains("# retain"))
                #expect(output.contains(String(repeating: " ", count: indent) + "sibling: value"))
            }
        }
    }

    @Test func yamlInlineSequenceMappingKeepsSafeOriginalIndentation() throws {
        for input in [
            "# comment\n- text: |\n    hello\n  sibling: value\n",
            "# comment\nroot:\n  - text: |2-\n      hello\n    sibling: value\n"
        ] {
            let parsedBefore = try Yams.load(yaml: input)
            let before = try #require(parsedBefore)
            for indent in [1, 4] {
                let output = try YAMLPrettifier.formatValidated(input, options: .init(indent: indent))
                let parsedAfter = try Yams.load(yaml: output)
                let after = try #require(parsedAfter)
                #expect(NSDictionary(dictionary: ["value": before]) == NSDictionary(dictionary: ["value": after]))
                #expect(output.contains("sibling: value"))
            }
        }
    }

    @Test func composeAliasExpansionIsBoundedBeforeAnyConstruction() throws {
        var yaml = "x-a0: &a0 [0, 0]\n"
        for index in 1...20 { yaml += "x-a\(index): &a\(index) [*a\(index - 1), *a\(index - 1)]\n" }
        yaml += "services: {app: {image: alpine}}\n"
        // A shared Node graph remains allowed; only the Any consumer charges expansion.
        #expect(try YAMLProcessingPreflight.inspect(yaml).hasAliases)
        #expect(throws: StructuredTextResourceError.self) { _ = try DockerComposeToRunService.convert(yaml) }
        let small = "x-base: &base {image: alpine}\nservices: {app: *base}\n"
        #expect(try DockerComposeToRunService.convert(small).commands == ["docker run -d alpine"])
        #expect(throws: CancellationError.self) {
            _ = try StructuredTextExecution.withCancellation({ true }) { try DockerComposeToRunService.convert(small) }
        }
    }

    @Test func composeStopGracePeriodBecomesExactIntegerSeconds() throws {
        for (duration, expected) in [("30s", "30"), ("1m30s", "90"), ("1.5m", "90"), ("500ms500ms", "1"), ("0s", "0"), ("0", "0"), ("1000000us", "1")] {
            let result = try DockerComposeToRunService.convert("services: {app: {image: alpine, stop_grace_period: '\(duration)'}}")
            #expect(result.commands == ["docker run -d --stop-timeout \(expected) alpine"])
            #expect(result.warnings.isEmpty)
        }
        for duration in ["1.5s", "1ns", "9223372036854775808s", "-2s", "1s-invalid", "+"] {
            let result = try DockerComposeToRunService.convert("services: {app: {image: alpine, stop_grace_period: '\(duration)'}}")
            #expect(result.commands == ["docker run -d alpine"])
            #expect(result.warningDetails.contains {
                $0.contains("stop_grace_period") && $0.contains("无法无损转换为整数秒")
            })
            #expect(!result.warningDetails.contains { $0.contains("未知字段") })
        }
        let forward = try DockerRunToDockerComposeService.convert("docker run --stop-timeout 30 alpine")
        #expect(try DockerComposeToRunService.convert(forward.yaml).commands == ["docker run -d --stop-timeout 30 alpine"])
    }

    private func rgbaPNG(width: Int, height: Int, transparentPixel: Int? = nil) throws -> Data {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for offset in stride(from: 3, to: pixels.count, by: 4) { pixels[offset] = 255 }
        if let transparentPixel { pixels[transparentPixel * 4 + 3] = 254 }
        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        let image = try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
            decode: nil, shouldInterpolate: true, intent: .defaultIntent))
        return try ImageProcessor.encode(image: image, format: .png, quality: nil)
    }
}
