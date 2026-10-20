// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Speak",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Speak",
            path: "Sources/Speak",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "SpeakTests",
            dependencies: ["Speak"],
            path: "Tests/SpeakTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
