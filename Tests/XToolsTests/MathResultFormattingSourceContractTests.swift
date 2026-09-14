import Foundation
import Testing

struct MathResultFormattingSourceContractTests {
    @Test func mathResultKeepsAStableCopyActionWithoutAnimatingLiveValues() throws {
        let page = try readSource("Sources/XTools/ToolPages/Utility/MathEvaluatorPage.swift")
        let heroStat = try readSource("Sources/XTools/Shared/Components/IndexHeroStat.swift")

        contains(page, "private var validResult: String?", "Math page must derive copy availability from the current live evaluation")
        contains(page, "IndexHeroStat(value: resultText, copyable: validResult != nil)", "Math result must render through the shared hero stat and gate its copy action on the current live evaluation")
        contains(heroStat, "if copyable && !value.isEmpty {", "The shared hero stat must suppress its copy affordance while no valid result is present")
        contains(heroStat, "IndexCopyButton(text: value, iconOnly: true)", "The shared hero stat must own the copy action through the shared copy button")
        appearsBefore(page, "IndexPanel(\"表达式\")", "IndexHeroStat(value: resultText, copyable: validResult != nil)", "Math result must stay below its expression input")
        appearsBefore(page, "IndexHeroStat(value: resultText, copyable: validResult != nil)", "IndexPanel(\"说明\")", "Math result must stay above the help panel")
        doesNotContain(page, "resultText)\n                    .toolMotionTextSwap", "High-frequency valid math results must remain immediate")
        doesNotContain(page, "@Published var history", "Math result formatting must not grow into calculator history state")
    }

    @Test func mathSupportCopyUsesScannableStaticRowsWithoutNewModes() throws {
        let page = try readSource("Sources/XTools/ToolPages/Utility/MathEvaluatorPage.swift")

        contains(page, "mathHelpRow(\"运算符\"", "Math help must separate supported operators into a scannable row")
        contains(page, "mathHelpRow(\"常量\"", "Math help must separate constants into a scannable row")
        contains(page, "mathHelpRow(\"函数\"", "Math help must separate functions into a scannable row")
        contains(page, "mathHelpRow(\"三角函数\"", "Math help must state the radians contract in its own row")
        doesNotContain(page, "angleMode", "Math formatting polish must not add angle-mode state")
        doesNotContain(page, "unitConversion", "Math formatting polish must not add unit-conversion state")
    }
}
