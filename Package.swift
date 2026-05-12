// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SweatStreaks",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "SweatStreaksCore", targets: ["SweatStreaksCore"]),
        .library(name: "SweatStreaksPersistence", targets: ["SweatStreaksPersistence"]),
        .library(name: "SweatStreaksProviderSupport", targets: ["SweatStreaksProviderSupport"]),
        .library(name: "SweatStreaksProviderGitHub", targets: ["SweatStreaksProviderGitHub"]),
        .library(name: "SweatStreaksProviderLeetCode", targets: ["SweatStreaksProviderLeetCode"]),
        .library(name: "SweatStreaksProviderLocalSupport", targets: ["SweatStreaksProviderLocalSupport"]),
        .library(name: "SweatStreaksProviderCodex", targets: ["SweatStreaksProviderCodex"]),
        .library(name: "SweatStreaksProviderClaudeCode", targets: ["SweatStreaksProviderClaudeCode"]),
        .executable(name: "SweatStreaksApp", targets: ["SweatStreaksApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0")
    ],
    targets: [
        .target(
            name: "SweatStreaksCore"
        ),
        .target(
            name: "SweatStreaksPersistence",
            dependencies: [
                "SweatStreaksCore",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .target(
            name: "SweatStreaksProviderSupport",
            dependencies: [
                "SweatStreaksCore"
            ]
        ),
        .target(
            name: "SweatStreaksProviderGitHub",
            dependencies: [
                "SweatStreaksCore",
                "SweatStreaksProviderSupport"
            ]
        ),
        .target(
            name: "SweatStreaksProviderLeetCode",
            dependencies: [
                "SweatStreaksCore",
                "SweatStreaksProviderSupport"
            ]
        ),
        .target(
            name: "SweatStreaksProviderLocalSupport",
            dependencies: [
                "SweatStreaksCore"
            ]
        ),
        .target(
            name: "SweatStreaksProviderCodex",
            dependencies: [
                "SweatStreaksCore",
                "SweatStreaksProviderLocalSupport"
            ]
        ),
        .target(
            name: "SweatStreaksProviderClaudeCode",
            dependencies: [
                "SweatStreaksCore",
                "SweatStreaksProviderLocalSupport"
            ]
        ),
        .executableTarget(
            name: "SweatStreaksApp",
            dependencies: [
                "SweatStreaksCore",
                "SweatStreaksPersistence",
                "SweatStreaksProviderClaudeCode",
                "SweatStreaksProviderCodex",
                "SweatStreaksProviderGitHub",
                "SweatStreaksProviderLeetCode"
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "SweatStreaksCoreTests",
            dependencies: ["SweatStreaksCore"]
        ),
        .testTarget(
            name: "SweatStreaksPersistenceTests",
            dependencies: [
                "SweatStreaksCore",
                "SweatStreaksPersistence"
            ]
        ),
        .testTarget(
            name: "SweatStreaksAppTests",
            dependencies: [
                "SweatStreaksApp",
                "SweatStreaksCore",
                "SweatStreaksPersistence"
            ]
        ),
        .testTarget(
            name: "SweatStreaksProviderGitHubTests",
            dependencies: [
                "SweatStreaksCore",
                "SweatStreaksProviderGitHub",
                "SweatStreaksProviderSupport"
            ]
        ),
        .testTarget(
            name: "SweatStreaksProviderLeetCodeTests",
            dependencies: [
                "SweatStreaksCore",
                "SweatStreaksProviderLeetCode",
                "SweatStreaksProviderSupport"
            ]
        ),
        .testTarget(
            name: "SweatStreaksProviderCodexTests",
            dependencies: [
                "SweatStreaksCore",
                "SweatStreaksProviderCodex",
                "SweatStreaksProviderLocalSupport"
            ]
        ),
        .testTarget(
            name: "SweatStreaksProviderClaudeCodeTests",
            dependencies: [
                "SweatStreaksCore",
                "SweatStreaksProviderClaudeCode",
                "SweatStreaksProviderLocalSupport"
            ]
        )
    ]
)
