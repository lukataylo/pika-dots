// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "PikaDots",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "PikaDots", targets: ["PikaDots"])],
    targets: [
        .executableTarget(name: "PikaDots", resources: [.copy("Resources/Skills")]),
        .testTarget(name: "PikaDotsTests", dependencies: ["PikaDots"])
    ],
    swiftLanguageModes: [.v5]
)
