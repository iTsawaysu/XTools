// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "XTools",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "XTools", targets: ["XTools"])
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.13.6"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.3"),
        // Markdown 预览的解析内核：SwiftUI 渲染层是 XTools 自有的
        // MarkdownDocument/IndexMarkdownPreviewContent（ToolPages/Workbench/Text）。
        .package(url: "https://github.com/swiftlang/swift-cmark.git", from: "0.8.0")
    ],
    targets: [
        .target(
            name: "XToolsCore",
            dependencies: [
                .product(name: "SwiftSoup", package: "SwiftSoup"),
                .product(name: "Yams", package: "Yams")
            ],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ],
            linkerSettings: [
                .linkedLibrary("icucore")
            ]
        ),
        .executableTarget(
            name: "XTools",
            dependencies: [
                "XToolsCore",
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark")
            ],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "EmojiCatalogCompiler",
            dependencies: ["XToolsCore"],
            path: "tools/EmojiCatalogCompiler",
            resources: [
                // emoji-test.txt 只随编译工具携带：运行时 bundle 不再包含该
                // 669KB 的 Unicode 数据源（plist 才是运行时目录）。
                // zh-annotations.xml（CLDR zh 注解）同样只作编译输入，
                // 其关键词在编译期并入 plist 的 searchText。
                .copy("emoji-test.txt"),
                .copy("zh-annotations.xml")
            ]
        ),
        .testTarget(
            name: "XToolsTests",
            dependencies: ["XToolsCore", "XTools"],
            path: "Tests/XToolsTests",
            resources: [
                .copy("Fixtures/test.md")
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
