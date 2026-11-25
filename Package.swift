// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Orbit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "OrbitCore", targets: ["OrbitCore"]),
        .executable(name: "orbit-cli", targets: ["OrbitCLI"]),
        .executable(name: "Orbit", targets: ["OrbitApp"]),
    ],
    targets: [
        .target(
            name: "OrbitCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(name: "OrbitCLI", dependencies: ["OrbitCore"]),
        .executableTarget(
            name: "OrbitApp",
            dependencies: ["OrbitCore"],
            resources: [.copy("Resources/GlassIcons"), .copy("Resources/Backgrounds")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "OrbitCoreTests", dependencies: ["OrbitCore"]),
    ]
)
