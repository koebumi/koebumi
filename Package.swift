// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Speak",
    platforms: [.macOS("26.0")],
    dependencies: [
        // この Mac で動かす音声認識モデル（Qwen3-ASR・Whisper・MOSS・Cohere）。リリースのタグがないので、動作を確かめたコミットに固定する。
        .package(url: "https://github.com/soniqo/speech-swift", revision: "3f58a58a8f867a4c87b97dbf4d6050d6a88ef665"),
    ],
    targets: [
        .executableTarget(
            name: "Speak",
            dependencies: [
                .product(name: "AudioCommon", package: "speech-swift"),
                .product(name: "Qwen3ASR", package: "speech-swift"),
                .product(name: "WhisperASR", package: "speech-swift"),
                .product(name: "MossTranscribe", package: "speech-swift"),
                .product(name: "CohereTranscribeASR", package: "speech-swift"),
            ],
            path: "Sources/Speak",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "SpeakTests",
            dependencies: [
                "Speak",
                // テストで偽のモデル（SpeechRecognitionModel）を作る
                .product(name: "AudioCommon", package: "speech-swift"),
            ],
            path: "Tests/SpeakTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
