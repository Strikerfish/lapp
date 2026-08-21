// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Lapp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Lapp",
            path: "Sources/Lapp",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
