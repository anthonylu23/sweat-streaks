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
        .executableTarget(
            name: "SweatStreaksApp",
            dependencies: [
                "SweatStreaksCore",
                "SweatStreaksPersistence"
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
        )
    ]
)
