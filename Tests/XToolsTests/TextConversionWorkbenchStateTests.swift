@testable import XTools
import Testing

struct TextConversionWorkbenchStateTests {
    @Test @MainActor func converterInitialModeUsesValidRequestAndFallsBackSafely() {
        let modes = [
            IndexConverterMode(id: "enc", label: "编码"),
            IndexConverterMode(id: "dec", label: "解码")
        ]

        #expect(IndexConverterPage.resolvedInitialMode(requested: "dec", modes: modes) == "dec")
        #expect(IndexConverterPage.resolvedInitialMode(requested: "missing", modes: modes) == "enc")
        #expect(IndexConverterPage.resolvedInitialMode(requested: nil, modes: modes) == "enc")
        #expect(IndexConverterPage.resolvedInitialMode(requested: "dec", modes: []) == "")
    }

    @Test func saveContentTypeFollowsTheDefaultFilenameExtension() {
        #expect(IndexTextConversionSaveContentType.contentType(for: "json-output.json")?.identifier == "public.json")
        #expect(IndexTextConversionSaveContentType.contentType(for: "sql-output.sql")?.identifier == "org.iso.sql")
        #expect(IndexTextConversionSaveContentType.contentType(for: "xml-output.xml")?.identifier == "public.xml")
        #expect(IndexTextConversionSaveContentType.contentType(for: "yaml-output.yaml")?.identifier == "public.yaml")
        #expect(IndexTextConversionSaveContentType.contentType(for: "text-output.txt")?.identifier == "public.plain-text")
        #expect(IndexTextConversionSaveContentType.contentType(for: "output") == nil)
    }
}
