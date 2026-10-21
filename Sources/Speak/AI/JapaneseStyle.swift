import Foundation

/// 日本語の句読点の組み合わせ
enum JapanesePunctuation: String, Codable, CaseIterable, Identifiable {
    case standard  // 、。
    case commaMaru  // ，。
    case commaPeriod  // ，．
    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return t("「、」と「。」", "、 and 。")
        case .commaMaru: return t("「，」と「。」", "， and 。")
        case .commaPeriod: return t("「，」と「．」", "， and ．")
        }
    }

    var comma: String { self == .standard ? "、" : "，" }
    var period: String { self == .commaPeriod ? "．" : "。" }
}

/// 日本語の文中にある英単語の前後の空白
enum LatinSpacing: String, Codable, CaseIterable, Identifiable {
    case keep, remove, insert
    var id: String { rawValue }

    var title: String {
        switch self {
        case .keep: return t("そのまま", "Leave as is")
        case .remove: return t("入れない（iPhoneを）", "None (iPhoneを)")
        case .insert: return t("入れる（iPhone を）", "Add (iPhone を)")
        }
    }
}

/// 日本語の表記ルール。AI の出力を決まった処理でそろえる（AI に指示すると小さいモデルの言い回しが崩れるため、指示はしない）。
struct JapaneseNotation: Codable, Equatable {
    var punctuation: JapanesePunctuation = .standard
    var latinSpacing: LatinSpacing = .keep
    /// 補助動詞・形式名詞などをひらがなで書く（〜して下さい → 〜してください）
    var hiraganaForms = true
    /// 疑問文の文末を「？」にする（〜ですか。 → 〜ですか？）
    var questionMark = true
    /// チャットでは文末の「。」を付けない
    var omitChatPeriod = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = JapaneseNotation()
        punctuation = (try? c.decodeIfPresent(JapanesePunctuation.self, forKey: .punctuation)) ?? d.punctuation
        latinSpacing = (try? c.decodeIfPresent(LatinSpacing.self, forKey: .latinSpacing)) ?? d.latinSpacing
        hiraganaForms = (try? c.decodeIfPresent(Bool.self, forKey: .hiraganaForms)) ?? d.hiraganaForms
        questionMark = (try? c.decodeIfPresent(Bool.self, forKey: .questionMark)) ?? d.questionMark
        omitChatPeriod = (try? c.decodeIfPresent(Bool.self, forKey: .omitChatPeriod)) ?? d.omitChatPeriod
    }
}

/// 日本語の出力を表記ルールに合わせる決まった処理。TextNormalizer で全角・半角と空白をそろえた後に使う。
enum JapaneseFormatter {
    static func apply(_ text: String, notation: JapaneseNotation, category: AppCategory) -> String {
        // かなを含む文だけを日本語とみなす（中国語や英語の出力は変えない）
        guard text.contains(where: { CharClass($0) == .kana }) else { return text }
        var t = fixDoubleHonorifics(text)
        if notation.hiraganaForms { t = openKanji(t) }
        if notation.questionMark { t = markQuestions(t) }
        t = punctuate(t, notation.punctuation)
        t = space(t, notation.latinSpacing)
        if notation.omitChatPeriod, category == .chat {
            t = t.replacingOccurrences(of: #"(?m)[。．](?=[ \t]*$)"#, with: "", options: .regularExpression)
        }
        return t
    }

    private static func punctuate(_ text: String, _ style: JapanesePunctuation) -> String {
        var t = text
        for c in ["、", "，"] where c != style.comma { t = t.replacingOccurrences(of: c, with: style.comma) }
        for p in ["。", "．"] where p != style.period { t = t.replacingOccurrences(of: p, with: style.period) }
        return t
    }

    /// 丁寧語の疑問の文末（〜ですか。〜ませんか。）を「？」で終える。句点のない行末も同じ。
    /// 「そうか。」「いいか。」のような独り言や、「今何時」のように語尾で疑問とわからない文は変えない
    static func markQuestions(_ text: String) -> String {
        text.replacingOccurrences(of: #"(?m)(です|ます|でしょう|ません|ました|でした|ましょう)か(?:[。．]|(?=[ \t]*$))"#,
                                  with: "$1か？", options: .regularExpression)
    }

    private static let japaneseLetter = #"[\p{Han}\p{Hiragana}\p{Katakana}ー々]"#
    /// 英字で始まる語（iPhone, GPT-5, Node.js, C++）
    private static let latinWord = #"[A-Za-z](?:[A-Za-z0-9+#._/-]*[A-Za-z0-9+#])?"#

    private static func space(_ text: String, _ rule: LatinSpacing) -> String {
        switch rule {
        case .keep:
            return text
        case .remove:
            var t = text.replacingOccurrences(of: "(?<=\(japaneseLetter)) +(?=[A-Za-z0-9])", with: "", options: .regularExpression)
            t = t.replacingOccurrences(of: "(?<=[A-Za-z0-9]) +(?=\(japaneseLetter))", with: "", options: .regularExpression)
            return t
        case .insert:
            // 英字で始まる語の両側にだけ入れる。「3時」「10分」のような数字と単位はつなげたまま
            let t = NSMutableString(string: text)
            let matches = latinWordRegex.matches(in: text, range: NSRange(location: 0, length: t.length))
            for m in matches.reversed() {
                if m.range.upperBound < t.length, isJapaneseLetter(t, at: m.range.upperBound) {
                    t.insert(" ", at: m.range.upperBound)
                }
                if m.range.location > 0, isJapaneseLetter(t, at: m.range.location - 1) {
                    t.insert(" ", at: m.range.location)
                }
            }
            return t as String
        }
    }

    private static let latinWordRegex = try! NSRegularExpression(pattern: latinWord)

    private static func isJapaneseLetter(_ s: NSString, at index: Int) -> Bool {
        let r = s.rangeOfComposedCharacterSequence(at: index)
        return s.substring(with: r).range(of: "^\(japaneseLetter)$", options: .regularExpression) != nil
    }

    /// 補助動詞・形式名詞などの「ひらく」書き方（公用文作成の考え方・記者ハンドブックの方針に沿う）。
    /// 本来の意味の動詞・名詞（「資料を下さい」「大事」「出来事」）は変えないよう、前後の文字で絞る。
    private static let openings: [(pattern: String, template: String)] = [
        // 補助動詞: 〜して下さい・ご確認下さい → ください
        (#"(?<=[てで])下さ(?=[いるっれら])"#, "くださ"),
        (#"(?<=[おご]\p{Han}{1,3}\p{Hiragana}{0,2})下さ(?=[いるっれら])"#, "くださ"),
        // 〜して頂く・ご確認頂けますか → いただく
        (#"(?<=[てで])頂(?=[きくけこ])"#, "いただ"),
        (#"(?<=[おご]\p{Han}{1,3}\p{Hiragana}{0,2})頂(?=[きくけこ])"#, "いただ"),
        // お願い致します・ご連絡致します → いたします（「一致します」は変えない）
        (#"(?<=\p{Hiragana})致(?=し[まてた])"#, "いた"),
        (#"(?<=[おご]\p{Han}{1,3})致(?=し[まてた])"#, "いた"),
        // 出来る → できる（「出来事」「上出来」は変えない）
        (#"(?<![上不])出来(?=[るなたれずまそて])"#, "でき"),
        // 形式名詞: する事が → することが、行く時に → 行くときに、その為に → そのために、この様に → このように
        (#"(?<=\p{Hiragana})事(?=[がはをにもで、。]|から|まで|より|$)"#, "こと"),
        (#"(?<=[るたいうくすつぬむぶぐなだ])時(?=[はにのもで、]|まで|から)"#, "とき"),
        (#"(?<=[のるたいな])為(?=[にのだで、。])"#, "ため"),
        (#"(?<=[のな])様(?=[にな]|です|だ)"#, "よう"),
        // 接続詞・あいさつ
        (#"(?<!\p{Han})又(?=は|、)"#, "また"),
        (#"(?<!\p{Han})但し"#, "ただし"),
        (#"宜しく"#, "よろしく"),
        (#"有難う"#, "ありがとう"),
        (#"御座い"#, "ござい"),
    ]

    /// 二重敬語（おっしゃられる・ご覧になられる）を正しい形に直す。「部長になられた」のような単独の敬語は変えない
    private static let doubleHonorifics: [(pattern: String, template: String)] = [
        (#"おっしゃられ(?=[たて])"#, "おっしゃっ"),
        (#"おっしゃられ(?=ま)"#, "おっしゃい"),
        (#"おっしゃられる"#, "おっしゃる"),
        (#"おっしゃられ(?=な)"#, "おっしゃら"),
        (#"(?<=ご覧|お召し上がり|[おご]\p{Han}{1,2}\p{Hiragana}?)になられ(?=[たて])"#, "になっ"),
        (#"(?<=ご覧|お召し上がり|[おご]\p{Han}{1,2}\p{Hiragana}?)になられ(?=ま)"#, "になり"),
        (#"(?<=ご覧|お召し上がり|[おご]\p{Han}{1,2}\p{Hiragana}?)になられる"#, "になる"),
    ]

    static func fixDoubleHonorifics(_ text: String) -> String {
        var t = text
        for (pattern, template) in doubleHonorifics {
            t = t.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return t
    }

    static func openKanji(_ text: String) -> String {
        var t = text
        for (pattern, template) in openings {
            t = t.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return t
    }
}
