import Foundation
import Testing
@testable import Koebumi

@Suite struct NormalizerTests {
    @Test func removesRecognizerSpacesInJapanese() {
        #expect(TextNormalizer.normalize("明日は 9時集合ですけど、違う 9時半に集合してください。") == "明日は9時集合ですけど、違う9時半に集合してください。")
        #expect(TextNormalizer.normalize("今何時 ？") == "今何時？")
        #expect(TextNormalizer.normalize("使用する図は概念図の方がいいでしょうか ？") == "使用する図は概念図の方がいいでしょうか？")
        #expect(TextNormalizer.normalize("会議は 3 時からです。 よろしく") == "会議は3時からです。よろしく")
    }

    @Test func keepsSpacesAroundLatinWords() {
        #expect(TextNormalizer.normalize("src の main.swift を開いて") == "src の main.swift を開いて")
        #expect(TextNormalizer.normalize("We ship  today .") == "We ship today.")
        #expect(TextNormalizer.normalize("안녕하세요 반갑습니다") == "안녕하세요 반갑습니다")  // 韓国語は空白で区切る
    }

    @Test func fixesWidthAndPunctuation() {
        #expect(TextNormalizer.normalize("ＡＢＣ１２３の件です、よろしく.") == "ABC123の件です、よろしく。")
        #expect(TextNormalizer.normalize("本当?すごい!") == "本当？すごい！")
        #expect(TextNormalizer.normalize("了解、、。明日ね。。") == "了解。明日ね。")
        #expect(TextNormalizer.normalize("Version 2.5 is out.") == "Version 2.5 is out.")
        #expect(TextNormalizer.normalize("你好,世界") == "你好，世界")  // 中国語は「，」
        #expect(TextNormalizer.normalize("了解,3時に行きます") == "了解、3時に行きます")
    }

    @Test func fixesFullwidthNumberPunctuation() {
        #expect(TextNormalizer.normalize("約３．５ギガで、１，０００円です。") == "約3.5ギガで、1,000円です。")
        #expect(TextNormalizer.normalize("１０：３０に集合") == "10:30に集合")
        #expect(TextNormalizer.normalize("はい，そうです．") == "はい，そうです．")  // 数字の間でなければ変えない
    }

    @Test func keepsLineStructure() {
        #expect(TextNormalizer.normalize("やること:\n1. 資料作成 \n2. 返信\n\n\n\n以上") == "やること:\n1. 資料作成\n2. 返信\n\n以上")
        #expect(TextNormalizer.normalize("- item\n  - nested") == "- item\n  - nested")
    }
}

@Suite struct JapaneseNumbersTests {
    private func arabize(_ text: String) -> String { JapaneseNumbers.arabize(text) }

    @Test func convertsNumbersWithUnits() {
        // この Mac のモデル（Qwen3-ASR）で実際に書き起こされた文
        #expect(arabize("明日のミーティングは三時からで、あいや四時からです。") == "明日のミーティングは3時からで、あいや4時からです。")
        #expect(arabize("明日から三連休です。一日目は海に行って、二日目は山に行って、三日目は空の旅をします。")
                == "明日から3連休です。1日目は海に行って、2日目は山に行って、3日目は空の旅をします。")
        #expect(arabize("話すことが二つあります。一つ目はメールについて。") == "話すことが2つあります。1つ目はメールについて。")
        #expect(arabize("三千万。") == "3000万。")
        #expect(arabize("三千回。") == "3000回。")
        #expect(arabize("明日から三日間いや四日間アメリカに行きます。") == "明日から3日間いや4日間アメリカに行きます。")
        #expect(arabize("二泊三日で、一人あたり十二万五千円です。") == "2泊3日で、1人あたり12万5000円です。")
        #expect(arabize("二〇二六年十月二十二日の午後一時十五分") == "2026年10月22日の午後1時15分")
        #expect(arabize("一億二千万人") == "1億2000万人")
        #expect(arabize("三時半に駅の三番線、十分後に出発") == "3時半に駅の3番線、10分後に出発")
        #expect(arabize("一時から二時間、三十人ぐらい") == "1時から2時間、30人ぐらい")
        #expect(arabize("五百円玉を三枚") == "500円玉を3枚")
        #expect(arabize("三月中旬に二十五パーセント") == "3月中旬に25パーセント")
        #expect(arabize("一点五倍で、全体の三分の一") == "1.5倍で、全体の3分の1")
        #expect(arabize("第三回の会議") == "第3回の会議")
    }

    @Test func keepsWordsWithNumerals() {
        for text in ["一緒に行こう", "一番好きな色", "もう一度言って", "一度も行ったことがない", "一時的に止める", "一時はどうなるかと思った",
                     "それで十分です", "十分に気をつけて", "三日月がきれい", "三日坊主", "二日酔い", "六本木に行く", "一本化する",
                     "統一する", "唯一の方法", "同一人物", "数十人が来た", "何百回も言った", "一人で行く", "一人暮らし", "一人一人に聞く",
                     "二度と行かない", "人一倍頑張る", "十人十色", "百人一首", "三位一体", "一回り大きい", "関東一円", "ご一行様",
                     "二三日休む", "七五三のお祝い", "〇〇さん", "万が一", "一部の人", "四十七士", "八百屋", "九十九里浜", "一年中", "四日市", "千代田区"] {
            #expect(arabize(text) == text)
        }
    }

    @Test func runsOnlyOnJapanese() {
        #expect(TextNormalizer.normalize("明日の会議は三時からです。") == "明日の会議は3時からです。")
        // かなのない文は、数と単位だけのときに直す。中国語は変えない
        #expect(TextNormalizer.normalize("三千万。") == "3000万。")
        #expect(TextNormalizer.normalize("十二月二十日") == "12月20日")
        #expect(TextNormalizer.normalize("我有三本书") == "我有三本书")
        #expect(TextNormalizer.normalize("快一点。") == "快一点。")
    }
}

@Suite struct ListTidierTests {
    @Test func dropsSpokenEndingOnLastItem() {
        #expect(ListTidier.tidy("やることは2つあります。\n1. 資料作成\n2. 返信です。") == "やることは2つあります。\n1. 資料作成\n2. 返信")
        #expect(ListTidier.tidy("今日やることは3つあります。\n1. 請求書の確認\n2. メールの返信\n3. 来週の準備です。")
                == "今日やることは3つあります。\n1. 請求書の確認\n2. メールの返信\n3. 来週の準備")
        #expect(ListTidier.tidy("- 牛乳\n- 卵\n- パン。") == "- 牛乳\n- 卵\n- パン")
    }

    @Test func keepsSentenceItems() {
        // 項目がどれも文なら句点は残す
        let steps = "やり方は次のとおりです。\n1. 電源を切ってください。\n2. 5分待ってください。"
        #expect(ListTidier.tidy(steps) == steps)
        #expect(ListTidier.tidy("明日は晴れです。") == "明日は晴れです。")
        // 最後の項目の後に続けた文の句点は外さない
        #expect(ListTidier.tidy("1. 資料作成\n2. 返信です。以上です。") == "1. 資料作成\n2. 返信です。以上です。")
    }
}

@Suite struct VocabularyTests {
    let aliases = ["クロードコード": "Claude Code", "スピーク": "Speak", "cube cuddle": "kubectl", "棚香": "田中"]

    @Test func replacesHeardForms() {
        #expect(VocabularyReplacer.apply("来週クロードコードのデモ", aliases: aliases) == "来週Claude Codeのデモ")
        #expect(VocabularyReplacer.apply("run Cube Cuddle get pods", aliases: aliases) == "run kubectl get pods")
        #expect(VocabularyReplacer.apply("棚香さんと会います", aliases: aliases) == "田中さんと会います")
    }

    @Test func respectsWordBoundaries() {
        #expect(VocabularyReplacer.apply("スピーカーを起動、スピークを起動", aliases: aliases) == "スピーカーを起動、Speakを起動")
        #expect(VocabularyReplacer.apply("cube cuddles", aliases: aliases) == "cube cuddles")
    }

    @Test func csvKeepsHeardAs() {
        let csv = "term,source,heard_as\nClaude Code,manual,\"クロードコード, クロード・コード\"\nSpeak,auto,\n\"Foo, Inc.\",manual"
        let rows = DictionaryStore.parseCSVRows(csv)
        #expect(rows.map(\.term) == ["Claude Code", "Speak", "Foo, Inc."])
        #expect(rows.map(\.heard) == ["クロードコード, クロード・コード", nil, nil])
    }

    @Test func dictionaryEntryAliases() {
        let e = DictionaryEntry(term: "Claude Code", source: .manual, replaced: "クロードコード, クロード・コード、Claude Code")
        #expect(e.aliases == ["クロードコード", "クロード・コード"])
    }
}

@Suite struct SpokenCommandTests {
    @Test func convertsStandaloneCommands() {
        #expect(SpokenCommands.apply("お疲れ様です。改行。明日の件です。") == "お疲れ様です。\n明日の件です。")
        #expect(SpokenCommands.apply("お疲れ様です、段落、明日の件です") == "お疲れ様です\n\n明日の件です")
        #expect(SpokenCommands.apply("Thanks. New line. Bob") == "Thanks.\nBob")
        #expect(SpokenCommands.apply("よろしくお願いします。新しい段落田中です。") == "よろしくお願いします。\n\n田中です。")
        #expect(SpokenCommands.apply("Hey Tom, new paragraph. Thanks") == "Hey Tom,\n\nThanks")
    }

    @Test func leavesWordsInsideSentences() {
        #expect(SpokenCommands.apply("改行コードはLFにしてください") == "改行コードはLFにしてください")
        #expect(SpokenCommands.apply("この段落は長いです") == "この段落は長いです")
        #expect(SpokenCommands.apply("Add a new line here") == "Add a new line here")
        #expect(SpokenCommands.apply("表の最後に。新しい行を追加して") == "表の最後に。新しい行を追加して")
    }
}

@Suite struct BasicCleanerTests {
    @Test func removesJapaneseFillers() {
        #expect(BasicCleaner.clean("えーと、明日はあの、晴れです") == "明日は晴れです")
        #expect(BasicCleaner.clean("で、明日は 9時集合です。") == "明日は9時集合です。")
        #expect(BasicCleaner.clean("DCワンは概念図を使用しました。そうですね。あー。") == "DCワンは概念図を使用しました。そうですね。")
        #expect(BasicCleaner.clean("あの人はまあまあです") == "あの人はまあまあです")
    }

    @Test func fillerOnlySpeechBecomesEmpty() {
        #expect(BasicCleaner.clean("えーと、あのー") == "")
        #expect(BasicCleaner.clean("うーん、えっと、まあ、") == "")
        #expect(BasicCleaner.removeFillers("えーと、明日は晴れです。") == "明日は晴れです。")
        #expect(BasicCleaner.removeFillers("まあ、いいか。") == "まあ、いいか。")  // 意味のある語は AI の判断に任せる
        #expect(BasicCleaner.removeFillers("やること:\n1. 資料\nUm, 2. 返信") == "やること:\n1. 資料\n2. 返信")  // 行をつなげない
        #expect(BasicCleaner.removeFillers("です。えーと\n次の件") == "です。\n次の件")
        #expect(BasicCleaner.removeFillers("なんか、今日は疲れたなって感じ。") == "今日は疲れたなって感じ。")
        #expect(BasicCleaner.removeFillers("で、明日は9時半に集合してください。") == "明日は9時半に集合してください。")
        #expect(BasicCleaner.removeFillers("あの人はなんか、元気だね") == "あの人はなんか、元気だね")  // 文頭だけ
    }

    @Test func removesEnglishFillersOnly() {
        #expect(BasicCleaner.clean("um so uh we ship today") == "So we ship today")
        #expect(BasicCleaner.clean("I think, uh, we should, um, ship it") == "I think we should ship it")
        #expect(BasicCleaner.clean("Do you know the the answer?") == "Do you know the answer?")
        #expect(BasicCleaner.clean("Use a 5 mm screw") == "Use a 5 mm screw")
    }
}

@Suite struct OutputGuardTests {
    @Test func acceptsNormalCleanup() {
        #expect(OutputGuard.accepts(source: "えーと、明日の会議なんですけど、あのー、資料を準備しておいてください。", output: "明日の会議なんですけど、資料を準備しておいてください。"))
        #expect(OutputGuard.accepts(source: "明日は田中さんと、いや、違う、佐藤さんと、いや、やっぱり田中さんと打ち合わせです", output: "明日は田中さんと打ち合わせです。"))
        #expect(OutputGuard.accepts(source: "やることは3つあって、1つ目は資料作成、2つ目はメールの返信、3つ目は会議の準備です。",
                                    output: "やることは3つあります。\n1. 資料作成\n2. メールの返信\n3. 会議の準備"))
        #expect(OutputGuard.accepts(source: "um so let's ship it on Tuesday, no wait, Wednesday", output: "Let's ship it on Wednesday."))
        #expect(OutputGuard.accepts(source: "クロードコードを開いて", output: "Claude Codeを開いて。", vocabulary: ["Claude Code"]))
        #expect(OutputGuard.accepts(source: "はい", output: "はい。"))
        #expect(OutputGuard.accepts(source: "今何時", output: "今何時？"))
    }

    @Test func rejectsAnswersAndRefusals() {
        #expect(!OutputGuard.accepts(source: "自己紹介してください。", output: "こんにちは！私はAIアシスタントです。文章の作成や質問への回答など、さまざまなお手伝いができます。"))
        #expect(!OutputGuard.accepts(source: "日本の首都はどこですか", output: "東京です。"))
        #expect(!OutputGuard.accepts(source: "write me a poem about the ocean", output: "I'm sorry, but I can't help with that."))
        #expect(!OutputGuard.accepts(source: "今週の振り返りです。月曜日はクライアントと打ち合わせをして、火曜日と水曜日は実装を進めました。", output: "振り返り。"))
        #expect(!OutputGuard.accepts(source: "明日は晴れです", output: ""))
    }

    @Test func checksCorrectedPartIsKept() {
        let source = "明日は9時集合ですけど、違う9時半に集合してください。"
        #expect(OutputGuard.keepsCorrection(source: source, output: "明日は9時半に集合してください。"))
        #expect(!OutputGuard.keepsCorrection(source: source, output: "明日は9時集合です。"))
        #expect(OutputGuard.keepsCorrection(source: "明日は晴れです", output: "明日は晴れです。"))
    }

    @Test func keepsParticlesAfterQuantities() {
        #expect(!OutputGuard.keepsQuantityParticles(source: "明日は3時に4時からの会議の準備をします。", output: "明日は3時から4時からの会議の準備をします。"))
        #expect(!OutputGuard.keepsQuantityParticles(source: "明日の会議3時に4時からでお願いします。", output: "明日の会議は3時から4時までお願いします。"))
        #expect(OutputGuard.keepsQuantityParticles(source: "明日の会議3時に4時からでお願いします。", output: "明日の会議4時からでお願いします。"))
        #expect(!OutputGuard.keepsQuantityParticles(source: "3時に、4時からの会議の資料を送ります。", output: "3時、4時からの会議の資料を送ります。"))
        #expect(OutputGuard.keepsQuantityParticles(source: "予算は300万円で、納期は12月15日です。", output: "予算は300万円で、納期は12月15日です。"))
        // ビジネス敬語の「から → より」は意味が変わらない
        #expect(OutputGuard.keepsQuantityParticles(source: "明日3時から打ち合わせです", output: "明日3時より打ち合わせがございます。"))
    }

    @Test func keepsCasualRegister() {
        #expect(!OutputGuard.keepsRegister(source: "答えが間違ってた", output: "答えが間違っていました。"))
        #expect(!OutputGuard.keepsRegister(source: "明日の天気を教えて", output: "明日の天気を教えてください。"))
        #expect(OutputGuard.keepsRegister(source: "明日の天気を教えてください", output: "明日の天気を教えてください。"))
        #expect(OutputGuard.keepsRegister(source: "了解", output: "了解。"))
        #expect(OutputGuard.keepsRegister(source: "こっちの方がましだ", output: "こっちの方がましだ。"))
    }

    @Test func keepsCasualQuestionsCasual() {
        #expect(OutputGuard.keepingCasualQuestions(source: "今何時", output: "今何時ですか？") == "今何時？")
        #expect(OutputGuard.keepingCasualQuestions(source: "会議室はどこですか", output: "会議室はどこですか？") == "会議室はどこですか？")
    }
}

@Suite struct LineBreakMergeTests {
    @Test func insertsSpokenLineBreakWhereTheWordWasDropped() {
        // SpeechTranscriber は「改行」を捨て、その時間を次の語「明」に含める
        let segments = [[TimedText(text: "お疲れ様です", start: 0, end: 1.14), TimedText(text: "。", start: 1.14, end: 1.32),
                         TimedText(text: "明", start: 1.32, end: 2.34), TimedText(text: "日です。", start: 2.34, end: 3.3)]]
        let breaks = [TimedText(text: "\n", start: 1.44, end: 1.92)]
        #expect(AppleSpeechSession.compose(segments, lineBreaks: breaks, unspaced: true) == "お疲れ様です。\n明日です。")
        #expect(AppleSpeechSession.compose(segments, lineBreaks: [], unspaced: true) == "お疲れ様です。明日です。")
    }

    @Test func joinsSegmentsWithSpacesForSpacedLanguages() {
        let segments = [[TimedText(text: "Hello there.", start: 0, end: 1)], [TimedText(text: " How are you?", start: 1.2, end: 2)]]
        #expect(AppleSpeechSession.compose(segments, lineBreaks: [], unspaced: false) == "Hello there. How are you?")
    }
}

@Suite struct TranslationCheckTests {
    @Test func detectsUntranslatedOutput() {
        #expect(!Languages.isWritten("明日の会議資料を送ってください", in: "ko-KR"))
        #expect(Languages.isWritten("내일 회의 자료를 보내 주세요.", in: "ko-KR"))
        #expect(!Languages.isWritten("Please send me the slides", in: "ja-JP"))
        #expect(Languages.isWritten("正午までにスライドを送ってください。", in: "ja-JP"))
        #expect(Languages.isWritten("请把明天会议的资料发给我。", in: "zh-CN"))
        #expect(!Languages.isWritten("明日の会議の資料を送ってください", in: "zh-CN"))
        #expect(Languages.isWritten("Mañana parece que va a llover.", in: "es-ES"))
        #expect(Languages.isWritten("Could we use Claude Code?", in: "en-US"))
        #expect(!Languages.isWritten("明日は雨です", in: "en-US"))
    }
}

@Suite struct PromptTests {
    @Test func detectsSelfCorrections() {
        #expect(Prompts.correctionHint("明日は9時集合ですけど、違う9時半に集合してください。") != nil)
        #expect(Prompts.correctionHint("ランチはカレーにしよう、やっぱりラーメンにしよう。") != nil)
        #expect(Prompts.correctionHint("金曜日に、あ、木曜日に提出します") != nil)
        #expect(Prompts.correctionHint("ship it Tuesday, no wait, Wednesday") != nil)
        #expect(Prompts.correctionHint("明日は晴れです") == nil)
        #expect(Prompts.correctionHint("あの人は意見が違う") == nil)
        #expect(Prompts.correctionHint("あ、そうだ、明日は休みです") == nil)  // 文頭の「あ、」は感嘆
        #expect(Prompts.correctionHint("会議は3時から、じゃなくて4時からに変更になりました。") != nil)
        #expect(Prompts.correctionHint("猫じゃなくて犬が好きです。") == nil)  // 対比
        #expect(Prompts.correctionHint("このラーメン、やっぱり美味しいね。") == nil)
        #expect(Prompts.correctionHint("いや、それは違うと思います。") == nil)
        #expect(Prompts.correctionHint("そうですね。いや、それは違うと思います。") == nil)
        #expect(Prompts.correctionHint("会議は3時からいや4時からに変更になりました。") != nil)  // 認識で読点が消えた
        #expect(Prompts.correctionHint("ランチはカレーにしよう。やっぱりラーメンにしよう。") != nil)  // 認識で文が分かれた
        // 認識で「いや」が「に」になった・落ちた言い直し
        #expect(Prompts.correction(in: "明日の会議3時に4時からでお願いします。")?.after == "4時からでお願いします")
        #expect(Prompts.correction(in: "明日の会議3時4時からでお願いします。")?.after == "4時からでお願いします")
        #expect(Prompts.correction(in: "会議は3時から4時までです。") == nil)  // 範囲
        #expect(Prompts.correction(in: "1日2日で終わります。") == nil)  // 言い回し
        #expect(Prompts.correction(in: "10人に1人が持っています。") == nil)  // 割合
        #expect(Prompts.correction(in: "5回に1回は失敗します。") == nil)
        #expect(Prompts.correction(in: "プランは1000円、2000円、3000円の3種類です。") == nil)  // 列挙
        #expect(Prompts.correction(in: "1回、2回と繰り返します。") == nil)
        #expect(Prompts.correction(in: "3時に2時間ほど作業します。") == nil)  // 後の数は「2時間」
        #expect(Prompts.correction(in: "3人で5人分の仕事をした。") == nil)
        #expect(Prompts.correction(in: "会議は3時に4時半からでお願いします。")?.after == "4時半からでお願いします")
        #expect(Prompts.correction(in: "3時に、4時からの会議の資料を送ります。") == nil)  // 後の時刻は「会議」にかかる
        // 数字だけが違う「じゃなくて」は言い直し
        #expect(Prompts.correction(in: "明日の会議は3時じゃなくて4時からでお願いします。")?.after == "4時からでお願いします")
        // 認識で「あ、いや」が「あいや」とつながった
        #expect(Prompts.correction(in: "明日から3時の会議があり。あいや、4時の会議があります。")?.after == "4時の会議があります")
        #expect(Prompts.correction(in: "明日のミーティングは3時からで、あいや4時からです。")?.after == "4時からです")
        let double = Prompts.correction(in: "金額は50万円、あ、違う、55万円でお願いします。")
        #expect(double?.before == "金額は50万円")
        #expect(double?.after == "55万円でお願いします")
    }

    @Test func detectsEnumerations() {
        #expect(Prompts.listHint("やることは3つあって、1つ目は資料作成、2つ目はメールの返信、3つ目は会議の準備です。") != nil)
        #expect(Prompts.listHint("手順としては、まずアプリをインストールして、次にアカウントを作成して、最後に通知をオンにしてください。") != nil)
        #expect(Prompts.listHint("we need first the budget second the timeline") != nil)
        #expect(Prompts.listHint("At first I was worried, but I finally finished it") == nil)
        #expect(Prompts.listHint("昨日は買い物に行って、それから映画を見た") == nil)
        #expect(Prompts.listHint("まず結論から言うと、明日は休みです。") == nil)
        #expect(Prompts.listHint("明日は晴れです") == nil)
    }

    @Test func splitsLongTranscriptsAtSentences() {
        let text = String(repeating: "これはテストの文です。", count: 30)
        let parts = Prompts.split(text, limit: 100)
        #expect(parts.count == 4)
        #expect(parts.allSatisfy { $0.text.count <= 100 && $0.text.hasSuffix("。") })
        #expect(parts.map { $0.text + $0.separator }.joined() == text)
        #expect(Prompts.split("short", limit: 100).map(\.text) == ["short"])
        let lines = Prompts.split("Hey Tom,\n\nThanks for the deck.\nBob", limit: 100)
        #expect(lines.map(\.text) == ["Hey Tom,", "Thanks for the deck.", "Bob"])
        #expect(lines.map(\.separator) == ["\n\n", "\n", ""])
    }

    @Test func translationPromptEndsWithTarget() {
        let r = PolishRequest(transcript: "こんにちは", mode: .translate, sourceLanguages: ["ja-JP"], targetLanguage: "en-US",
                              appName: "Slack", category: .chat, styleDescription: "casual", personalStyle: nil,
                              vocabulary: [], corrections: [])
        #expect(Prompts.polishUser(r).hasSuffix("Write it in English (United States)."))
    }

    @Test func rewriteKeepsLanguageUnlessAsked() {
        #expect(Prompts.changesLanguage(selection: "明日行けないわ", output: "I cannot attend tomorrow.", request: "もっと丁寧にして"))
        #expect(!Prompts.changesLanguage(selection: "明日の会議は中止です", output: "Tomorrow's meeting is canceled.", request: "これを英語にして"))
        #expect(!Prompts.changesLanguage(selection: "明日行けないわ", output: "明日は伺えません。", request: "もっと丁寧にして"))
    }

    @Test func cleanOutputStripsLabels() {
        #expect(Prompts.cleanOutput("Output: Hello there") == "Hello there")
        #expect(Prompts.cleanOutput("出力：こんにちは") == "こんにちは")
    }
}
