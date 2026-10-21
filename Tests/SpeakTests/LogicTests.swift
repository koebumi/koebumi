import Foundation
import Testing
@testable import Speak

@Suite struct CorrectionDetectorTests {
    private func learnAll(_ before: String, _ after: String) -> [String] {
        CorrectionDetector.learnedTerms(before: Array(before), after: Array(after)).map(\.term)
    }

    private func learn(_ before: String, _ after: String) -> String? {
        learnAll(before, after).first
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

    @Test func learnsMixedScriptTerms() {
        #expect(learn("認識用の急にモデルを渡す", "認識用のキューにモデルを渡す") == "キュー")
        #expect(learn("スレッドカンで安全に渡す", "スレッド間で安全に渡す") == "スレッド間")  // カタカナと漢字で 1 語
    }

    @Test func learnsKatakanaRewrittenInEnglish() {
        #expect(learn("クロードコードで直しました", "Claude Codeで直しました") == "Claude Code")
    }

    @Test func ignoresUnrelatedReplacements() {
        // 入力した文を消して、別の文を書いた（実際に誤って登録された例）
        #expect(learn("明日の会議はできた", "明日の会議は渡邊") == nil)
        #expect(learn("明日の3時に4時からの会議の資料を準備する", "試したら正しく4時からになった") == nil)
        #expect(learn("メモリのせいでしょうか", "deimosも再起動中です") == nil)
        #expect(learn("英語は。", "英語は対応していない") == nil)
    }

    @Test func learnsEachCorrectedWord() {
        #expect(learnAll("明日は棚香さんと急の件で話す", "明日は田中さんとキューの件で話す") == ["田中", "キュー"])
        #expect(learnAll("機会学修の資料", "機械学習の資料") == ["機械学習"])  // 同じ語の中の 2 か所は 1 語にまとめる
        // 以前は 2 語まとめて「gpt-4o-transcribeとGroq」を 1 語として登録していた
        #expect(learnAll("GPTフォートランスクライブとグロックで比べてみて", "gpt-4o-transcribeとGroqで比べてみて")
                == ["gpt-4o-transcribe", "Groq"])
    }

    @Test func learnsOnlyTheMisheardPartWhenTheTitleChanges() {
        func pairs(_ before: String, _ after: String) -> [CorrectionDetector.Learned] {
            CorrectionDetector.learnedTerms(before: Array(before), after: Array(after))
        }
        // 以前は「田中部長」を 1 語として、「棚香さん」を聞き取られ方として登録していた
        #expect(pairs("会議は棚香さんが来る", "会議は田中部長が来る") == [.init(term: "田中", replaced: "棚香")])
        #expect(pairs("渡辺さんに送る", "渡邉部長に送る") == [.init(term: "渡邉", replaced: "渡辺")])
        #expect(pairs("棚香の資料", "田中部長の資料") == [.init(term: "田中", replaced: "棚香")])
        #expect(pairs("先日棚香と話した", "昨日田中と話した") == [.init(term: "田中", replaced: "棚香")])
        // 読みが近いまま続く語は切り離さない
        #expect(pairs("スレッドカンで渡す", "スレッド間で渡す") == [.init(term: "スレッド間", replaced: "スレッドカン")])
        #expect(pairs("機会学習の資料", "機械学習の資料") == [.init(term: "機械学習", replaced: "機会学習")])
        #expect(pairs("棚香さんと会う", "田中さんと会う") == [.init(term: "田中", replaced: "棚香")])
        #expect(pairs("クラウドコードで直す", "クロードコードで直す") == [.init(term: "クロードコード", replaced: "クラウドコード")])
    }

    @Test func ignoresTitleChangesAlone() {
        // 名前はそのままで、敬称や隣の語だけを書き換えた
        #expect(learn("鈴木さんに送る", "鈴木課長に送る") == nil)
        #expect(learn("田中さんに送る", "田中様に送る") == nil)
        #expect(learn("東京都庁に行く", "東京都議会に行く") == nil)
    }

    @Test func ignoresCapitalizedCommonWordsAtSentenceStart() {
        #expect(learn("Their car is red", "There car is red") == nil)
        #expect(learn("Done. Their car is red", "Done. There car is red") == nil)
        #expect(learn("clawd is great", "Claude is great") == "Claude")  // 小文字では辞書にない語
        #expect(learn("we use slick", "we use Slack") == "Slack")  // 文の途中の大文字は固有名詞
    }

    @Test func ignoresChangedNumbers() {
        // 数を書き換えたのは内容の修正。覚えると、次から「3時」が「4時」に置き換わる
        #expect(learn("明日は3時に集合", "明日は4時に集合") == nil)
        #expect(learn("予算は3000円です", "予算は3500円です") == nil)
        #expect(learn("残りは10件", "残りは12件") == nil)
        #expect(learn("v1.2 を入れて", "v1.3 を入れて") == nil)
        #expect(learn("GPT4で試す", "GPT-5で試す") == nil)
    }

    @Test func ignoresGrammarEdits() {
        #expect(learn("私は行きます", "私が行きます") == nil)  // 助詞の修正
        #expect(learn("their car", "there car") == nil)  // ありふれた英単語
        #expect(learn("hello world", "hello") == nil)  // 削除だけ
    }

    @Test func diffFindsSingleRegion() {
        let e = CorrectionDetector.diff(Array("abcXYZdef"), Array("abc12def"))
        #expect(e?.oldStart == 3)
        #expect(e?.old == "XYZ")
        #expect(e?.new == "12")
        #expect(CorrectionDetector.lastRange(of: Array("ab"), in: Array("xabyab")) == 4..<6)
    }
}

@Suite struct CorrectionTrackerTests {
    private typealias Learned = CorrectionDetector.Learned

    /// 入力欄の内容を順に読ませ、辞書に残る語を返す。同じ内容を続けて渡すと「直し終えた」ことになる
    private func run(_ field: String, inserted: String, _ reads: [String], finish: String? = nil) -> [Learned] {
        let value = Array(field)
        var tracker = CorrectionTracker(value: value, range: CorrectionDetector.lastRange(of: Array(inserted), in: value)!)
        var dictionary: [Learned] = []
        func apply(_ c: CorrectionTracker.Changes) {
            dictionary.removeAll { c.forgotten.contains($0) }
            dictionary += c.learned
        }
        for read in reads { apply(tracker.observe(Array(read))) }
        if let finish { apply(tracker.finish(Array(finish))) }
        return dictionary
    }

    @Test func waitsUntilTheCorrectionIsTyped() {
        // 以前は「消しただけ」の読み取りを基準にして、次に書いた「田中」を書き足しとみなし、何も覚えなかった
        let reads = ["明日はさんと会います。", "明日はさんと会います。",
                     "明日はたなかさんと会います。", "明日はたなかさんと会います。",  // 変換中
                     "明日は田中さんと会います。", "明日は田中さんと会います。"]
        #expect(run("明日は棚香さんと会います。", inserted: "明日は棚香さんと会います。", reads)
                == [Learned(term: "田中", replaced: "棚香")])
    }

    @Test func replacesWhatWasLearnedFromHalfTypedWord() {
        let reads = ["クロードコーで直しました", "で直しました", "で直しました",
                     "Claude Coで直しました", "Claude Coで直しました",
                     "Claude Codeで直しました", "Claude Codeで直しました"]
        #expect(run("クロードコードで直しました", inserted: "クロードコードで直しました", reads)
                == [Learned(term: "Claude Code", replaced: "クロードコード")])
    }

    @Test func learnsFirstWordRetypedAtTheEdge() {
        // 入力したテキストの先頭の語を消して書き直すと、書いた語が範囲の境目に入る
        let reads = ["メモ: さんに送る", "メモ: さんに送る", "メモ: 田中さんに送る", "メモ: 田中さんに送る"]
        #expect(run("メモ: 棚香さんに送る", inserted: "棚香さんに送る", reads) == [Learned(term: "田中", replaced: "棚香")])
    }

    @Test func followsEditsAroundTheInsertedText() {
        let reads = ["前に書いた文。棚香さんに送る", "前に書いた文。棚香さんに送る。続き", "前に書いた文。田中さんに送る。続き",
                     "前に書いた文。田中さんに送る。続き"]
        #expect(run("前の文。棚香さんに送る", inserted: "棚香さんに送る", reads) == [Learned(term: "田中", replaced: "棚香")])
    }

    @Test func keepsWhatWasLearnedAfterSendingOrDeleting() {
        // 直してすぐ送信した（入力欄が空になった）
        #expect(run("棚香さんに送る", inserted: "棚香さんに送る", ["田中さんに送る", ""]) == [Learned(term: "田中", replaced: "棚香")])
        // 直した後で文ごと消した
        let reads = ["田中さんに送る。急ぎ", "田中さんに送る。急ぎ", "急ぎ", "急ぎ"]
        #expect(run("棚香さんに送る。急ぎ", inserted: "棚香さんに送る。急ぎ", reads) == [Learned(term: "田中", replaced: "棚香")])
    }

    @Test func forgetsWhenTheCorrectionIsUndone() {
        let reads = ["田中さんに送る", "田中さんに送る", "棚香さんに送る", "棚香さんに送る"]
        #expect(run("棚香さんに送る", inserted: "棚香さんに送る", reads) == [])
    }

    @Test func learnsWhenTheOnlyDictatedWordIsRetyped() {
        let reads = ["Cl", "Claude Code", "Claude Code"]
        #expect(run("クロードコード", inserted: "クロードコード", reads) == [Learned(term: "Claude Code", replaced: "クロードコード")])
    }

    @Test func checksTheLastStateWhenFinished() {
        #expect(run("棚香さんに送る", inserted: "棚香さんに送る", ["田中さんに送る"], finish: "田中さんに送る")
                == [Learned(term: "田中", replaced: "棚香")])
    }
}

@MainActor @Suite struct DictionaryLearningTests {
    @Test func forgetsOnlyWhatWasLearned() {
        let store = DictionaryStore(fileName: nil)
        store.add("Claude Code", source: .manual, replaced: "クロードコード")
        #expect(!store.learn("Claude Code", replaced: "クロードコード"))  // 登録済み。取り消しの対象にしない

        #expect(store.learn("田中", replaced: "棚香"))
        #expect(store.learn("田中", replaced: "たなか"))
        store.forget("田中", replaced: "棚香")
        #expect(store.entries.first { $0.term == "田中" }?.aliases == ["たなか"])
        store.forget("田中", replaced: "たなか")
        #expect(!store.terms.contains("田中"))
        #expect(store.terms == ["Claude Code"])
    }

    @Test func newerCorrectionWins() {
        let store = DictionaryStore(fileName: nil)
        store.learn("Claude", replaced: "クロード")
        store.learn("クロード", replaced: "Claude")
        // 置き換えが Claude ⇄ クロード で行ったり来たりしない
        #expect(store.aliases == ["Claude": "クロード"])
        #expect(!store.terms.contains("Claude"))

        // 手動で登録した向きは変えない
        store.add("Speak", source: .manual, replaced: "スピーク")
        #expect(!store.learn("スピーク", replaced: "Speak"))
        #expect(store.aliases["スピーク"] == "Speak")
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
