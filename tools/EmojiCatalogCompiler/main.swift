import XToolsCore
import Foundation

guard let outputPath = CommandLine.arguments.dropFirst().first else {
    FileHandle.standardError.write(
        Data("用法：swift run EmojiCatalogCompiler <输出 plist 路径>\n".utf8)
    )
    exit(EXIT_FAILURE)
}

do {
    // emoji-test.txt 随编译工具 bundle（Package.swift 的 .copy）提供：
    // 数据注入 EmojiCatalog，XToolsCore 运行时资源不再包含该 txt。
    guard let sourceURL = Bundle.module.url(forResource: "emoji-test", withExtension: "txt") else {
        FileHandle.standardError.write(
            Data("缺少编译输入 emoji-test.txt：应位于 tools/EmojiCatalogCompiler 并随工具 bundle 提供。\n".utf8)
        )
        exit(EXIT_FAILURE)
    }
    let sourceData = try String(contentsOf: sourceURL, encoding: .utf8)

    // CLDR zh 注解（LDML annotations）同样只随编译工具 bundle 提供：
    // 解析出的中文关键词并入 searchText，使目录支持中文搜索。
    guard let annotationsURL = Bundle.module.url(forResource: "zh-annotations", withExtension: "xml") else {
        FileHandle.standardError.write(
            Data("缺少编译输入 zh-annotations.xml：应位于 tools/EmojiCatalogCompiler 并随工具 bundle 提供。\n".utf8)
        )
        exit(EXIT_FAILURE)
    }
    let annotationsXML = try String(contentsOf: annotationsURL, encoding: .utf8)

    let data = try EmojiCatalog.compilePrecompiledCatalogData(
        sourceData: sourceData,
        chineseAnnotationsXML: annotationsXML
    )
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
