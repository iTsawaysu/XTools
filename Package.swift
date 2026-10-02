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
        // Vendored 0.5.2 with a local patch: bare `Document` references are
        // qualified as `CommonMark.Document` because the macOS 27 SDK's
        // SwiftUI exports its own `Document`, which makes upstream 0.5.2
        // fail to compile. Upstream is in maintenance mode.
        .package(path: "Vendor/swift-markdown-ui")
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
                .product(name: "MarkdownUI", package: "swift-markdown-ui")
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
