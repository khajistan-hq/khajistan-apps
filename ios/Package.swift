// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KhajistanCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "KhajistanCore", targets: ["KhajistanCore"])],
    targets: [
        .target(
            name: "KhajistanCore",
            path: "Khajistan/Core",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ShuffleTests",
            dependencies: ["KhajistanCore"],
            path: "Tests/ShuffleTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
