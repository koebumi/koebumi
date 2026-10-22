import AudioCommon
import Foundation
import Testing
@testable import Koebumi

@Suite struct LocalSpeechModelTests {
    @Test func qwenGetsEnglishLanguageNameOnlyForASingleLanguage() {
        #expect(LocalSpeechModel.qwen3Small.languageHint(for: ["ja-JP"]) == "Japanese")
        #expect(LocalSpeechModel.qwen3Large.languageHint(for: ["zh-CN"]) == "Chinese")
        // 話す言語が複数なら渡さず、自動判定に任せる
        #expect(LocalSpeechModel.qwen3Small.languageHint(for: ["ja-JP", "en-US"]) == nil)
    }

    @Test func whisperAndCohereGetIsoCodes() {
        #expect(LocalSpeechModel.whisperTurbo.languageHint(for: ["en-GB"]) == "en")
        // Cohere は言語を判定しないので、先頭の言語を必ず渡す
        #expect(LocalSpeechModel.cohere.languageHint(for: ["ja-JP", "en-US"]) == "ja")
    }

    @Test func mossNeverGetsALanguage() {
        #expect(LocalSpeechModel.moss.languageHint(for: ["ja-JP"]) == nil)
    }

    @Test func cohereRejectsUnsupportedLanguages() {
        #expect(LocalSpeechModel.cohere.supports("ko-KR"))
        #expect(!LocalSpeechModel.cohere.supports("th-TH"))
        #expect(LocalSpeechModel.qwen3Small.supports("th-TH"))
    }

    @Test func contextEchoIsDetectedOnlyWhenTheTermListIsWrittenOut() {
        let terms = ["Dark Mode Bird App Icon", "Soyomi", "アプリ", "Claude"]
        // 実際に Qwen3-ASR 0.6B が返したもの
        #expect(LocalSpeechRuntime.echoesContext("Dark Mode Bird App Icon, Soyomi, アプリ, Claude, PHPに G クレースが発見された。", terms: terms))
        #expect(LocalSpeechRuntime.echoesContext("Dark Mode Bird App Icon, Soyomi, アプリ, Claude", terms: terms))
        #expect(LocalSpeechRuntime.echoesContext("FGD-PINNs, Claude。 PHPに脆弱性が発見された", terms: ["FGD-PINNs", "Claude"]))
        #expect(LocalSpeechRuntime.echoesContext("Claude.", terms: ["Claude"]))
        // 先頭の画面の語を飛ばして、辞書の語から書き出した（実際に返したもの）
        let withScreen = ["Dark Mode Bird App Icon", "Soyomi", "新版", "音声入力時", "起動", "Ghostty", "zhaoくん", "ClaudeCode"]
        #expect(LocalSpeechRuntime.echoesContext("新版, 音声入力時, 起動, Ghostty, zhaoくん, ClaudeCode, ClaudeCode", terms: withScreen))
        #expect(!LocalSpeechRuntime.echoesContext("Ghostty, これ見て", terms: withScreen))
        // 語から話し始めた文や、文脈を書き出していない結果は認識し直さない
        #expect(!LocalSpeechRuntime.echoesContext("Claudeに聞いてみて。", terms: ["Claude"]))
        #expect(!LocalSpeechRuntime.echoesContext("今日は夜ご飯うどん食べたよ。", terms: terms))
        #expect(!LocalSpeechRuntime.echoesContext("", terms: terms))
        #expect(!LocalSpeechRuntime.echoesContext("Claude.", terms: []))
    }

    @Test func longAudioIsSplitAtTheQuietestPause() {
        // 1 秒の音 → 0.5 秒の無音 → 1 秒の音 → 0.5 秒の無音 → 1 秒の音（16 kHz で 4 秒）
        let tone = (0..<16000).map { Float(sin(Double($0) * 0.3)) * 0.5 }
        let pause = [Float](repeating: 0, count: 8000)
        let audio = RecordedAudio(samples: tone + pause + tone + pause + tone)
        let parts = audio.split(maxDuration: 2)
        #expect(parts.allSatisfy { $0.duration <= 2 })
        #expect(parts.flatMap(\.samples) == audio.samples)
        // 区切りは無音の中に置く
        var cut = 0
        for part in parts.dropLast() {
            cut += part.samples.count
            #expect(audio.samples[cut] == 0, "\(cut)")
        }
        #expect(RecordedAudio(samples: tone).split(maxDuration: 15).count == 1)
    }

    @Test func tokenLimitFollowsTheAudioLength() {
        #expect(LocalSpeechRuntime.maxTokens(for: 6) == 114)
        #expect(LocalSpeechRuntime.maxTokens(for: 30) == 474)
    }

    @Test func splitTranscriptsAreJoinedWithSpacesOnlyBetweenLatinText() {
        #expect(LocalSpeechRuntime.joinTranscripts(["今日は晴れ。", "明日は雨。"]) == "今日は晴れ。明日は雨。")
        #expect(LocalSpeechRuntime.joinTranscripts(["My name is Kosuke.", "Today's meeting is at 3."]) == "My name is Kosuke. Today's meeting is at 3.")
        #expect(LocalSpeechRuntime.joinTranscripts(["", " Claude ", "に聞いて。"]) == "Claudeに聞いて。")
    }

    @Test func ratingsStayInRange() {
        for m in LocalSpeechModel.allCases {
            #expect((1...5).contains(m.speed) && (1...5).contains(m.accuracy), "\(m)")
        }
        #expect(LocalSpeechModel.allCases.filter(\.isRecommended).count == 1)
    }
}

@Suite struct SpeechEngineChoiceTests {
    @Test func localChoiceRoundTripsThroughSettings() {
        var s = AppSettings()
        SpeechEngineChoice.local(.moss).apply(to: &s)
        #expect(s.sttProvider == .local)
        #expect(s.localSpeechModel == .moss)
        #expect(SpeechEngineChoice(s) == .local(.moss))
    }

    @Test func switchingToCloudKeepsTheChosenLocalModel() {
        var s = AppSettings()
        SpeechEngineChoice.local(.whisperTurbo).apply(to: &s)
        SpeechEngineChoice.cloud(.groq).apply(to: &s)
        #expect(SpeechEngineChoice(s) == .cloud(.groq))
        #expect(s.localSpeechModel == .whisperTurbo)
    }

    @Test func unknownLocalModelFallsBackToTheRecommendedOne() {
        var s = AppSettings()
        s.sttProvider = .local
        s.sttModels[STTProvider.local.rawValue] = "removed-model"
        #expect(s.localSpeechModel == .qwen3Small)
    }

    @Test func onlyEnginesWithoutDetectionGetASingleLanguage() {
        var s = AppSettings()
        s.dictationLanguages = ["ja-JP", "en-US"]
        s.sttProvider = .apple
        #expect(s.sttLanguages(current: "en-US") == ["en-US"])
        SpeechEngineChoice.local(.qwen3Small).apply(to: &s)
        #expect(s.sttLanguages(current: "en-US") == ["ja-JP", "en-US"])
        SpeechEngineChoice.local(.cohere).apply(to: &s)
        #expect(s.sttNeedsFixedLanguage)
        #expect(s.sttLanguages(current: "en-US") == ["en-US"])
    }

    @Test func localModelsCountAsOnDevice() {
        var s = AppSettings()
        SpeechEngineChoice.local(.qwen3Small).apply(to: &s)
        #expect(s.sttRunsLocally)
    }
}

@Suite struct LocalSpeechRuntimeTests {
    @Test func downloadingAnotherModelKeepsTheModelInUse() async throws {
        let fake = FakeModelFiles(downloaded: [.qwen3Small])
        let runtime = LocalSpeechRuntime(files: fake.files)
        await runtime.retain(.qwen3Small)
        let download = Task { try await runtime.download(.qwen3Large) { _ in } }
        await fake.waitForDownload()

        _ = try await runtime.model(.qwen3Small)
        fake.finishDownload()
        try await download.value
        _ = try await runtime.model(.qwen3Small)
        // ダウンロードの前後で読み込み直していない
        #expect(fake.loads(.qwen3Small) == 1)
        // 選んでいないモデルは、読み込めることを確かめたら手放す
        #expect(fake.unloaded == [.qwen3Large])
    }

    @Test func modelStaysDownloadingWhileAnotherModelLoads() async throws {
        let fake = FakeModelFiles(downloaded: [.qwen3Small])
        let runtime = LocalSpeechRuntime(files: fake.files)
        let download = Task { try await runtime.download(.qwen3Large) { _ in } }
        await fake.waitForDownload()

        _ = try await runtime.model(.qwen3Small)
        #expect(await thrownError { try await runtime.model(.qwen3Large) } == .modelDownloading)
        fake.finishDownload()
        try await download.value
    }

    @Test func downloadedSelectedModelIsUsedWithoutLoadingAgain() async throws {
        let fake = FakeModelFiles(downloaded: [])
        let runtime = LocalSpeechRuntime(files: fake.files)
        await runtime.retain(.qwen3Large)
        let download = Task { try await runtime.download(.qwen3Large) { _ in } }
        await fake.waitForDownload()
        fake.finishDownload()
        try await download.value

        _ = try await runtime.model(.qwen3Large)
        #expect(fake.loads(.qwen3Large) == 0)
        #expect(fake.unloaded.isEmpty)
    }

    @Test func selectingAModelThatIsNotDownloadedReleasesThePreviousOne() async throws {
        let fake = FakeModelFiles(downloaded: [.qwen3Small])
        let runtime = LocalSpeechRuntime(files: fake.files)
        await runtime.retain(.qwen3Small)
        await runtime.retain(.qwen3Large)
        #expect(await thrownError { try await runtime.model(.qwen3Large) } == .modelNotDownloaded)
        #expect(fake.unloaded == [.qwen3Small])

        // 手放したので、もう一度使うときは読み込み直す
        _ = try await runtime.model(.qwen3Small)
        #expect(fake.loads(.qwen3Small) == 2)
    }

    @Test func selectingAnotherEngineUnloadsTheModel() async {
        let fake = FakeModelFiles(downloaded: [.qwen3Small])
        let runtime = LocalSpeechRuntime(files: fake.files)
        await runtime.retain(.qwen3Small)
        await runtime.retain(nil)
        #expect(fake.unloaded == [.qwen3Small])
    }

    @Test func deletingTheModelUnloadsIt() async {
        let fake = FakeModelFiles(downloaded: [.qwen3Small])
        let runtime = LocalSpeechRuntime(files: fake.files)
        await runtime.retain(.qwen3Small)
        await runtime.release(.qwen3Small)
        #expect(fake.unloaded == [.qwen3Small])
    }
}

private enum RuntimeError { case modelDownloading, modelNotDownloaded, other }

private func thrownError(_ body: () async throws -> Any) async -> RuntimeError? {
    do {
        _ = try await body()
        return nil
    } catch TranscriptionError.modelDownloading {
        return .modelDownloading
    } catch TranscriptionError.modelNotDownloaded {
        return .modelNotDownloaded
    } catch {
        return .other
    }
}

private final class FakeModel: SpeechRecognitionModel {
    let id: LocalSpeechModel
    init(_ id: LocalSpeechModel) { self.id = id }
    var inputSampleRate: Int { 16_000 }
    func transcribe(audio: [Float], sampleRate: Int, language: String?) -> String { "" }
}

/// 本物のファイルに触らないモデルの置き場。ダウンロードは finishDownload() を呼ぶまで終わらない。
private final class FakeModelFiles: @unchecked Sendable {
    private let lock = NSLock()
    private var downloaded: Set<LocalSpeechModel>
    private var loadCounts: [LocalSpeechModel: Int] = [:]
    private var unloadedModels: [LocalSpeechModel] = []
    private var pendingDownload: CheckedContinuation<Void, Never>?
    private let started: AsyncStream<Void>
    private let startedContinuation: AsyncStream<Void>.Continuation

    init(downloaded: Set<LocalSpeechModel>) {
        self.downloaded = downloaded
        (started, startedContinuation) = AsyncStream.makeStream()
    }

    var files: LocalModelFiles {
        LocalModelFiles(
            isDownloaded: { [self] id in lock.withLock { downloaded.contains(id) } },
            load: { [self] id, offline, _ in
                if offline {
                    lock.withLock { loadCounts[id, default: 0] += 1 }
                } else {
                    await withCheckedContinuation { continuation in
                        lock.withLock { pendingDownload = continuation }
                        startedContinuation.yield()
                    }
                }
                return FakeModel(id)
            },
            markReady: { [self] id in lock.withLock { _ = downloaded.insert(id) } },
            unload: { [self] model in lock.withLock { unloadedModels.append((model as! FakeModel).id) } }
        )
    }

    /// 読み込み（ダウンロードを除く）の回数
    func loads(_ id: LocalSpeechModel) -> Int {
        lock.withLock { loadCounts[id, default: 0] }
    }

    /// 手放したモデル（手放した順）
    var unloaded: [LocalSpeechModel] {
        lock.withLock { unloadedModels }
    }

    func waitForDownload() async {
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()
    }

    func finishDownload() {
        let continuation = lock.withLock {
            defer { pendingDownload = nil }
            return pendingDownload
        }
        continuation?.resume()
    }
}
