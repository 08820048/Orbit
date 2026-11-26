// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Orbit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OrbitCore", targets: ["OrbitCore"]),
        .executable(name: "orbit-cli", targets: ["OrbitCLI"]),
        .executable(name: "Orbit", targets: ["OrbitApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
    ],
    targets: [
        .target(
            name: "OrbitCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(name: "OrbitCLI", dependencies: ["OrbitCore"]),
        .executableTarget(
            name: "OrbitApp",
            dependencies: ["OrbitCore", .product(name: "Sparkle", package: "Sparkle")],
            resources: [.copy("Resources/GlassIcons"), .copy("Resources/Backgrounds"), .copy("Resources/BrandLogos")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "OrbitCoreTests", dependencies: ["OrbitCore"]),
    ]
)
