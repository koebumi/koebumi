import Foundation

/// 音声認識が漢数字で書いた数を算用数字にする（三時 → 3時、三千万 → 3000万、一日目 → 1日目、一点五倍 → 1.5倍）。
/// この Mac のモデル（Qwen3-ASR など）は漢数字で、Apple の音声認識は算用数字で書くので、どちらでも同じ表記にする。
/// 言い直し（「3時、いや4時」）や時刻の助詞の確認も、算用数字を前提にしている。
/// 「一緒」「一時的」「十分です」「三日月」「二三日」のような語は変えないよう、単位が続く数と、万・億を含む数だけを直す。
enum JapaneseNumbers {
    private static let digits: [Character: Int] = ["〇": 0, "一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
    private static let smallUnits: [Character: Int] = ["十": 10, "百": 100, "千": 1000]
    private static let largeUnits: [Character] = ["兆", "億", "万"]

    private static func isNumeral(_ c: Character) -> Bool {
        digits[c] != nil || smallUnits[c] != nil || largeUnits.contains(c)
    }

    /// 数の後ろに続く単位（長いものから並べる）
    private static let units = #"時間|時半|時|分|秒|日間|日|週間|週|[かヶカヵケ]月間?|月|年間|年生|年|歳|才|人|名|個|件|回|つ|枚|本|台|冊|匹|頭|羽|社|店|種類|階|番目|番線|番地|番手|番|号|位|点|度|倍|割|円|ドル|ユーロ|泊|連(?:休|勝|敗|覇|泊|続)|章|話|巻|行|列|組|着|周年|周|代|世紀|[かヶカ]国|[かヶカ]所|箇所|キロ|メートル|センチ|ミリ|グラム|トン|リットル|パーセント|ページ|ポイント|ギガ|メガ|テラ|バイト"#
    private static let unit = try! Regex("^(?:" + units + ")")
    /// 数と単位と句読点だけの文（三千万。三時。十二月二十日）
    private static let numbersOnly = try! Regex(#"(?:[〇一二三四五六七八九十百千万億兆]|"# + units + #"|[\s、。，．！？!?,.])+"#)

    /// 単位の後ろに続いてもよい漢字（3日目・3時間後・3人分・500円玉）。ほかの漢字が続くなら語の一部（三日月・六本木・一本化）
    private static let afterUnit: Set<Character> = ["目", "間", "半", "前", "後", "以", "程", "弱", "強", "超", "余", "頃", "過", "分", "当", "連", "毎", "玉",
                                                    "台", "末", "上", "下", "先", "内", "近", "未"]

    /// 前にあると語の一部になる漢字（統一・唯一・同一人物・数十人・何百回）
    private static let wordBefore: Set<Character> = ["統", "唯", "同", "単", "均", "画", "逐", "随", "択", "数", "何", "幾"]

    /// 単位が続いても変えない言い回し
    private static let idioms = try! Regex(
        #"二度と|一巻の終わり|ご一行|人一倍|一点一点|一つ一つ|一つひとつ|一人一人|一人ひとり|一人(?:で|っ子|ぼっち|きり)|十人十色|百人一首|三位一体|二人三脚|五分五分|九分九厘|八百万の神|四十九日|千歳|千代"#)

    static func arabize(_ text: String) -> String {
        guard text.contains(where: isNumeral) else { return text }
        // かなを含まない文は中国語かもしれない（快一点）ので、数と単位だけでできているときだけ直す
        guard text.contains(where: { CharClass($0) == .kana }) || text.wholeMatch(of: numbersOnly) != nil else { return text }
        let chars = Array(text)
        var protected = Set<Int>()
        for m in text.matches(of: idioms) {
            let start = text.distance(from: text.startIndex, to: m.range.lowerBound)
            protected.formUnion(start..<start + text[m.range].count)
        }

        var out = ""
        var i = 0
        while i < chars.count {
            guard isNumeral(chars[i]), i == 0 || !isNumeral(chars[i - 1]) else {
                out.append(chars[i])
                i += 1
                continue
            }
            var j = i
            while j < chars.count, isNumeral(chars[j]) { j += 1 }
            let run = Array(chars[i..<j])
            if !(i..<j).contains(where: protected.contains), let converted = convert(run, before: chars[..<i], after: chars[j...]) {
                out += converted.text
                i = j + converted.consumed
            } else {
                out += String(run)
                i = j
            }
        }
        return out
    }

    /// 数の並びを算用数字にした文字列と、後ろから続けて読んだ文字数（小数の「点五」）を返す。変えないなら nil
    private static func convert(_ run: [Character], before: ArraySlice<Character>, after: ArraySlice<Character>) -> (text: String, consumed: Int)? {
        guard let number = parse(run) else { return nil }
        if let last = before.last, wordBefore.contains(last) || CharClass(last) == .digit || CharClass(last) == .latin { return nil }
        let rest = String(after.prefix(8))

        guard let m = rest.prefixMatch(of: unit) else {
            // 単位がなくても数とわかる形（三千万、二十ぐらい、百二十。）。四十七士・八百屋のように漢字やカタカナが続くなら語の一部
            if run.contains(where: largeUnits.contains) { return (number, 0) }
            if run.count >= 2, after.first.map({ CharClass($0) != .han && !CharClass.isKatakana($0) }) ?? true { return (number, 0) }
            return nil
        }
        let unitText = String(rest[m.range])
        let tail = rest[m.range.upperBound...]
        let plain = !run.contains(where: largeUnits.contains)

        // 小数（三点五 → 3.5）
        if unitText == "点", plain, let fraction = tail.prefix(while: { digits[$0] != nil }).nonEmpty {
            return (number + "." + String(fraction.map { Character(String(digits[$0]!)) }), 1 + fraction.count)
        }
        // 分数（三分の一 → 3分の1）
        let numeratorRun = Array(tail.dropFirst().prefix(while: isNumeral))
        if unitText == "分", plain, tail.hasPrefix("の"), let numerator = parse(numeratorRun) {
            return (number + "分の" + numerator, 2 + numeratorRun.count)
        }
        if let next = tail.first, CharClass(next) == .han, !isNumeral(next), !afterUnit.contains(next), !tail.hasPrefix("中旬") { return nil }
        if unitText == "回", tail.hasPrefix("り") { return nil }  // 一回り
        if run == ["十"], unitText == "分" {
            // 「十分です」「十分に」は じゅうぶん。時刻と時間の長さのときだけ 10分 にする
            return before.last == "時" || ["後", "前", "間", "以", "程", "過", "ほど", "くらい", "ぐらい", "おき", "ごと"].contains(where: tail.hasPrefix) ? (number, 0) : nil
        }
        if run == ["一"] {
            switch unitText {
            case "時":  // 一時的・一時は（いちじ）と区別する
                let clock = ["午前", "午後", "朝", "夜", "夕方", "深夜", "明日", "今日", "昨日"].contains { String(before.suffix(2)).hasSuffix($0) }
                guard clock || ["に", "から", "まで", "頃", "ごろ", "過ぎ", "すぎ", "前", "台", "以降", "ちょうど"].contains(where: tail.hasPrefix) else { return nil }
            case "度": guard tail.hasPrefix("目") else { return nil }  // もう一度・一度も
            case "番", "代": return nil  // 一番好き・一代で
            case "円": if let b = before.last, CharClass(b) == .han, !"約計各全".contains(b) { return nil }  // 関東一円
            default: break
            }
        }
        return (number, 0)
    }

    /// 漢数字の並びを算用数字にする（三千万 → 3000万、二〇二六 → 2026、四十七 → 47）。数として読めなければ nil
    private static func parse(_ run: [Character]) -> String? {
        if run.allSatisfy({ digits[$0] != nil }) {
            if run.count == 1 { return String(digits[run[0]]!) }
            // 「二〇二六」のような位取りの書き方だけを数とみなす（「二三日」「七五三」「〇〇さん」は変えない）
            guard run.contains("〇"), run.contains(where: { $0 != "〇" }) else { return nil }
            return String(run.map { Character(String(digits[$0]!)) })
        }
        var out = ""
        var segment: [Character] = []
        var previous = -1  // 兆・億・万の順に小さくなる
        for c in run {
            if let rank = largeUnits.firstIndex(of: c) {
                guard rank > previous, let v = value(of: segment) else { return nil }
                out += "\(v)\(c)"
                previous = rank
                segment = []
            } else {
                segment.append(c)
            }
        }
        if !segment.isEmpty {
            guard let v = value(of: segment) else { return nil }
            out += "\(v)"
        }
        return out
    }

    /// 万より小さい部分（三千五百 → 3500）。「二三」のように数字が続く、「百千」のように位が逆になるものは nil
    private static func value(of segment: [Character]) -> Int? {
        var total = 0
        var digit: Int?
        var lastUnit = 10_000
        for c in segment {
            if let d = digits[c], d > 0 {
                guard digit == nil else { return nil }
                digit = d
            } else if let u = smallUnits[c], u < lastUnit {
                total += (digit ?? 1) * u
                digit = nil
                lastUnit = u
            } else {
                return nil
            }
        }
        total += digit ?? 0
        return total > 0 ? total : nil
    }
}

private extension Collection {
    var nonEmpty: Self? { isEmpty ? nil : self }
}
