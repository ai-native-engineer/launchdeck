// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LaunchDeck",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "LaunchDeckCore", targets: ["LaunchDeckCore"]),
        .executable(name: "launchdeck", targets: ["LaunchDeckCLI"]),
        .executable(name: "LaunchDeckApp", targets: ["LaunchDeckApp"]),
    ],
    targets: [
        .target(name: "LaunchDeckCore"),
        .executableTarget(
            name: "LaunchDeckCLI",
            dependencies: ["LaunchDeckCore"]
        ),
        .executableTarget(
            name: "LaunchDeckApp",
            dependencies: ["LaunchDeckCore"]
        ),
        .testTarget(
            name: "LaunchDeckCoreTests",
            dependencies: ["LaunchDeckCore"]
        ),
    ]
)
