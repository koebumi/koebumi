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
        private var received: [LiveTranscriptEvent] = []

        var callCount: Int { lock.withLock { calls.count } }
        var calledLengths: [Int] { lock.withLock { calls } }
        var events: [LiveTranscriptEvent] { lock.withLock { received } }
        var lastPartial: String? {
            lock.withLock {
                received.compactMap { if case .partial(let text) = $0 { text } else { nil } }.last
            }
        }

        func transcribe(_ audio: RecordedAudio) -> String {
            lock.withLock { calls.append(audio.samples.count) }
            return Self.expected(audio)
        }

        func receive(_ event: LiveTranscriptEvent) {
            lock.withLock { received.append(event) }
        }

        /// 録音が終わってからまとめて認識したときの結果
        static func expected(_ audio: RecordedAudio) -> String {
            LocalSpeechRuntime.joinTranscripts(audio.split(maxDuration: LocalModelSession.partDuration).map { "\($0.samples.count)" })
        }
    }

    func makeSession(_ model: FakeModel) -> LocalModelSession {
        LocalModelSession(onLive: { model.receive($0) }, interval: 0.02) { model.transcribe($0) }
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
        // 書き起こしを始めたことを、届く前に知らせる（音声バーの札で末尾を光らせる）
        let events = model.events
        let arrived = events.firstIndex(of: .partial("32000"))!
        #expect(events[..<arrived].contains(.transcribing))
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

    @Test func firstTranscriptionStartsSoonAfterTheVoice() async throws {
        let model = FakeModel()
        let session = makeSession(model)
        // 話し始める前の無音では書き起こさない
        Self.feed(session, [Float](repeating: 0, count: 16000))
        try await Task.sleep(for: .milliseconds(150))
        #expect(model.callCount == 0)
        // 声が出始めてから 0.4 秒たまったら書き起こす
        Self.feed(session, Self.voice(seconds: 0.5))
        await Self.wait { model.callCount > 0 }
        #expect(model.calledLengths.first.map { $0 >= 16000 + 6400 } == true)
        session.cancel()
    }

    struct Failure: Error {}

    @Test func failureWhileRecordingClearsTheTranscribingMark() async throws {
        let model = FakeModel()
        // 1 回目は書き起こせて、2 回目に失敗する
        let session = LocalModelSession(onLive: { model.receive($0) }, interval: 0.02) { audio in
            if model.callCount >= 1 { throw Failure() }
            return model.transcribe(audio)
        }
        Self.feed(session, Self.voice(seconds: 1))
        await Self.wait { model.lastPartial != nil }
        let shown = try #require(model.lastPartial)
        Self.feed(session, Self.voice(seconds: 1))
        await Self.wait { model.events.filter { $0 == .transcribing }.count == 2 && model.events.last != .transcribing }
        // 出している文はそのままで、書き起こし中の印だけを消す（札の末尾を薄いままにしない）
        #expect(model.events.last == .partial(shown))
        var live = LiveTranscript()
        for event in model.events { live.receive(event, at: Date()) }
        #expect(live.transcribingSince == nil && live.text == shown)
        session.cancel()
    }

    @Test func quietSpeakerIsTranscribedAfterAWhile() async throws {
        let model = FakeModel()
        let session = makeSession(model)
        // 出始めが分からないほど小さな声でも、1.5 秒たてば書き起こす
        Self.feed(session, Self.voice(seconds: 1.6, amplitude: 0.015))
        await Self.wait { model.callCount > 0 }
        #expect(model.callCount > 0)
        session.cancel()
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
        let before = model.events.count
        let text = try await session.finish()
        #expect(text == "32000")
        #expect(model.callCount == calls)
        // 書き起こし直さないので、書き起こしを始めたとは知らせず、最後の文だけを知らせる
        #expect(Array(model.events[before...]) == [.final("32000")])
    }

    @Test func speechAfterTheLastTranscriptIsTranscribedAgain() async throws {
        let model = FakeModel()
        let session = makeSession(model)
        Self.feed(session, Self.voice(seconds: 2))
        await Self.wait { model.lastPartial == "32000" }
        // キーを離す直前に話した語
        Self.feed(session, Self.voice(seconds: 0.3))
        let before = model.events.count
        #expect(try await session.finish() == "36800")
        // 残りを書き起こす間は札の末尾を光らせ、書き起こした最後の文を出す
        #expect(model.events[before...].last == .final("36800"))
        #expect(model.events[before...].contains(.transcribing))
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

    @Test func liveTranscriptRemembersWhenTextArrived() {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        var live = LiveTranscript()
        live.receive(.transcribing, at: t0)
        #expect(live.transcribingSince == t0)
        live.receive(.partial("明日の"), at: t0 + 1)
        #expect(live.text == "明日の" && live.previous == "" && live.arrivedAt == t0 + 1 && live.transcribingSince == nil)
        // 書き起こし直しても同じ文なら、届いた時刻を変えない（光らせる部分がない）
        live.receive(.transcribing, at: t0 + 2)
        live.receive(.partial("明日の"), at: t0 + 3)
        #expect(live.arrivedAt == t0 + 1 && live.transcribingSince == nil)
        live.receive(.final("明日の会議"), at: t0 + 4)
        #expect(live.text == "明日の会議" && live.previous == "明日の" && live.finalAt == t0 + 4)
    }

    /// t0 に short が届き、t0 + 1 から書き起こしを始め、t0 + 2 に long が届いた
    static let t0 = Date(timeIntervalSinceReferenceDate: 0)
    static func style(_ events: [LiveTranscriptEvent], at seconds: TimeInterval, reduceMotion: Bool = false) -> LiveTextStyle {
        var live = LiveTranscript()
        for (i, event) in events.enumerated() { live.receive(event, at: t0 + Double(i)) }
        return LiveTextStyle.at(t0 + seconds, live: live, reduceMotion: reduceMotion)
    }

    /// 虹の帯の位置。帯がなければ nil
    static func band(_ effect: LiveTextStyle.Effect) -> Double? {
        switch effect {
        case .none: nil
        case .transcribing(let band): band
        case .arrived(let band), .appeared(let band), .polishing(let band): band
        }
    }

    @Test func tailShinesTwiceWhileTranscribing() {
        let events: [LiveTranscriptEvent] = [.partial("明日の会議は3時からです"), .transcribing]
        // 末尾の全角 6 字ぶん（「3」は半角なので 7 字）を光らせる。虹は 0.45 秒で 1 回通り、2 回通ったら薄いまま待つ
        let passing = Self.style(events, at: 1.2)
        #expect(passing.markedFrom == 5)
        #expect(abs(Self.band(passing.effect)! - 0.2 / 0.45) < 1e-9)
        #expect(abs(Self.band(Self.style(events, at: 1.6).effect)! - (0.6 / 0.45 - 1)) < 1e-9)
        #expect(Self.style(events, at: 1.95) == LiveTextStyle(shown: "明日の会議は3時からです", markedFrom: 5, effect: .transcribing(band: nil)))
        // 動きを減らす設定では、虹を通さず薄くするだけ
        #expect(Self.style(events, at: 1.2, reduceMotion: true).effect == .transcribing(band: nil))
    }

    @Test func arrivedTextIsRevealedOnce() {
        let events: [LiveTranscriptEvent] = [.partial("明日の会議"), .transcribing, .partial("明日の会議は3時から")]
        // 変わった部分（前に届いた文との違い）だけを、虹で 1 回なでる
        let arriving = Self.style(events, at: 2.3)
        #expect(arriving.markedFrom == 5)
        guard case .arrived(let band) = arriving.effect else { Issue.record("\(arriving.effect)"); return }
        #expect(band > 0 && band < 1)
        #expect(Self.style(events, at: 2.7) == LiveTextStyle(shown: "明日の会議は3時から", markedFrom: nil, effect: .none))
        #expect(Self.style(events, at: 2.3, reduceMotion: true).effect == .none)
    }

    @Test func firstTextIsShownRightAway() {
        // 札に初めて出す字は薄くせず、虹を上に 1 回通すだけ
        let style = Self.style([.partial("明日の")], at: 0.3)
        #expect(style.markedFrom == 0)
        guard case .appeared(let band) = style.effect else { Issue.record("\(style.effect)"); return }
        #expect(band > 0 && band < 1)
    }

    @Test func wholeTextShinesWhilePolishing() {
        let events: [LiveTranscriptEvent] = [.partial("明日の会議"), .transcribing, .final("明日の会議は3時から")]
        // 最後の文が届いたら、残りをなでてから、0.7 秒後に全文へ 2.2 秒で 1 回ずつ虹を流し続ける
        if case .arrived = Self.style(events, at: 2.3).effect {} else { Issue.record("最後の文が届いた字をなでない") }
        let polishing = Self.style(events, at: 2.7 + 1.1)
        #expect(polishing.markedFrom == 0)
        if case .polishing(let band) = polishing.effect { #expect(abs(band - 0.5) < 1e-9) } else { Issue.record("\(polishing.effect)") }
        #expect(abs(Self.band(Self.style(events, at: 2.7 + 2.2 + 0.55).effect)! - 0.25) < 1e-9)
        #expect(Self.style(events, at: 4, reduceMotion: true).effect == .none)
    }

    @Test func shineStopsAfterItIsDone() {
        var live = LiveTranscript()
        live.receive(.partial("明日の"), at: Self.t0)
        #expect(LiveTextStyle.animationEnd(live: live, reduceMotion: false) == Self.t0 + LiveTextStyle.arrivalDuration)
        live.receive(.transcribing, at: Self.t0 + 1)
        #expect(LiveTextStyle.animationEnd(live: live, reduceMotion: false) == Self.t0 + 1 + 0.9)
        live.receive(.final("明日の会議"), at: Self.t0 + 2)
        #expect(LiveTextStyle.animationEnd(live: live, reduceMotion: false) == .distantFuture)
        #expect(LiveTextStyle.animationEnd(live: live, reduceMotion: true) == nil)
    }

    @Test func englishTailIsNotCutInsideAWord() {
        // 全角 6 字ぶん（半角 12 字）を取り、語の途中なら語の頭まで戻す
        let chars = Array("Let's move tomorrow's meeting")
        #expect(String(chars[LiveTextStyle.tailStart(chars)...]) == "tomorrow's meeting")
        let japanese = Array("明日の会議は3時から")
        #expect(String(japanese[LiveTextStyle.tailStart(japanese)...]) == "会議は3時から")
    }

    @Test func liveTranscriptIsShownUnlessTurnedOff() throws {
        // 初めは出す。前の版の設定ファイルには項目がないので、出す
        #expect(AppSettings().showLiveTranscript)
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"llmProvider": "claude"}"#.utf8))
        #expect(old.showLiveTranscript)
        let off = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"showLiveTranscript": false}"#.utf8))
        #expect(!off.showLiveTranscript)
    }

    @Test func voiceBarShowsTheEndOfALongTranscript() {
        func shown(_ text: String) -> String { Self.style([.partial(text)], at: 5).shown }
        #expect(shown("明日の会議は3時から") == "明日の会議は3時から")
        let japanese = String(repeating: "あ", count: 60) + "おわり"
        #expect(shown(japanese).hasPrefix("…") && shown(japanese).hasSuffix("おわり"))
        #expect(shown(japanese).count == 50)
        let english = String(repeating: "word ", count: 40) + "end"
        // 「…」は全角なので、残りは半角 98 字（先頭の空白は削る）
        #expect(shown(english) == "…" + String(english.suffix(98)).trimmingCharacters(in: .whitespaces))
        #expect(shown("一行目\n二行目") == "一行目 二行目")
        // 「…」で省いた部分は光らせない。光らせる位置は、出す文の中で数える
        let style = Self.style([.partial(japanese), .transcribing], at: 1.2)
        #expect(style.markedFrom == 44)
        #expect(String(Array(style.shown)[44...]) == "ああああおわり".suffix(6))
    }
}
