import Foundation
import Testing
@testable import Koebumi

@Suite struct MailReplyTests {
    /// Apple Mail の返信。引用は入力欄のカーソルより後ろにある
    private let appleMailQuote = """


    2026/10/22 15:00、東海林 太郎 <shoji@example.co.jp>のメール:

    > 矢野様
    >
    > いつもお世話になっております。
    > 株式会社ABCの東海林です。
    """

    @Test func readsSenderAndRegisterFromQuotedReply() {
        let c = MailReply.context(from: SurroundingText(after: appleMailQuote))
        #expect(c?.name == "東海林")
        #expect(c?.fullName == "東海林太郎")
        #expect(c?.honorific == "様")
        #expect(c?.external == true)
        #expect(c?.addressee == "東海林様")
        #expect(c?.greeting == "お世話になっております。")
    }

    @Test func readsARichTextReplyBelowTheUsersSignature() {
        // Web 表示の本文をテキストマーカーで読んだ文（引用に「> 」が付かず、自分の署名が引用の前にある）
        let after = "\n\n--\n矢野 康介\n\n\n2026/10/20 10:00、東海林 太郎 <shoji@example.co.jp>のメール：\n\n矢野様\n\n"
            + "いつも大変お世話になっております。\n株式会社サンプルの東海林です。\n\n先日の打ち合わせの資料をお送りします。\n"
            + "ご確認のほど、よろしくお願いいたします。\n\n--\n株式会社サンプル\n営業部 東海林 太郎"
        let c = MailReply.context(from: SurroundingText(after: after, screen: "宛先:\nCc:\n￼\n件名:\n差出人:\n署名:"))
        #expect(c?.addressee == "東海林様")
        #expect(c?.external == true)
    }

    @Test func readsANameIntroducedBeforeTheGreeting() {
        // 差出人がアドレスだけで、挨拶（こんにちは）より先に「所属　名前です。」と名乗るメール。名前は署名の行で確かめる
        let after = "\n株式会社サンプル 営業部\n矢野 康介\nyano@example.com\n\n\n\n2026/10/24 18:30、tanaka@example.ac.jp のメール:\n\n"
            + "林さん\n矢野さん\n\n情報科学研究科2年　田中です。\n\nこんにちは。\n先日の件について連絡です。\n\nよろしくお願いします。\n\n"
            + "--------------------------------\n情報科学研究科\n田中　太郎\ntanaka@example.ac.jp"
        let c = MailReply.context(from: SurroundingText(after: after))
        #expect(c?.addressee == "田中さん")
        #expect(c?.external == nil)
        // 署名に同じ名前がなければ、名乗りとみなさない
        let unsigned = "2026/10/24 18:30、tanaka@example.ac.jp のメール:\n\n矢野さん\n\n研究室の議事録です。\n\nご確認ください。"
        #expect(MailReply.context(from: SurroundingText(after: unsigned))?.name == nil)
    }

    @Test func readsTheNewestMessageOfAThread() {
        // Gmail はスレッドを入力欄より前に出す。入力欄に近い（後ろの）メールが返信先
        let screen = """
        矢野 浩介
        <yano@example.com>
        東海林様
        お世話になっております。矢野です。
        佐藤 花子
        <sato@example.com>
        矢野さん
        お疲れ様です。佐藤です。
        資料を確認しました。
        """
        let c = MailReply.context(from: SurroundingText(screen: screen))
        #expect(c?.name == "佐藤")
        #expect(c?.honorific == "さん")
        #expect(c?.external == false)
        #expect(c?.greeting == "お疲れ様です。")
    }

    @Test func skipsTheUsersOwnAddress() {
        let screen = """
        To: 矢野 浩介 <yano@example.com>
        矢野様
        お世話になっております。
        """
        let c = MailReply.context(from: SurroundingText(screen: screen))
        #expect(c?.name == nil)
        #expect(c?.external == true)
    }

    @Test func usesAnIntroductionOnlyWhenTheSignatureHasTheName() {
        let signed = "矢野様\nお世話になっております。株式会社ABCの東海林です。\n見積書を添付いたします。\n株式会社ABC 営業部\n東海林 太郎"
        #expect(MailReply.context(from: SurroundingText(screen: signed))?.name == "東海林")
        // 「〜の議事録です」は名乗りではない
        let minutes = "矢野様\nお世話になっております。先日の会議の議事録です。\nご確認ください。"
        #expect(MailReply.context(from: SurroundingText(screen: minutes))?.name == nil)
    }

    @Test func returnsNilWithoutAnyClue() {
        #expect(MailReply.context(from: SurroundingText(screen: "受信トレイ\n未読 3 件")) == nil)
        #expect(MailReply.context(from: SurroundingText()) == nil)
    }

    @Test func fixesTheOpeningGreetingToTheRelationship() {
        let external = MailReplyContext(name: "東海林", external: true)
        #expect(MailReply.adjust("お疲れ様です。資料を送ります。", context: external) == "お世話になっております。資料を送ります。")
        #expect(MailReply.adjust("東海林さん、お疲れさまです。", context: external) == "東海林様、お世話になっております。")
        let colleague = MailReplyContext(name: "佐藤", honorific: "さん", external: false)
        #expect(MailReply.adjust("佐藤さん\n\nいつもお世話になっております。\n資料を送ります。", context: colleague)
                == "佐藤さん\n\nお疲れ様です。\n資料を送ります。")
        // 書き出しでない挨拶（4 行目より後・文の途中）は変えない
        #expect(MailReply.adjust("資料を送ります。\nよろしく\nお願いします。\nお疲れ様です。", context: external)
                == "資料を送ります。\nよろしく\nお願いします。\nお疲れ様です。")
        #expect(MailReply.adjust("先方にお疲れ様ですと伝えてください。", context: external) == "先方にお疲れ様ですと伝えてください。")
    }

    @Test func raisesHonorificsButNeverLowersThem() {
        let external = MailReplyContext(name: "東海林", fullName: "東海林太郎", external: true)
        #expect(MailReply.adjust("東海林さんにご確認いただきました。", context: external) == "東海林様にご確認いただきました。")
        #expect(MailReply.adjust("東海林太郎さま", context: external) == "東海林太郎様")
        let colleague = MailReplyContext(name: "佐藤", honorific: "さん", external: false)
        #expect(MailReply.adjust("佐藤様にお送りしました。", context: colleague) == "佐藤様にお送りしました。")
        // 日本語でない文は変えない
        let english = MailReplyContext(name: "Smith", external: false)
        #expect(MailReply.adjust("Hi Smith, Best regards", context: english) == "Hi Smith, Best regards")
    }

    @Test func draftsGetTheAddresseeLine() {
        let c = MailReplyContext(name: "東海林", external: true)
        #expect(MailReply.finishDraft("お疲れ様です。\n承知いたしました。", context: c) == "東海林様\n\nお世話になっております。\n承知いたしました。")
        // 宛名を書いてあれば足さない
        #expect(MailReply.finishDraft("東海林様\n\nお世話になっております。", context: c) == "東海林様\n\nお世話になっております。")
        // 挨拶で始まらない下書きにも足さない
        #expect(MailReply.finishDraft("承知いたしました。", context: c) == "承知いたしました。")
    }

    @Test func polishFixesNameHonorificAndGreetingWithoutAI() async throws {
        let r = PolishRequest(transcript: "しょうじさん、お疲れ様です。資料を送ります", mode: .dictate, sourceLanguages: ["ja-JP"], targetLanguage: nil,
                              appName: "Mail", category: .email, styleDescription: "polite", personalStyle: nil,
                              vocabulary: [], corrections: [], notation: JapaneseNotation(),
                              surrounding: SurroundingText(after: appleMailQuote),
                              mailReply: MailReply.context(from: SurroundingText(after: appleMailQuote)))
        let out = try await Polisher.run(r, engine: nil)
        #expect(out.text == "東海林様、お世話になっております。資料を送ります")
        #expect(out.plain == out.text)
    }
}

@Suite struct SnippetTests {
    private let signature = Snippet(trigger: "署名", text: "--\n矢野 浩介\n株式会社ABC")
    private let opening = Snippet(trigger: "書き出し", text: "{宛名}\n\n{挨拶}\n矢野です。")
    private let closing = Snippet(trigger: "結び", text: "引き続きよろしくお願いいたします。")
    private var all: [Snippet] { [signature, opening, closing] }

    @Test func expandsTriggersSpokenAsTheirOwnSentence() {
        let p = SnippetExpander.split("資料をお送りします。署名", snippets: all)
        #expect(p.body == "資料をお送りします。")
        #expect(p.trailing == [signature])
        #expect(p.leading.isEmpty)

        let both = SnippetExpander.split("書き出し、資料をお送りします、結び 署名", snippets: all)
        #expect(both.leading == [opening])
        #expect(both.body == "資料をお送りします")
        #expect(both.trailing == [closing, signature])

        let only = SnippetExpander.split("署名。", snippets: all)
        #expect(only.body.isEmpty)
        #expect(only.trailing == [signature])
    }

    @Test func matchesByReading() {
        #expect(SnippetExpander.split("以上です。しょめい", snippets: all).trailing == [signature])
        #expect(SnippetExpander.split("ショメイ", snippets: all).trailing == [signature])
        #expect(SnippetExpander.split("thanks. My Signature", snippets: [Snippet(trigger: "my signature", text: "Yano")]).body == "thanks.")
    }

    @Test func leavesTriggerWordsInsideSentences() {
        #expect(SnippetExpander.split("署名をお願いします", snippets: all) == SnippetExpander.Parts(body: "署名をお願いします"))
        #expect(SnippetExpander.split("契約書の署名", snippets: all) == SnippetExpander.Parts(body: "契約書の署名"))
        #expect(SnippetExpander.split("電子署名", snippets: all) == SnippetExpander.Parts(body: "電子署名"))
        // 音声認識が句点を付けなくても、丁寧語の文末の後なら呼び出す
        let joined = SnippetExpander.split("よろしくお願いします署名", snippets: all)
        #expect(joined.body == "よろしくお願いします")
        #expect(joined.trailing == [signature])
        #expect(SnippetExpander.split("署名", snippets: []) == SnippetExpander.Parts(body: "署名"))
        // 本文が空の定型文は使わない
        #expect(SnippetExpander.split("署名", snippets: [Snippet(trigger: "署名", text: " ")]).trailing.isEmpty)
    }

    @Test func fillsInTheReplyPlaceholders() {
        let reply = MailReplyContext(name: "東海林", external: true)
        #expect(SnippetExpander.render(opening, reply: reply) == "東海林様\n\nお世話になっております。\n矢野です。")
        // 宛名がわからなければ、宛名の行と続く空行を書かない
        #expect(SnippetExpander.render(opening, reply: nil) == "お世話になっております。\n矢野です。")
        let colleague = MailReplyContext(name: "佐藤", honorific: "さん", external: false)
        #expect(SnippetExpander.render(opening, reply: colleague) == "佐藤さん\n\nお疲れ様です。\n矢野です。")
    }

    @Test func joinsSnippetsAsParagraphs() {
        let p = SnippetExpander.split("書き出し。資料をお送りします。署名", snippets: all)
        #expect(SnippetExpander.join(p, body: "資料をお送りします。", reply: nil)
                == "お世話になっております。\n矢野です。\n\n資料をお送りします。\n\n--\n矢野 浩介\n株式会社ABC")
        #expect(SnippetExpander.leadingBreak(SnippetExpander.split("署名", snippets: all), before: "よろしくお願いいたします。") == "\n\n")
        #expect(SnippetExpander.leadingBreak(SnippetExpander.split("署名", snippets: all), before: "よろしくお願いいたします。\n") == "")
        #expect(SnippetExpander.leadingBreak(SnippetExpander.split("本文です。署名", snippets: all), before: "前の文。") == "")
    }

    @Test func bodyIsPolishedNextToTheSnippetsNotTheCursor() {
        let p = SnippetExpander.split("書き出し。資料を送ります。署名", snippets: all)
        let s = SnippetExpander.surrounding(SurroundingText(before: "東海林様\n", after: "以上", screen: "画面"), around: p, reply: nil)
        #expect(s?.before == "お世話になっております。\n矢野です。\n\n")
        #expect(s?.after == "\n\n--\n矢野 浩介\n株式会社ABC")
        #expect(s?.screen == "画面")
    }

    @Test func settingsKeepSnippetsAndNewShortcut() throws {
        var s = AppSettings()
        #expect(s.revertLastShortcuts == [.commandOptionZ])
        #expect(s.mailReplyStyle)
        s.snippets = [signature]
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(decoded.snippets == [signature])
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"llmProvider": "claude"}"#.utf8))
        #expect(old.snippets.isEmpty)
        #expect(old.revertLastShortcuts == [.commandOptionZ])
    }
}

@Suite struct EmailDraftTests {
    private func request(category: AppCategory, reply: MailReplyContext? = nil) -> AskRequest {
        AskRequest(query: "了解しましたと返信を書いて", selection: nil, selectionEditable: false, hasFocusedTextField: true,
                   appName: "Mail", vocabulary: [], category: category, mailReply: reply)
    }

    @Test func emailAppsGetJapaneseEmailConventions() {
        #expect(!Prompts.askUser(request(category: .chat)).contains("お世話になっております"))
        let u = Prompts.askUser(request(category: .email))
        #expect(u.contains("お世話になっております。 for people outside the company"))
        #expect(u.contains("Do not write a signature"))
        #expect(!u.contains("replying to"))
    }

    @Test func replyContextNamesTheRecipient() {
        let u = Prompts.askUser(request(category: .email, reply: MailReplyContext(name: "佐藤", honorific: "さん", external: false)))
        #expect(u.contains("The user is replying to an email from 佐藤さん. The sender is a colleague, so open with お疲れ様です。"))
    }
}

@Suite struct TextDiffTests {
    @Test func showsRemovedAndAddedText() {
        let d = TextDiff.segments(from: "資料を送ります。", to: "資料をお送りします。")
        #expect(d.first == TextDiff.Segment(kind: .same, text: "資料を"))
        #expect(d.contains(TextDiff.Segment(kind: .added, text: "お")))
        // 消した部分と同じ部分をつなげると元の文、足した部分と同じ部分をつなげると新しい文になる
        let old = d.filter { $0.kind != .added }.map(\.text).joined()
        let new = d.filter { $0.kind != .removed }.map(\.text).joined()
        #expect(old == "資料を送ります。")
        #expect(new == "資料をお送りします。")
    }

    @Test func mergesSingleCharactersLeftBetweenRewrites() {
        let d = TextDiff.segments(from: "お客様が言ってた資料、見ました。", to: "お客様がおっしゃっていた資料を拝見しました。")
        #expect(d.filter { $0.kind != .added }.map(\.text).joined() == "お客様が言ってた資料、見ました。")
        #expect(d.filter { $0.kind != .removed }.map(\.text).joined() == "お客様がおっしゃっていた資料を拝見しました。")
        // 1 文字だけの同じ部分を、変更の間に残さない
        for (i, s) in d.enumerated() where s.kind == .same && i > 0 && i < d.count - 1 {
            #expect(s.text.count > 1)
        }
    }

    @Test func identicalTextIsOneSegment() {
        #expect(TextDiff.segments(from: "同じです。", to: "同じです。") == [TextDiff.Segment(kind: .same, text: "同じです。")])
        #expect(TextDiff.segments(from: "", to: "足した") == [TextDiff.Segment(kind: .added, text: "足した")])
    }
}
