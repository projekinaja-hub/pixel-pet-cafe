// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PixelPetCafe",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "PixelPetCafe",
            path: "Sources/PixelPetCafe",
            resources: [.copy("Resources/Sprites"), .copy("Resources/Sounds")]
        ),
        .testTarget(
            name: "PixelPetCafeTests",
            dependencies: ["PixelPetCafe"],
            path: "Tests/PixelPetCafeTests"
        ),
    ]
)
