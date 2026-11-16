// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MathPad",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MathPad",
            path: "Sources/MathPad",
            resources: [.copy("Resources/web"), .copy("Resources/vendor")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
