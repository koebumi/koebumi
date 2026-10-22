import Foundation
import Testing
@testable import Speak

@Suite struct ChatPunctuationTests {
    /// 入力する直前の処理（日本語の表記ルール → チャットの句読点）を通す
    private func fit(_ text: String, _ rule: ChatPunctuation, category: AppCategory = .chat, mode: Mode = .dictate,
                     _ configure: (inout JapaneseNotation) -> Void = { _ in }) -> String {
        var n = JapaneseNotation()
        configure(&n)
        let request = PolishRequest(transcript: text, mode: mode, sourceLanguages: [], targetLanguage: nil,
                                    appName: "Slack", category: category, styleDescription: "", personalStyle: nil,
                                    vocabulary: [], corrections: [], notation: n, chatPunctuation: rule)
        return Polisher.fit(text, request)
    }

    @Test func keepsCommasInTranslations() {
        // 翻訳した文は読み手の言語の書き方にする。中国語は読点を消すと文が切れ目なくつながる
        let chinese = "明天的会议我可能会晚一点到，你们能先开始吗？"
        #expect(fit(chinese, .noPunctuation, mode: .translate) == chinese)
        #expect(fit("辛苦了。我们已经确认过了，没有问题。", .noPunctuation, mode: .translate) == "辛苦了。我们已经确认过了，没有问题")
        #expect(fit("Sure, sounds good. See you tomorrow.", .noPunctuation, mode: .translate) == "Sure, sounds good. See you tomorrow")
        #expect(fit("好的，没问题。", .noFinalPeriod, mode: .translate) == "好的，没问题")
        #expect(fit("好的，没问题。", .keep, mode: .translate) == "好的，没问题。")
        #expect(fit("好的，没问题。", .noPunctuation, category: .email, mode: .translate) == "好的，没问题。")
    }

    @Test func omitsFinalPeriodInJapanese() {
        let text = "了解です。\n明日やります。"
        #expect(fit(text, .noFinalPeriod) == "了解です\n明日やります")
        #expect(fit(text, .noFinalPeriod, category: .email) == text)
        #expect(fit("了解です。", .keep) == "了解です。")
        #expect(fit("了解です。明日でいいですか。", .noFinalPeriod) == "了解です。明日でいいですか？")
        #expect(fit("はい、了解です。", .noFinalPeriod) == "はい、了解です")  // 「、」は残す
    }

    @Test func omitsCommasAndPeriodsInJapanese() {
        // 「、」は消し、文の切れ目の「。」は空白、行の終わりの「。」は消す
        #expect(fit("はい、了解です。りんご、みかん、ぶどうを買います。", .noPunctuation) == "はい了解です りんごみかんぶどうを買います")
        #expect(fit("了解です。\n明日やります。", .noPunctuation) == "了解です\n明日やります")
        #expect(fit("了解です。明日でいいですか。", .noPunctuation) == "了解です 明日でいいですか？")
        // 閉じかっこの前の「。」は空白にせず詰める
        #expect(fit("「了解です。」と伝えました。", .noPunctuation) == "「了解です」と伝えました")
        // 「，」「．」の書き方でも同じ
        #expect(fit("はい、了解です。明日行きます。", .noPunctuation) { $0.punctuation = .commaPeriod } == "はい了解です 明日行きます")
        #expect(fit("はい、了解です。", .noPunctuation, category: .email) == "はい、了解です。")
    }

    @Test func worksInEnglish() {
        let text = "Sure, sounds good. See you tomorrow."
        #expect(fit(text, .noFinalPeriod) == "Sure, sounds good. See you tomorrow")
        #expect(fit(text, .noPunctuation) == "Sure sounds good See you tomorrow")
        #expect(fit(text, .noPunctuation, category: .email) == text)
        #expect(fit("Thanks!\nSee you.", .noFinalPeriod) == "Thanks!\nSee you")
        #expect(fit("Is that okay?", .noPunctuation) == "Is that okay?")
        // 閉じ引用符・閉じかっこの前の句点も消す
        #expect(fit(#"He said "sounds good." Then he left."#, .noPunctuation) == #"He said "sounds good" Then he left"#)
        #expect(fit("(I think so.)", .noFinalPeriod) == "(I think so)")
    }

    @Test func keepsNumbersAbbreviationsAndEllipses() {
        #expect(fit("It costs $1,000.50, right? Let's meet at 3 p.m. tomorrow.", .noPunctuation)
                == "It costs $1,000.50 right? Let's meet at 3 p.m. tomorrow")
        #expect(fit("See you at 5 p.m.", .noPunctuation) == "See you at 5 p.m.")
        #expect(fit("Fruit, e.g. apples, oranges.", .noPunctuation) == "Fruit e.g. apples oranges")
        #expect(fit("Well... maybe.", .noPunctuation) == "Well... maybe")
        #expect(fit("Check example.com and v2.5.", .noPunctuation) == "Check example.com and v2.5")
        // 箇条書きの番号の「.」は残す
        #expect(fit("やることは2つあります。\n1. 資料作成\n2. 返信", .noPunctuation) == "やることは2つあります\n1. 資料作成\n2. 返信")
        #expect(fit("Two things:\n  1. Budget.\n  2. Timeline.", .noPunctuation) == "Two things:\n  1. Budget\n  2. Timeline")
        // 全角の小数点が「。」にならない
        #expect(fit("3.5ギガです。", .noPunctuation) == "3.5ギガです")
    }

    @Test func worksInOtherLanguages() {
        // 中国語は日本語と同じく、「，」「、」を消し、文の切れ目の「。」を空白にする
        #expect(fit("好的，没问题。我明天早上发给你。", .noFinalPeriod) == "好的，没问题。我明天早上发给你")
        #expect(fit("好的，没问题。我明天早上发给你。", .noPunctuation) == "好的没问题 我明天早上发给你")
        #expect(fit("你好吗？", .noPunctuation) == "你好吗？")
        #expect(fit("네, 알겠습니다. 내일 아침에 보낼게요.", .noPunctuation) == "네 알겠습니다 내일 아침에 보낼게요")
        #expect(fit("¿Vienes mañana? Sí, claro.", .noPunctuation) == "¿Vienes mañana? Sí claro")
        #expect(fit("Ja, klar. Bis morgen.", .noPunctuation) == "Ja klar Bis morgen")
        #expect(fit("نعم، سأرسله غدًا.", .noPunctuation) == "نعم سأرسله غدًا")
        #expect(fit("हाँ, ठीक है। कल भेज दूँगा।", .noPunctuation) == "हाँ ठीक है कल भेज दूँगा")
        // 日本語の中の英語
        #expect(fit("了解です。Thanks, see you.", .noPunctuation) == "了解です Thanks see you")
    }

    @Test func readsOldSetting() throws {
        func decode(_ json: String) throws -> ChatPunctuation {
            try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8)).chatPunctuation
        }
        // 日本語の表記ルールの中にあった設定と、その前の「チャットでは文末の「。」を付けない」のオン・オフを引き継ぐ
        #expect(try decode(#"{"japaneseNotation": {"chatPunctuation": "noPunctuation", "omitChatPeriod": true}}"#) == .noPunctuation)
        #expect(try decode(#"{"japaneseNotation": {"omitChatPeriod": true}}"#) == .noFinalPeriod)
        #expect(try decode(#"{"japaneseNotation": {"omitChatPeriod": false}}"#) == .keep)
        #expect(try decode("{}") == .keep)
        #expect(try decode(#"{"chatPunctuation": "noFinalPeriod", "japaneseNotation": {"chatPunctuation": "noPunctuation"}}"#) == .noFinalPeriod)

        var settings = AppSettings()
        settings.chatPunctuation = .noFinalPeriod
        let saved = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(saved.chatPunctuation == .noFinalPeriod)
    }

    @Test func defaultsToNoPunctuationOnlyForNewUsers() throws {
        #expect(AppSettings().chatPunctuation == .noPunctuation)
        // 設定ファイルがある人は、この項目がなくても以前の初期値の「そのまま」を保つ
        let existing = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"japaneseNotation": {"punctuation": "standard"}}"#.utf8))
        #expect(existing.chatPunctuation == .keep)
    }
}
