import XToolsCore
import Foundation

guard let outputPath = CommandLine.arguments.dropFirst().first else {
    FileHandle.standardError.write(
        Data("用法：swift run EmojiCatalogCompiler <输出 plist 路径>\n".utf8)
    )
    exit(EXIT_FAILURE)
}

do {
    let data = try EmojiCatalog.compilePrecompiledCatalogData()
    let outputURL = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try data.write(to: outputURL, options: .atomic)
    print("已生成 \(data.count) 字节：\(outputURL.path)")
} catch {
    FileHandle.standardError.write(Data("生成 Emoji 目录失败：\(error)\n".utf8))
    exit(EXIT_FAILURE)
}
