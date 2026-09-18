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
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", from: "1.10.0"),
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
                .product(name: "CryptoSwift", package: "CryptoSwift"),
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
            path: "tools/EmojiCatalogCompiler"
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
