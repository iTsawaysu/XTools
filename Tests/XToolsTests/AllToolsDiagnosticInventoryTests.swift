@testable import XTools
import Foundation
import Testing

enum ToolDiagnosticProfile: String, Sendable {
    case none
    case inputValidation
    case errorAndWarning
    case externalIO
    case actionFailure
    case securityValidation
}

struct ToolDiagnosticInventoryEntry: Sendable {
    let id: String
    let category: String
    let profile: ToolDiagnosticProfile
    let primaryOwner: String
    let rationale: String
}

struct AllToolsDiagnosticInventoryTests {
    @Test func everyRegisteredToolHasExactlyOneDiagnosticInventoryEntry() {
        let registered = ToolRegistry.default.categoryGroups().flatMap(\.tools)
        let registeredGroups = Dictionary(grouping: registered, by: { $0.id.rawValue })
        let inventoryGroups = Dictionary(grouping: Self.inventory, by: \.id)
        let duplicateRegisteredIDs = registeredGroups.filter { $0.value.count != 1 }.keys.sorted()
        let duplicateInventoryIDs = inventoryGroups.filter { $0.value.count != 1 }.keys.sorted()

        #expect(duplicateRegisteredIDs.isEmpty, "Registered duplicate IDs: \(duplicateRegisteredIDs)")
        #expect(duplicateInventoryIDs.isEmpty, "Inventory duplicate IDs: \(duplicateInventoryIDs)")

        let actual = registeredGroups.mapValues { $0[0].categoryID.rawValue }
        let expected = inventoryGroups.mapValues { $0[0].category }

        #expect(actual.count == 46)
        #expect(Self.inventory.count == 46)
        #expect(actual == expected)
    }

    @Test func generatorAndCalculatorProfilesMatchReachableFailures() throws {
        let entries = Dictionary(uniqueKeysWithValues: Self.inventory.map { ($0.id, $0) })

        let obfuscator = try #require(entries["string-obfuscator"])
        #expect(obfuscator.profile == .none)
        #expect(!obfuscator.rationale.isEmpty)

        let randomPort = try #require(entries["random-port-generator"])
        #expect(randomPort.profile == .none)
        #expect(!randomPort.rationale.isEmpty)

        let chmod = try #require(entries["chmod-calculator"])
        #expect(chmod.profile == .inputValidation)
        #expect(chmod.rationale.isEmpty)
    }

    @Test func inventoryOwnersExistAndNoDiagnosticProfilesAreExplained() throws {
        let root = try sourcePackageRoot()

        for entry in Self.inventory {
            let owner = root.appendingPathComponent(entry.primaryOwner).path
            #expect(FileManager.default.fileExists(atPath: owner), "Missing owner for \(entry.id)")
            if entry.profile == .none {
                #expect(!entry.rationale.isEmpty, "No-diagnostic profile needs a rationale for \(entry.id)")
            }
        }
    }

    static let inventory: [ToolDiagnosticInventoryEntry] = [
        entry("base64-file-converter", "converter", .externalIO, "Converter/Base64FileWorkflow.swift"),
        entry("base64-string", "converter", .inputValidation, "Converter/Base64StringPage.swift"),
        entry("url-encoder-decoder", "converter", .inputValidation, "Converter/URLCoderPage.swift"),
        entry("text-to-ascii-binary", "converter", .inputValidation, "Converter/ASCIIBinaryPage.swift"),
        entry("text-to-unicode", "converter", .inputValidation, "Converter/UnicodePage.swift"),
        entry("integer-base-converter", "converter", .inputValidation, "Converter/IntegerBaseConverterPage.swift"),
        entry("roman-numeral-converter", "converter", .inputValidation, "Converter/RomanNumeralPage.swift"),
        entry("case-converter", "converter", .none, "Converter/CaseConverterPage.swift", "所有文本都能产生大小写派生结果，空输入仅显示空状态。"),

        entry("hash-text", "crypto", .none, "Crypto/HashTextPage.swift", "任意文本和受支持算法都能产生摘要。"),
        entry("text-encryption", "crypto", .securityValidation, "Crypto/TextEncryptionPage.swift"),
        entry("string-obfuscator", "crypto", .none, "Crypto/StringObfuscatorPage.swift", "任意文本和受控参数都能产生确定性遮蔽结果。"),
        entry("token-generator", "crypto", .securityValidation, "Crypto/TokenGeneratorPage.swift"),
        entry("uuid-generator", "crypto", .none, "Crypto/UUIDGeneratorPage.swift", "受支持数量范围由控件约束，生成过程无用户输入解析错误。"),
        entry("password-generator", "crypto", .securityValidation, "Crypto/PasswordGeneratorPage.swift"),

        entry("json-formatter", "development", .errorAndWarning, "Development/JSONFormatterPage.swift"),
        entry("sql-prettify", "development", .inputValidation, "Development/SQLPrettifyPage.swift"),
        entry("xml-formatter", "development", .inputValidation, "Development/XMLFormatterPage.swift"),
        entry("yaml-prettify", "development", .inputValidation, "Development/YAMLPrettifyPage.swift"),
        entry("json-diff", "development", .errorAndWarning, "Development/JSONDiffPage.swift"),
        entry("text-diff", "development", .inputValidation, "Development/TextDiffPage.swift"),
        entry("regex-tester", "development", .inputValidation, "Development/RegexTesterPage.swift"),
        entry("docker-run-to-docker-compose-converter", "development", .errorAndWarning, "Development/DockerRunToComposePage.swift"),
        entry("html-to-markdown", "development", .errorAndWarning, "Development/HTMLToMarkdownPage.swift"),
        entry("crontab-generator", "development", .inputValidation, "Development/CrontabGeneratorPage.swift"),
        entry("random-port-generator", "development", .none, "Development/RandomPortPage.swift", "随机生成端口候选值，不执行本机 socket 探测，也没有可达的运行时失败状态。"),
        entry("chmod-calculator", "development", .inputValidation, "Development/ChmodCalculatorPage.swift"),

        entry("jwt-parser", "web", .errorAndWarning, "Web/JWTParserPage.swift"),
        entry("basic-auth-generator", "web", .securityValidation, "Web/BasicAuthGeneratorPage.swift"),
        entry("http-status-codes", "web", .none, "Web/HTTPStatusCodesPage.swift", "查询和筛选无结果使用空状态，不是输入错误。"),
        entry("useragent-parser", "web", .inputValidation, "Web/UserAgentParserPage.swift"),
        entry("keycode-info", "web", .none, "Web/KeycodeInfoPage.swift", "键盘事件持续产生可显示结果，没有可解析文本输入。"),

        entry("image-converter", "image", .externalIO, "Image/ImageConverterPage.swift"),
        entry("image-compressor", "image", .errorAndWarning, "Image/ImageCompressorPage.swift"),
        entry("image-watermark", "image", .externalIO, "Image/ImageWatermarkPage.swift"),
        entry("image-grayscale", "image", .externalIO, "Image/ImageGrayscalePage.swift"),
        entry("favicon-generator", "image", .externalIO, "Image/FaviconGeneratorPage.swift"),
        entry("color-picker", "image", .inputValidation, "Image/ColorPickerPage.swift"),

        entry("date-time-converter", "time", .inputValidation, "Time/DateTimeConverterPage.swift"),
        entry("timezone-viewer", "time", .none, "Time/TimezoneViewerPage.swift", "固定精选城市目录没有任意文本输入；收藏与折叠为本地界面状态。"),
        entry("date-calculator", "time", .inputValidation, "Time/DateCalculatorPage.swift"),
        entry("chronometer", "time", .none, "Time/ChronometerPage.swift", "计时状态机不解析任意文本输入。"),

        entry("device-information", "utility", .none, "Utility/DeviceInformationPage.swift", "只读展示系统信息，缺失字段使用稳定占位。"),
        entry("file-type-detector", "utility", .externalIO, "Utility/FileTypeDetectorPage.swift"),
        entry("math-evaluator", "utility", .inputValidation, "Utility/MathEvaluatorPage.swift"),
        entry("text-statistics", "utility", .none, "Utility/TextStatisticsPage.swift", "任意文本都能统计，空输入产生零值。"),
        entry("emoji-picker", "utility", .actionFailure, "Utility/EmojiPickerPage.swift"),
    ]

    private static func entry(
        _ id: String,
        _ category: String,
        _ profile: ToolDiagnosticProfile,
        _ page: String,
        _ rationale: String = ""
    ) -> ToolDiagnosticInventoryEntry {
        ToolDiagnosticInventoryEntry(
            id: id,
            category: category,
            profile: profile,
            primaryOwner: "Sources/XTools/ToolPages/\(page)",
            rationale: rationale
        )
    }
}
