import Testing
@testable import XToolsCore

struct HTMLReadabilityScriptResourceTests {
    @Test func loadsTheBundledReadabilityScript() throws {
        let script = try HTMLReadabilityScriptResource.load()

        #expect(!script.isEmpty)
        #expect(script.contains("Readability"), "The bundled 0.6.0 script must expose the Readability constructor")
    }

    @Test func repeatedLoadsReturnTheSameCachedScript() throws {
        // 进程级缓存：第二次起不再读盘；内容必须与首次一致且稳定。
        let first = try HTMLReadabilityScriptResource.load()
        let second = try HTMLReadabilityScriptResource.load()

        #expect(first == second)
        #expect(!second.isEmpty)
    }
}
