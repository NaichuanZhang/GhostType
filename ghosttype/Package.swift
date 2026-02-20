// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GhostType",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/raspu/Highlightr.git", from: "2.2.0"),
        .package(url: "https://github.com/apple/swift-testing.git", branch: "release/6.0"),
    ],
    targets: [
        .target(
            name: "GhostTypeLib",
            dependencies: ["Highlightr"],
            path: "GhostType",
            exclude: [
                "Resources/Info.plist",
                "Resources/GhostType.entitlements",
                "App/main.swift",
            ],
            resources: [
                .copy("Resources/Assets.xcassets"),
            ]
        ),
        .executableTarget(
            name: "GhostType",
            dependencies: ["GhostTypeLib"],
            path: "GhostTypeMain"
        ),
        .testTarget(
            name: "GhostTypeTests",
            dependencies: [
                "GhostTypeLib",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests/GhostTypeTests"
        ),
    ]
)
