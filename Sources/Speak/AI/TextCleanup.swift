import Foundation

/// 文字の種類（表記の統一と辞書の置き換えで使う）
enum CharClass {
    case kana, han, cjkPunct, latin, digit, space, newline, other

    init(_ c: Character) {
        if c.isNewline { self = .newline; return }
        guard let s = c.unicodeScalars.first else { self = .other; return }
        switch s.value {
        case 0x20, 0x3000, 0x09: self = .space
        case 0x3040...0x309F, 0x30A0...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9F: self = .kana
        case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0xF900...0xFAFF, 0x3005: self = .han  // 々 も漢字として扱う
        case 0x3001...0x3004, 0x3008...0x3011, 0x3014...0x301F, 0xFF01...0xFF0F, 0xFF1A...0xFF20, 0xFF3B...0xFF40, 0xFF5B...0xFF65:
            self = .cjkPunct
        case 0x30...0x39: self = .digit
        default:
            self = c.isLetter ? .latin : .other
        }
    }

    /// 日本語・中国語の文字（単語を空白で区切らない）
    var isCJK: Bool { self == .kana || self == .han }
}

/// 認識結果と整形結果の表記をそろえる決まった処理（AI を使わない）。
/// 音声認識が日本語の文中に入れる空白（「明日は 9時」「今何時 ？」）や半角の「?」、全角英数字を直す。
enum TextNormalizer {
    static func normalize(_ text: String) -> String {
        let japanese = text.contains { CharClass($0) == .kana }
        var chars = Array(text).map(halfwidthAlphanumeric)

        // 日本語・中国語の後ろの半角句読点を全角にする
        for i in chars.indices where i > 0 && CharClass(chars[i - 1]).isCJK {
            let next = i + 1 < chars.count ? CharClass(chars[i + 1]) : .newline
            switch chars[i] {
            case "?": chars[i] = "？"
            case "!": chars[i] = "！"
            case ",": if next != .digit { chars[i] = japanese ? "、" : "，" }
            case ".": if [.newline, .space].contains(next) || next.isCJK { chars[i] = "。" }
            default: break
            }
        }

        // 空白の連なりを、前後の文字を見て消すか 1 つにまとめる（行頭のインデントは残す）
        var out: [Character] = []
        var i = 0
        while i < chars.count {
            let c = chars[i]
            guard CharClass(c) == .space else {
                out.append(c)
                i += 1
                continue
            }
            var j = i
            while j < chars.count, CharClass(chars[j]) == .space { j += 1 }
            let atLineStart = out.isEmpty || out.last?.isNewline == true
            if atLineStart {
                out.append(contentsOf: chars[i..<j].map { $0 == "\u{3000}" ? " " : $0 })
            } else if j < chars.count, !chars[j].isNewline, !shouldDropSpace(between: out.last!, and: chars[j]) {
                out.append(" ")
            }
            i = j
        }

        var t = String(out)
        // 重なった句読点（「、。」「。。」）をまとめる
        t = t.replacingOccurrences(of: #"[、，]+([。．！？])"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"([、，。！？])[、，。]+"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(?m)^[、，。]+"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func shouldDropSpace(between a: Character, and b: Character) -> Bool {
        let ca = CharClass(a), cb = CharClass(b)
        if ca == .cjkPunct || cb == .cjkPunct { return true }
        if ca.isCJK && (cb.isCJK || cb == .digit) { return true }
        if cb.isCJK && ca == .digit { return true }
        // 英語の句読点の前の空白（"hello , world"）
        if [",", ".", "?", "!", ";", ":"].contains(b), ca == .latin || ca == .digit { return true }
        return false
    }

    /// 全角英数字（ＡＢＣ１２３）を半角にする。全角カタカナや記号はそのまま。
    private static func halfwidthAlphanumeric(_ c: Character) -> Character {
        guard c.unicodeScalars.count == 1, let s = c.unicodeScalars.first else { return c }
        switch s.value {
        case 0xFF10...0xFF19, 0xFF21...0xFF3A, 0xFF41...0xFF5A:
            return Character(UnicodeScalar(s.value - 0xFEE0)!)
        default:
            return c
        }
    }
}

/// 辞書の「聞き取られ方」（例: スピーク → Speak）を正しい表記に置き換える。
/// Apple の音声認識は辞書のヒントを使わず、英語の語をカタカナで書くため、認識後に直す。
enum VocabularyReplacer {
    static func apply(_ text: String, aliases: [String: String]) -> String {
        guard !aliases.isEmpty, !text.isEmpty else { return text }
        var t = text
        // 長い表記から置き換える（「クロードコード」を「クロード」より先に）
        for (alias, term) in aliases.sorted(by: { $0.key.count > $1.key.count }) where !alias.isEmpty && alias != term {
            t = replace(alias, with: term, in: t)
        }
        return t
    }

    private static func replace(_ alias: String, with term: String, in text: String) -> String {
        let first = CharClass(alias.first!), last = CharClass(alias.last!)
        var result = ""
        var rest = text[...]
        while let r = rest.range(of: alias, options: [.caseInsensitive]) {
            let before = r.lowerBound > rest.startIndex ? rest[rest.index(before: r.lowerBound)] : (result.last ?? " ")
            let after = r.upperBound < rest.endIndex ? rest[r.upperBound] : " "
            // 「スピーカー」の中の「スピーク」や "speaker" の中の "speak" は置き換えない
            let joined = continues(first, CharClass(before)) || continues(last, CharClass(after))
            result += rest[..<r.lowerBound]
            result += joined ? String(rest[r]) : term
            rest = rest[r.upperBound...]
        }
        return result + rest
    }

    private static func continues(_ edge: CharClass, _ neighbor: CharClass) -> Bool {
        switch edge {
        case .kana: return neighbor == .kana
        case .latin, .digit: return neighbor == .latin || neighbor == .digit
        default: return false
        }
    }
}

/// 「改行」「段落」などの音声コマンド。文として単独で話されたときだけ改行にする（「改行コード」などは残す）。
enum SpokenCommands {
    private static let commands: [(String, String)] = [
        (#"(?:新しい段落|次の段落|段落|new paragraph|next paragraph)"#, "\n\n"),
        (#"(?:新しい行|次の行|改行|new line|next line|newline)"#, "\n"),
    ]

    static func apply(_ text: String) -> String {
        var t = text
        for (word, replacement) in commands {
            let pattern = #"(?:^|(?<=[。、，．！？.,!?\n]))[ \t　]*"# + word + #"[ \t　]*(?:[。、，．.,][ \t　]*|$|(?=\n))"#
            t = t.replacingOccurrences(of: pattern, with: replacement, options: [.regularExpression, .caseInsensitive])
        }
        // 改行の直前に残った読点と空白を消す
        return t.replacingOccurrences(of: #"[、，, \t]+\n"#, with: "\n", options: .regularExpression)
    }
}

/// AI 整形を使わない・使えないときの整形（フィラーの除去と表記の統一）
enum BasicCleaner {
    /// 単独で出てきたら必ずフィラーとみなす語
    private static let jaFillers = #"えーっと|えーと|えっと|ええと|あのー+|そのー+|うーん|うーむ|んー+"#
    /// 後ろに読点などが続くときだけフィラーとみなす語（「あの人」「まあまあ」は残す）
    private static let jaFillersBeforePunct = #"あの|その|まあ|なんか"#
    /// さらに文頭か句読点の後でだけフィラーとみなす語（「ねえー、」の「えー」は残す）
    private static let jaInterjections = #"えー+|あー+"#
    private static let enFillers = #",?\s*\b(?:u+m+|u+h+|e+r+m+|u+h+m+|h+m+)\b[,.]?(?=\s|$)"#
    private static let enStutterWords = "the|a|an|i|to|of|in|on|at|for|and|or|but|we|you|it|my|this|with|is|are|was"

    static func clean(_ text: String) -> String {
        var t = text
        let boundary = #"(?<=^|[。、！？!?\s「])"#
        t = t.replacingOccurrences(of: boundary + "(?:" + jaFillers + ")(?:ですね)?[、，,…\\s]*", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "(?:" + jaFillersBeforePunct + ")(?:ですね)?[、，,…]+\\s*", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: boundary + "(?:" + jaInterjections + ")(?:ですね)?[、，,。…]+\\s*", with: "", options: .regularExpression)
        // 話し始めの「で、」
        t = t.replacingOccurrences(of: #"(?<=^|[。！？\n])で、"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: enFillers, with: "", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: #"(?:^|(?<=[.!?]\s))you know,\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: #",\s*you know,"#, with: ",", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: "\\b(" + enStutterWords + ")(?:\\s+\\1\\b)+", with: "$1", options: [.regularExpression, .caseInsensitive])
        t = SpokenCommands.apply(t)
        t = TextNormalizer.normalize(t)
        t = t.replacingOccurrences(of: #"(?m)^[,.、。]+ *"#, with: "", options: .regularExpression)
        if let first = t.first, first.isLowercase, CharClass(first) == .latin {
            t = first.uppercased() + t.dropFirst()
        }
        return t
    }
}
