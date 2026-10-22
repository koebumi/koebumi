import Foundation
import Testing
@testable import Koebumi

@Suite struct FileNameFixerTests {
    /// このリポジトリのファイルの一部（README.md は 2 つのフォルダにある）
    private let files = ProjectFiles(paths: [
        "Package.swift", "README.md", "docs/README.md", "scripts/build-app.sh", "Sources/Speak/AI/AgentInput.swift",
        "Sources/Speak/System/CodingAgent.swift", "Sources/Speak/Core/DictationController.swift", "Sources/Speak/Core/Settings.swift",
        "Sources/Speak/UI/MainView.swift", "Tests/SpeakTests/AgentInputTests.swift",
    ])

    private func fixed(_ spoken: String) -> String { FileNameFixer.fix(spoken, files: files).text }

    @Test func fixesNamesSpokenInKatakana() {
        #expect(fixed("エージェントインプットを直して") == "AgentInputを直して")
        #expect(fixed("ディクテーションコントローラーの録音を見て") == "DictationControllerの録音を見て")
        // 音声認識が語の間に空白を入れた
        #expect(fixed("エージェント インプットを直して") == "AgentInputを直して")
        #expect(fixed("ビルドアップのスクリプト") == "build-appのスクリプト")
        #expect(FileNameFixer.fix("コーディングエージェントとエージェントインプット", files: files).names == ["CodingAgent", "AgentInput"])
    }

    @Test func fixesOneWordNamesOnlyWithAnExtensionOrFile() {
        #expect(fixed("パッケージドットスウィフトに足して") == "Package.swiftに足して")
        #expect(fixed("セッティングス ドット スウィフト") == "Settings.swift")
        #expect(fixed("リードミーファイルを更新して") == "README ファイルを更新して")
        #expect(fixed("ビルドアップドットシェル") == "build-app.sh")
        // ふつうの言葉は、そのまま
        #expect(fixed("パッケージを更新して") == "パッケージを更新して")
        #expect(fixed("インプットを確認して") == "インプットを確認して")
        #expect(fixed("メインの処理を直して") == "メインの処理を直して")
        // 拡張子が違えば直さない
        #expect(fixed("パッケージドットジェイソン") == "パッケージドットジェイソン")
    }

    @Test func mentionsFilesWithAt() {
        #expect(fixed("アット ディクテーションコントローラーを見て") == "@Sources/Speak/Core/DictationController.swiftを見て")
        #expect(fixed("アットパッケージドットスウィフト") == "@Package.swift")
        // README.md は 2 つのフォルダにあるので、浅いほう
        #expect(fixed("アット リードミーファイル") == "@README.md")
    }

    @Test func fixesNamesTheRecognizerWroteInLetters() {
        #expect(fixed("Agent Inputのテストを追加して") == "AgentInputのテストを追加して")
        #expect(fixed("fix the agent input tests please") == "fix the AgentInputTests please")
        #expect(fixed("agent input.swift") == "AgentInput.swift")
        // 正しく書けているものと、1 語の名前は変えない
        #expect(fixed("AgentInput を直して") == "AgentInput を直して")
        #expect(fixed("update the readme") == "update the readme")
    }

    @Test func hintsChangedFilesFirst() {
        let files = ProjectFiles(paths: ["Package.swift", "Sources/A/AgentInput.swift", "Sources/A/CodingAgent.swift"],
                                 changed: ["Sources/A/CodingAgent.swift", "Package.swift"])
        #expect(FileNameFixer.hints(files) == ["CodingAgent", "AgentInput"])
    }

    @Test func readsGitOutput() {
        let files = ProjectFiles(lsFiles: "Package.swift\nSources/A/AgentInput.swift\n",
                                 status: " M Sources/A/AgentInput.swift\nR  Old.swift -> New.swift\n?? メモ.txt\n")
        #expect(files.paths == ["Package.swift", "Sources/A/AgentInput.swift"])
        #expect(files.changed == ["Sources/A/AgentInput.swift", "New.swift", "メモ.txt"])
    }

    @Test func readsFilesOnThisMacWithGit() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("speak-files-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: root) }
        try FileManager.default.createDirectory(atPath: root + "/Sources", withIntermediateDirectories: true)
        try Data().write(to: URL(fileURLWithPath: root + "/Sources/AgentInput.swift"))
        try Data("build/\n".utf8).write(to: URL(fileURLWithPath: root + "/.gitignore"))
        try FileManager.default.createDirectory(atPath: root + "/build", withIntermediateDirectories: true)
        try Data().write(to: URL(fileURLWithPath: root + "/build/Ignored.swift"))
        _ = try #require(Subprocess.run("/usr/bin/env", ["git", "-C", root, "init", "-q"], timeout: 5))
        let files = ProjectFiles.read(directory: root)
        // まだ追加していないファイルも読み、.gitignore のものは読まない
        #expect(Set(files.paths) == [".gitignore", "Sources/AgentInput.swift"])
        #expect(Set(files.changed) == [".gitignore", "Sources/"])
    }

    @Test func readsFilesFromTheRemoteListing() throws {
        let output = "\u{2}/home/me\n\u{2}/home/me/app\n\u{1}:git-files\nmain.py\nsrc/AgentInput.py\n\u{1}:git-status\n M src/AgentInput.py\n\u{3}\n"
        let files = try #require(RemoteFiles.parse(Data(output.utf8)))
        #expect(files.projectFiles.paths == ["main.py", "src/AgentInput.py"])
        #expect(files.projectFiles.changed == ["src/AgentInput.py"])
    }

    @Test func keepsLowercaseNamesAtTheStartOfASentence() async throws {
        let request = PolishRequest(transcript: "build-appを直して", mode: .dictate, sourceLanguages: ["ja-JP"], targetLanguage: nil,
                                    appName: "Claude Code", category: .ai, styleDescription: AppCategory.ai.defaultStyleDescription,
                                    personalStyle: nil, vocabulary: ["build-app"], corrections: [], codingAgent: true)
        #expect(try await Polisher.run(request, engine: nil).text == "build-appを直して")
    }
}
