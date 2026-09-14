import Foundation
import AppKit
@testable import XTools
import Testing

struct GeneratedCryptoSourceContractTests {
    @Test func generatorPagesSharePrototypeParameterCardAndValueRows() throws {
        // The whole generator family graduated to the prototype v3 layout:
        // one wrapping parameter card (recipe + facts + 全部复制/生成 ⌘↩)
        // above the shared value row list under the query-list shell.
        for path in ["TokenGeneratorPage.swift", "PasswordGeneratorPage.swift"] {
            let source = try readSource("Sources/XTools/ToolPages/Crypto/\(path)")
            contains(source, "workspaceSemantic: .queryListWorkspace", "\(path) must pin parameters above an internally scrolling value list")
            contains(source, "IndexGeneratedValueRowList(", "\(path) results must use the shared value row list")
            contains(source, "wrapsValues: true", "\(path) values are long and must wrap instead of truncating")
            contains(source, "IndexStepperInput(value: $workspace.quantity, range: 1...20)", "\(path) quantity must use the joined prototype stepper")
            contains(source, "IndexCopyButton(", "\(path) batch copy must use the shared copy button")
            contains(source, "IndexPrimaryActionButton(", "\(path) must generate through the shared prototype primary action")
            contains(source, ".keyboardShortcut(.return, modifiers: .command)", "\(path) must regenerate through Command-Return")
            doesNotContain(source, "IndexGenerateBar(", "\(path) must not keep the retired results accessory bar")
            doesNotContain(source, "IndexPanel(\"生成设置\")", "\(path) must not keep the settings panel header")
            doesNotContain(source, "IndexPanel(\"生成结果\")", "\(path) must not keep the results panel header")
        }
    }

    @Test func generatedResultPagesUseStableSlotIdentity() throws {
        let token = try readSource("Sources/XTools/ToolPages/Crypto/TokenGeneratorPage.swift")
        let uuid = try readSource("Sources/XTools/ToolPages/Crypto/UUIDGeneratorPage.swift")
        let password = try readSource("Sources/XTools/ToolPages/Crypto/PasswordGeneratorPage.swift")

        contains(token, "id: \"slot-\\(offset)\"", "Token rows must retain their slot identity when values regenerate")
        doesNotContain(token, "id: \"\\(offset)-\\(token)\"", "Token values must not participate in row identity")
        contains(uuid, "id: \"slot-\\(offset)\"", "UUID rows must retain their slot identity when values regenerate")
        doesNotContain(uuid, "id: \"\\(offset)-\\(value)\"", "UUID values must not participate in row identity")
        contains(password, "struct GeneratedPassword {", "Password values no longer need model-level random row identity")
        doesNotContain(password, "struct GeneratedPassword: Identifiable", "Password rows must not manufacture identity before UI projection")
        doesNotContain(password, "let id = UUID()", "Password regeneration must not replace every card identity")
        contains(password, "id: \"slot-\\(offset)\"", "Password rows must retain their slot identity when values regenerate")
    }

    @Test func tokenAndPasswordResultHeadersPreferReplacementOverClear() throws {
        let pages = [
            ("Token", try readSource("Sources/XTools/ToolPages/Crypto/TokenGeneratorPage.swift")),
            ("Password", try readSource("Sources/XTools/ToolPages/Crypto/PasswordGeneratorPage.swift"))
        ]

        for (name, source) in pages {
            doesNotContain(source, "IndexClearButton(", "\(name) results must not expose a redundant clear action")
            doesNotContain(source, "clearGeneratedValues", "\(name) must not retain an unconsumed result-clear API")
            doesNotContain(source, "hasClearableContent", "\(name) must not retain state used only by the removed clear action")
            contains(source, "title: \"全部复制\"", "\(name) results must keep the batch copy action")
            doesNotContain(source, "Label(\"重新生成\"", "\(name) must not hand-roll the regenerate button")
            contains(source, "if !workspace.hasAttemptedGeneration { generate() }", "\(name) must keep first-appearance generation without regenerating after navigation")
        }
    }

    @Test func uuidGeneratorUsesPrototypeParameterRowAndValueRows() throws {
        let source = try readSource("Sources/XTools/ToolPages/Crypto/UUIDGeneratorPage.swift")
        let generator = try readSource("Sources/XToolsCore/Crypto/UUIDGenerator.swift")
        let emptyStates = try readSource("Sources/XTools/Shared/Components/IndexEmptyState.swift")
        let rowList = try readSource("Sources/XTools/ToolPages/Workbench/Diagnostics/IndexGeneratedValueRowList.swift")
        let controls = try readSource("Sources/XTools/ToolPages/Workbench/Controls/IndexStepperInput.swift")

        doesNotContain(source, "Stepper(\"", "UUID generator must not use the native Stepper")
        contains(source, "workspaceSemantic: .queryListWorkspace", "UUID must pin parameters above an internally scrolling value list")
        contains(source, "IndexStepperInput(value: $workspace.quantity, range: Self.quantityRange)", "UUID quantity must use the joined prototype stepper")
        contains(controls, "struct IndexStepperInput: View", "The prototype stepper must be a shared control")
        contains(source, "IndexSegmentedControl(", "UUID version must use the shared segmented control")
        contains(source, "range: Self.quantityRange", "UUID quantity must clamp through the stepper range")
        contains(source, "quantityRange = 1...32", "Prototype parameter bounds stay 1...32")
        contains(source, ".onChange(of: workspace.quantity) { _ in generate() }", "UUID output must refresh when the retained quantity changes")
        contains(source, "IndexGeneratedValueRowList(\n                    rows: resultRows,\n                    emptyText: IndexEmptyStateCopy.noResults,\n                    motionGeneration: motionGeneration", "UUID results must use the shared value row list")
        contains(source, "UUIDGenerationVersion", "UUID page must delegate version semantics to Core")
        contains(source, ".onChange(of: workspace.version) { _ in generate() }", "UUID output must refresh when the retained version changes")
        contains(source, "UUID v4 或按时间排序的 UUID v7", "UUID subtitle must distinguish identifiers from security tokens")
        contains(source, "emptyText: IndexEmptyStateCopy.noResults", "UUID empty state must remain factual through the canonical shared copy")
        contains(emptyStates, "public static let noResults = \"暂无匹配结果\"", "The canonical no-results copy must stay defined in the shared empty-state component")
        doesNotContain(source, "安全 Token", "UUID UI must not describe identifiers as security tokens")
        contains(source, "IndexPrimaryActionButton(\n                title: \"生成\",\n                hint: \"⌘↩\",", "Generate must be the prototype primary action with the keycap hint")
        contains(source, ".keyboardShortcut(.return, modifiers: .command)", "Command-Return must regenerate from the keyboard")
        contains(source, "id: \"slot-\\(offset)\"", "Result rows keep slot identity")
        contains(source, "上次生成 ", "The parameter row must surface the last-generation time")
        contains(source, "ToolFeedbackCopy.copiedAll(noun: \"UUID\")", "Batch copy must use the canonical batch toast copy")
        contains(rowList, "let staggerStep: TimeInterval = 0.03", "Row pop-in must keep the prototype 30ms stagger")
        contains(generator, "case v4", "UUID Core must expose v4")
        contains(generator, "case v7", "UUID Core must expose v7")
        contains(generator, "private static let maxCounter = (UInt64(1) << 42) - 1", "UUID v7 counter must leave random tail space")
        contains(generator, "timestamp: timestamp", "UUID v7 bytes must be assembled in Core")
    }

    @Test func tokenGeneratorAutoGeneratesWithoutCustomCharacterSet() throws {
        let source = try readSource("Sources/XTools/ToolPages/Crypto/TokenGeneratorPage.swift")
        let generator = try readSource("Sources/XToolsCore/Crypto/TokenGenerator.swift")
        let preferences = try readSource("Sources/XTools/AppShell/ToolPreferenceStore.swift")

        doesNotContain(source, "customChars", "Token generator must remove custom character state")
        doesNotContain(source, "自定义字符", "Token generator must remove custom character UI")
        doesNotContain(source, "IndexPanel(\"选项\")", "Token generator options must sit directly in the page action row")
        contains(preferences, "\"tools.tokenGenerator.length.v1\",\n        default: 32,", "Token generator retained recipe default length must be 32")
        contains(preferences, "\"tools.tokenGenerator.quantity.v1\",\n        default: 1,", "Token generator retained recipe default quantity must be one")
        contains(source, "range: 1...512", "Token generator length control must support up to 512")
        contains(source, "range: 1...20", "Token generator quantity control must support up to 20")
        contains(source, ".onChange(of: workspace.length) { _ in generate() }", "Token output must refresh when retained length changes")
        contains(source, ".onChange(of: workspace.quantity) { _ in generate() }", "Token output must refresh when retained quantity changes")
        contains(source, ".onChange(of: workspace.lower) { _ in generate() }", "Token output must refresh when retained lowercase recipe changes")
        contains(source, ".onChange(of: workspace.upper) { _ in generate() }", "Token output must refresh when retained uppercase recipe changes")
        contains(source, ".onChange(of: workspace.numbers) { _ in generate() }", "Token output must refresh when retained number recipe changes")
        contains(source, ".onChange(of: workspace.symbols) { _ in generate() }", "Token output must refresh when retained symbol recipe changes")
        contains(source, "TokenGenerator.generate(", "Token page must delegate generation to Core")
        contains(generator, "case emptyCharacterSet", "Token generator Core must keep a typed empty-character-set failure")
        contains(source, "IndexGeneratedValueRowList(", "Token generator must use the shared prototype value row list")
    }

    @Test func tokenGeneratorExposesTypedFormatsWithoutEntropyClaims() throws {
        let source = try readSource("Sources/XTools/ToolPages/Crypto/TokenGeneratorPage.swift")
        let generator = try readSource("Sources/XToolsCore/Crypto/TokenGenerator.swift")

        contains(generator, "enum TokenGenerationMode", "Token formats must be represented by a typed Core mode")
        contains(generator, "case base64URL", "Token Core must expose Base64url mode")
        contains(generator, "case hex", "Token Core must expose Hex mode")
        contains(generator, "case characterSet", "Token Core must preserve character-set mode")
        contains(source, "IndexSegmentedControl(", "Token mode selection must use the shared segmented control")
        contains(source, ".onChange(of: workspace.mode) { _ in generate() }", "Token output must refresh when the representation mode changes")
        contains(source, "Base64url", "Token mode control must label the URL-safe representation")
        contains(source, "Hex", "Token mode control must label the hexadecimal representation")
        contains(source, "\"字符集\"", "Token mode control must distinguish the character-set recipe")
        doesNotContain(source, "估算熵", "The prototype parameter card must not present entropy estimates")
        doesNotContain(source, "低于 64 bit", "The prototype parameter card must not keep the entropy warning caption")
        doesNotContain(source, "高强度随机 Token", "Token page must not make an unconditional strength claim")
    }

    @Test func passwordGeneratorAvoidsStrengthHeuristics() throws {
        let source = try readSource("Sources/XTools/ToolPages/Crypto/PasswordGeneratorPage.swift")
        let generator = try readSource("Sources/XToolsCore/Crypto/PasswordGenerator.swift")

        contains(source, "PasswordGenerator.generate(", "Password page must delegate generation to Core")
        contains(generator, "PasswordComposition.enabledCharacterSets(", "Password generator must keep selected classes as separate required pools")
        contains(generator, "requiredCharacters: requiredSets", "Password generator must guarantee every selected class appears in each password")
        contains(generator, "case emptyCharacterSet", "Password generator Core must keep a typed empty-character-set failure")
        contains(generator, "case requiredCharactersExceedLength", "Password generator Core must distinguish a length/class conflict")
        doesNotContain(source, "badgeText:", "Password cards must not repeat a strength badge")
        doesNotContain(source, "StrengthLevel", "Password page must not depend on removed strength buckets")
        doesNotContain(generator, "StrengthLevel", "Password Core must not expose removed strength buckets")
        doesNotContain(generator, "strength", "Password Core must not classify generated values")
        doesNotContain(source, "高强度随机密码", "Password page must not make an unconditional strength claim")
    }
}
