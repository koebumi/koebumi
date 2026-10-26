import AVFoundation
import Foundation
import Testing
@testable import Koebumi

/// この Mac のモデルで、録音しながら書き起こすセッション（LocalModelSession）
@Suite struct LiveTranscriptionTests {
    /// 偽の書き起こし。本物と同じく 30 秒以内に区切り、区間ごとにサンプル数を書く。呼ばれた音声の長さを覚えておく
    final class FakeModel: @unchecked Sendable {
        private let lock = NSLock()
        private var calls: [Int] = []
        private var partials: [String] = []

        var callCount: Int { lock.withLock { calls.count } }
        var calledLengths: [Int] { lock.withLock { calls } }
        var lastPartial: String? { lock.withLock { partials.last } }

        func transcribe(_ audio: RecordedAudio) -> String {
            lock.withLock { calls.append(audio.samples.count) }
            return Self.expected(audio)
        }

        func received(_ text: String) {
            lock.withLock { partials.append(text) }
        }

        /// 録音が終わってからまとめて認識したときの結果
        static func expected(_ audio: RecordedAudio) -> String {
            LocalSpeechRuntime.joinTranscripts(audio.split(maxDuration: LocalModelSession.partDuration).map { "\($0.samples.count)" })
        }
    }

    func makeSession(_ model: FakeModel) -> LocalModelSession {
        LocalModelSession(onPartial: { model.received($0) }, interval: 0.02) { model.transcribe($0) }
    }

    /// 声の代わりの音。1 秒ごとに大きさを変え、30 秒を超えたときの区切りが 1 か所に決まるようにする
    static func voice(seconds: Double, amplitude: Float = 0.3) -> [Float] {
        (0..<Int(seconds * 16000)).map { i in
            let second = i / 16000
            let gain: Float = second % 7 == 6 ? 0.05 : 1
            return sin(Float(i) * 0.05) * amplitude * gain
        }
    }

    static func feed(_ session: LocalModelSession, _ samples: [Float]) {
        var i = 0
        while i < samples.count {
            let end = min(i + 1600, samples.count)
            session.append(AppleSpeechSession.buffer(from: Array(samples[i..<end]))!)
            i = end
        }
    }

    /// 条件を満たすまで待つ（最大 5 秒）
    static func wait(until condition: () -> Bool) async {
        for _ in 0..<500 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func showsWhatWasSaidWhileRecording() async throws {
        let model = FakeModel()
        let session = makeSession(model)
        Self.feed(session, Self.voice(seconds: 2))
        await Self.wait { model.lastPartial == "32000" }
        #expect(model.lastPartial == "32000")
        session.cancel()
    }

    @Test func longRecordingIsCutWhereTheWholeRecordingWouldBeCut() async throws {
        let model = FakeModel()
        let session = makeSession(model)
        let samples = Self.voice(seconds: 70)
        Self.feed(session, samples)
        let first = RecordedAudio(samples: samples).split(maxDuration: LocalModelSession.partDuration)[0].samples.count
        // 30 秒を超えた分は、録音の途中で確定する
        await Self.wait { model.calledLengths.contains(first) }
        #expect(model.calledLengths.contains(first))
        let text = try await session.finish()
        // 確定した区間を使っても、まとめて認識したときと同じ区切りになる
        #expect(text == FakeModel.expected(RecordedAudio(samples: samples)))
        // 話し終えたときに、確定した区間を書き起こし直さない
        #expect(model.calledLengths.last! < samples.count - first + 1)
    }

    @Test func silenceBeforeReleasingTheKeyReusesTheLastTranscript() async throws {
        let model = FakeModel()
        let session = makeSession(model)
        Self.feed(session, Self.voice(seconds: 2))
        await Self.wait { model.lastPartial == "32000" }
        // 部屋の雑音ほどの音しかない沈黙
        Self.feed(session, Self.voice(seconds: 1.5, amplitude: 0.005))
        try await Task.sleep(for: .milliseconds(100))
        let calls = model.callCount
        let text = try await session.finish()
        #expect(text == "32000")
        #expect(model.callCount == calls)
    }

    @Test func speechAfterTheLastTranscriptIsTranscribedAgain() async throws {
        let model = FakeModel()
        let session = makeSession(model)
        Self.feed(session, Self.voice(seconds: 2))
        await Self.wait { model.lastPartial == "32000" }
        // キーを離す直前に話した語
        Self.feed(session, Self.voice(seconds: 0.3))
        #expect(try await session.finish() == "36800")
    }

    @Test func quietIsMeasuredAgainstHowLoudTheSpeakerWas() {
        let loud = ArraySlice(Self.voice(seconds: 1, amplitude: 0.3))
        let soft = ArraySlice(Self.voice(seconds: 1, amplitude: 0.04))
        let noise = ArraySlice(Self.voice(seconds: 1, amplitude: 0.01))
        #expect(LocalModelSession.isQuiet(noise, after: loud))
        // 小さく話す人では、同じ大きさの音でも声とみなす
        #expect(!LocalModelSession.isQuiet(noise, after: soft))
        #expect(!LocalModelSession.isQuiet(soft, after: loud))
    }

    @Test func onlyQwenTranscribesWhileRecording() {
        #expect(LocalSpeechModel.qwen3Small.transcribesWhileRecording)
        #expect(LocalSpeechModel.qwen3Large.transcribesWhileRecording)
        #expect(!LocalSpeechModel.whisperTurbo.transcribesWhileRecording)
        #expect(!LocalSpeechModel.moss.transcribesWhileRecording)
        #expect(!LocalSpeechModel.cohere.transcribesWhileRecording)
    }

    @Test func voiceBarShowsTheEndOfALongTranscript() {
        #expect(VoiceBarView.tail(of: "明日の会議は3時から") == "明日の会議は3時から")
        let japanese = String(repeating: "あ", count: 60) + "おわり"
        let shown = VoiceBarView.tail(of: japanese)
        #expect(shown.hasPrefix("…") && shown.hasSuffix("おわり"))
        #expect(shown.count == 50)
        let english = String(repeating: "word ", count: 40) + "end"
        // 「…」は全角なので、残りは半角 98 字（先頭の空白は削る）
        #expect(VoiceBarView.tail(of: english) == "…" + String(english.suffix(98)).trimmingCharacters(in: .whitespaces))
        #expect(VoiceBarView.tail(of: "一行目\n二行目") == "一行目 二行目")
    }
}
