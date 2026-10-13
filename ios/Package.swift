// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KhajistanCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "KhajistanCore", targets: ["KhajistanCore"])],
    targets: [
        .target(name: "KhajistanCore", path: "Khajistan/Core"),
        .testTarget(name: "KhajistanCorePackageTests", dependencies: ["KhajistanCore"], path: "Tests/PackageTests")
    ],
    swiftLanguageModes: [.v5]
)
