import Foundation
import Testing
@testable import Speak

@Suite struct CorrectionDetectorTests {
    private func learn(_ before: String, _ after: String) -> String? {
        let a = Array(before), b = Array(after)
        guard let edit = CorrectionDetector.diff(a, b) else { return nil }
        return CorrectionDetector.learnedTerm(before: a, after: b, edit: edit)?.term
    }

    @Test func learnsCorrectedJapaneseName() {
        #expect(learn("明日は棚香さんと会います。", "明日は田中さんと会います。") == "田中")
    }

    @Test func expandsToWholeKanjiWord() {
        #expect(learn("機会学習の資料です", "機械学習の資料です") == "機械学習")
    }

    @Test func learnsLatinSpellingFixes() {
        #expect(learn("I use iphone daily", "I use iPhone daily") == "iPhone")
        #expect(learn("ask the clawd team", "ask the Claude team") == "Claude")
        #expect(learn("run cube cuddle get pods", "run kubectl get pods") == "kubectl")
    }

    @Test func ignoresGrammarEdits() {
        #expect(learn("私は行きます", "私が行きます") == nil)  // 助詞の修正
        #expect(learn("their car", "there car") == nil)  // ありふれた英単語
        #expect(learn("hello world", "hello") == nil)  // 削除だけ
    }

    @Test func diffFindsSingleRegion() {
        let e = CorrectionDetector.diff(Array("abcXYZdef"), Array("abc12def"))
        #expect(e?.start == 3)
        #expect(e?.old == "XYZ")
        #expect(e?.new == "12")
        #expect(CorrectionDetector.lastRange(of: Array("ab"), in: Array("xabyab")) == 4..<6)
    }
}

@Suite struct WAVTests {
    @Test func roundTrips() throws {
        let samples: [Float] = (0..<1600).map { sin(Float($0) / 10) * 0.5 }
        let data = WAV.encode(RecordedAudio(samples: samples))
        #expect(data.count == 44 + samples.count * 2)
        let decoded = try #require(WAV.decode(data))
        #expect(decoded.sampleRate == 16000)
        #expect(decoded.samples.count == samples.count)
        #expect(zip(decoded.samples, samples).allSatisfy { abs($0 - $1) < 0.001 })
    }

    @Test func silenceAndNormalization() {
        #expect(RecordedAudio(samples: [Float](repeating: 0.001, count: 16000)).isSilent)
        #expect(RecordedAudio(samples: [Float](repeating: 0.2, count: 1000)).isSilent)  // 短すぎる
        let quiet = RecordedAudio(samples: [Float](repeating: 0.05, count: 16000))
        #expect(!quiet.isSilent)
        #expect(abs(quiet.normalized().peak - 0.8) < 0.01)  // 最大 16 倍まで
    }
}

@Suite struct TextTests {
    @Test func basicCleanerRemovesFillers() {
        #expect(BasicCleaner.clean("えーと、明日はあの、晴れです") == "明日は晴れです")
        #expect(BasicCleaner.clean("um so uh we ship today") == "So we ship today")
    }

    @Test func cleanOutputStripsWrappers() {
        #expect(Prompts.cleanOutput("<think>x</think>\n\"Hello there\"") == "Hello there")
        #expect(Prompts.cleanOutput("```\nコード\n```") == "コード")
        #expect(Prompts.extractJSON("前置き {\"a\": 1} 後") == "{\"a\": 1}")
    }

    @Test func askOutcomeValidation() {
        let withSel = AskRequest(query: "q", selection: "x", selectionEditable: true, hasFocusedTextField: true, appName: "A", vocabulary: [])
        let noSel = AskRequest(query: "q", selection: nil, selectionEditable: false, hasFocusedTextField: true, appName: "A", vocabulary: [])
        #expect(Prompts.outcome(action: "replace", text: "y", url: "", request: withSel) == .replace("y"))
        #expect(Prompts.outcome(action: "replace", text: "y", url: "", request: noSel) == .answer("y"))
        #expect(Prompts.outcome(action: "open_url", text: "d", url: "javascript:alert(1)", request: noSel) == .answer("d"))
        #expect(Prompts.outcome(action: "open_url", text: "d", url: "https://example.com", request: noSel) == .openURL(URL(string: "https://example.com")!, "d"))
    }

    @Test func polishPromptCarriesContext() {
        let r = PolishRequest(transcript: "えーと", mode: .translate, sourceLanguages: ["ja-JP"], targetLanguage: "en-US",
                              appName: "Slack", category: .chat, styleDescription: "casual", personalStyle: "short",
                              vocabulary: ["田中"], corrections: [Correction(original: "a", preferred: "b")])
        let u = Prompts.polishUser(r)
        #expect(u.contains("App: Slack (chat)"))
        #expect(u.contains("Target language: English (United States)"))
        #expect(u.contains("田中"))
        #expect(u.contains("<transcript>\nえーと\n</transcript>"))
    }

    @Test func wordCountHandlesJapanese() {
        #expect(StatsStore.wordCount("We ship today.") == 3)
        #expect(StatsStore.wordCount("明日は晴れです") >= 3)
    }

    @Test func csvParsing() {
        let csv = "term,source\nSpeak,manual\n\"Foo, Inc.\",manual\n田中\n\n"
        #expect(DictionaryStore.parseCSV(csv) == ["Speak", "Foo, Inc.", "田中"])
    }
}

@Suite struct ContextTests {
    @Test func classifiesApps() {
        #expect(AppContext.classify(bundleID: "com.tinyspeck.slackmacgap", windowTitle: nil) == .chat)
        #expect(AppContext.classify(bundleID: "com.google.Chrome", windowTitle: "受信トレイ - Gmail") == .email)
        #expect(AppContext.classify(bundleID: "com.google.Chrome", windowTitle: "ChatGPT") == .ai)
        #expect(AppContext.classify(bundleID: "com.jetbrains.intellij", windowTitle: nil) == .code)
        #expect(AppContext.classify(bundleID: "com.example.unknown", windowTitle: "Untitled") == .other)
    }

    @Test func streakCountsConsecutiveDays() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let days = Set([0, 1, 2, 4].map { StatsStore.dayKey(cal.date(byAdding: .day, value: -$0, to: today)!) })
        #expect(StatsStore.streak(days: days, today: today) == 3)
        let fromYesterday = Set([1, 2].map { StatsStore.dayKey(cal.date(byAdding: .day, value: -$0, to: today)!) })
        #expect(StatsStore.streak(days: fromYesterday, today: today) == 2)
    }

    @Test func settingsDecodeFillsMissingKeys() throws {
        let json = #"{"llmProvider": "claude", "dictationLanguages": ["en-US"], "unknownKey": 1}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(s.llmProvider == .claude)
        #expect(s.dictationLanguages == ["en-US"])
        #expect(s.dictateShortcuts == [.fn])
        #expect(s.historyRetention == .forever)
    }

    @Test func retentionPrunesOldItems() {
        #expect(Retention.week.interval == TimeInterval(7 * 86400))
        #expect(Retention.forever.interval == nil)
        #expect(Retention.never.interval == 0)
    }
}
