import Foundation
import Testing
@testable import XToolsCore

struct ExternalImageOptimizerTests {
    @Test func noOptimizationByDefaultLeavesDataUntouched() {
        #expect(NoExternalImageOptimizer().optimize(Data([1, 2, 3]), format: .png, lossy: false) == nil)
        #expect(NoExternalImageOptimizer().optimize(Data([1, 2, 3]), format: .png, lossy: true) == nil)
    }

    @Test func locatorResolvesExecutableToolsInSearchDirectories() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("xtools-optimizer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let pngquant = directory.appendingPathComponent("pngquant")
        #expect(FileManager.default.createFile(atPath: pngquant.path, contents: Data(), attributes: [.posixPermissions: 0o755]))

        let locator = FileSystemImageOptimizerToolLocator(searchDirectories: [directory.path])

        #expect(locator.pngquantPath == pngquant.path)
        #expect(locator.oxipngPath == nil)
    }

    @Test func locatorSkipsNonExecutableEntries() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("xtools-optimizer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // 无可执行权限的同名文件不算可用工具。
        let pngquant = directory.appendingPathComponent("pngquant")
        #expect(FileManager.default.createFile(atPath: pngquant.path, contents: Data(), attributes: [.posixPermissions: 0o644]))

        let locator = FileSystemImageOptimizerToolLocator(searchDirectories: [directory.path])

        #expect(locator.pngquantPath == nil)
    }

    @Test func locatorReturnsNilWhenDirectoriesAreMissing() {
        let missing = NSTemporaryDirectory() + "/xtools-optimizer-missing-\(UUID().uuidString)"
        let locator = FileSystemImageOptimizerToolLocator(searchDirectories: [missing])

        #expect(locator.pngquantPath == nil)
        #expect(locator.oxipngPath == nil)
    }
}
