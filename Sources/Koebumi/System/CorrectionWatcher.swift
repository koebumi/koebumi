import AppKit
import ApplicationServices

/// 入力したテキストをユーザーが直したかを判定する純粋なロジック（辞書の自動追加用）
enum CorrectionDetector {
    struct Edit: Equatable {
        var oldStart: Int  // 変更前テキスト上の位置
        var oldEnd: Int
        var newStart: Int  // 変更後テキスト上の位置
        var newEnd: Int
        var old: String
        var new: String

        init(_ a: [Character], _ b: [Character], old: Range<Int>, new: Range<Int>) {
            oldStart = old.lowerBound
            oldEnd = old.upperBound
            newStart = new.lowerBound
            newEnd = new.upperBound
            self.old = String(a[old])
            self.new = String(b[new])
        }
    }

    /// 直された語（term）と、直される前の語（replaced）
    struct Learned: Equatable {
        var term: String
        var replaced: String
    }

    /// 変わった箇所をすべて取り出す。同じ語の中の変更（機会学修 → 機械学習）は 1 か所にまとめる。
    static func edits(_ a: [Character], _ b: [Character]) -> [Edit] {
        guard a != b else { return [] }
        var merged: [(old: Range<Int>, new: Range<Int>)] = []
        for span in spans(a, b) {
            if let last = merged.last, a[last.old.upperBound..<span.old.lowerBound].allSatisfy(isWordCharacter) {
                merged[merged.count - 1] = (last.old.lowerBound..<span.old.upperBound, last.new.lowerBound..<span.new.upperBound)
            } else {
                merged.append(span)
            }
        }
        return merged.map { Edit(a, b, old: $0.old, new: $0.new) }
    }

    /// 入力欄全体の変わった箇所の位置。端末の画面全体（1 万字ほど）を毎秒比べても重くならないよう、前後の同じ部分を除き、
    /// まだ長ければ行ごとに比べてから、変わった行の中を文字ごとに比べる。それでも長く変わった部分は、まとめて 1 か所の書き換えとする。
    static func changes(_ a: [Character], _ b: [Character]) -> [(old: Range<Int>, new: Range<Int>)] {
        var p = 0
        while p < a.count, p < b.count, a[p] == b[p] { p += 1 }
        var ea = a.count, eb = b.count
        while ea > p, eb > p, a[ea - 1] == b[eb - 1] {
            ea -= 1
            eb -= 1
        }
        guard p < ea || p < eb else { return [] }
        let midA = Array(a[p..<ea]), midB = Array(b[p..<eb])
        let shift = { (span: (old: Range<Int>, new: Range<Int>), da: Int, db: Int) in
            ((span.old.lowerBound + da)..<(span.old.upperBound + da), (span.new.lowerBound + db)..<(span.new.upperBound + db))
        }
        if midA.count + midB.count <= charDiffLimit {
            return spans(midA, midB).map { shift($0, p, p) }
        }
        let linesA = lines(midA), linesB = lines(midB)
        return spans(linesA.map(\.text), linesB.map(\.text)).flatMap { block -> [(old: Range<Int>, new: Range<Int>)] in
            // 端末の画面のように、同じ数の行が書き換わったときは行どうしを比べる（左右に並べた画面は、どの行にも別の画面の文字が入る）
            let pairs = block.old.count == block.new.count
                ? zip(block.old, block.new).map { (linesA[$0].range, linesB[$1].range) }
                : [(charRange(block.old, in: linesA, total: midA.count), charRange(block.new, in: linesB, total: midB.count))]
            return pairs.flatMap { old, new -> [(old: Range<Int>, new: Range<Int>)] in
                guard old.count + new.count <= charDiffLimit else { return [shift((old, new), p, p)] }
                return spans(Array(midA[old]), Array(midB[new])).map { shift($0, p + old.lowerBound, p + new.lowerBound) }
            }
        }
    }

    private static let charDiffLimit = 3000

    /// 改行で区切った行（改行を含む）
    private static func lines(_ chars: [Character]) -> [(range: Range<Int>, text: String)] {
        var result: [(range: Range<Int>, text: String)] = []
        var start = 0
        for (i, c) in chars.enumerated() where c == "\n" || i == chars.count - 1 {
            result.append((start..<(i + 1), String(chars[start...i])))
            start = i + 1
        }
        return result
    }

    /// 何行目から何行目までを、文字の位置の範囲にする（行がない位置なら、その前の行の終わり）
    private static func charRange(_ lineRange: Range<Int>, in lines: [(range: Range<Int>, text: String)], total: Int) -> Range<Int> {
        let start = lineRange.lowerBound < lines.count ? lines[lineRange.lowerBound].range.lowerBound : total
        let end = lineRange.isEmpty ? start : lines[lineRange.upperBound - 1].range.upperBound
        return start..<end
    }

    /// 変わった箇所の位置（変更前・変更後）。Myers の差分で取り、まとめない
    private static func spans<T: Equatable>(_ a: [T], _ b: [T]) -> [(old: Range<Int>, new: Range<Int>)] {
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in b.difference(from: a) {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        var result: [(old: Range<Int>, new: Range<Int>)] = []
        var i = 0, j = 0
        while i < a.count || j < b.count {
            guard removed.contains(i) || inserted.contains(j) else {
                i += 1
                j += 1
                continue
            }
            let si = i, sj = j
            while removed.contains(i) || inserted.contains(j) {
                if removed.contains(i) { i += 1 } else { j += 1 }
            }
            result.append((si..<i, sj..<j))
        }
        return result
    }

    /// 直された語をすべて取り出す（同じ組は 1 回だけ）
    static func learnedTerms(before: [Character], after: [Character]) -> [Learned] {
        var result: [Learned] = []
        for edit in edits(before, after) {
            if let learned = learnedTerm(before: before, after: after, edit: edit), !result.contains(learned) {
                result.append(learned)
            }
        }
        return result
    }

    private enum Script { case latin, katakana, kanji, hiragana, other }

    private static func script(_ c: Character) -> Script {
        guard let s = c.unicodeScalars.first else { return .other }
        switch s.value {
        case 0x30A0...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9F: return .katakana
        case 0x3040...0x309F: return .hiragana
        case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0xF900...0xFAFF: return .kanji
        default:
            if c.isLetter || c.isNumber || c == "-" || c == "_" || c == "." || c == "+" || c == "#" { return .latin }
            return .other
        }
    }

    /// 単語をつくる文字（英字・カタカナ・漢字）。「スレッド間」のように文字種が混ざっても 1 語として扱う。
    private static func isWordCharacter(_ c: Character) -> Bool {
        [.latin, .katakana, .kanji].contains(script(c))
    }

    /// 直された語を、単語をつくる文字が続く範囲まで広げて取り出す。
    /// 辞書に入れる価値がありそうなら返す（固有名詞・専門用語・表記の修正）。
    static func learnedTerm(before: [Character], after: [Character], edit: Edit) -> Learned? {
        if edit.old.isEmpty || edit.new.isEmpty {
            // 文字を足しただけ・消しただけの変更は、語の中のとき（Ghosty → Ghostty）だけ直しとみなす。
            // 語の後ろに書き足した・語を丸ごと消したのは、話した内容の修正
            guard let left = before[safe: edit.oldStart - 1], let right = before[safe: edit.oldEnd],
                  isWordCharacter(left), isWordCharacter(right) else { return nil }
        }
        // 数を書き換えた（3時 → 4時、10件 → 100件）のは話した内容の修正なので、聞き取られ方として覚えない
        let numberOnly: (String) -> Bool = { $0.allSatisfy { $0.isNumber || ",.:/-".contains($0) } }
        if numberOnly(edit.old), numberOnly(edit.new), (edit.old + edit.new).contains(where: \.isNumber) { return nil }
        // 変わっていない前後の文字は変更前と変更後で同じなので、両方を同じだけ広げる
        var sa = edit.oldStart, ea = edit.oldEnd
        var sb = edit.newStart, eb = edit.newEnd
        if let firstNew = after[safe: sb], isWordCharacter(firstNew) {
            while sb > 0, sa > 0, isWordCharacter(after[sb - 1]) {
                sb -= 1
                sa -= 1
            }
        }
        if let lastNew = after[safe: eb - 1], isWordCharacter(lastNew) {
            while eb < after.count, ea < before.count, isWordCharacter(after[eb]) {
                eb += 1
                ea += 1
            }
        }
        var term = String(after[sb..<eb]).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        var replaced = String(before[sa..<ea]).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard term.count >= 2, term.count <= 40, !replaced.isEmpty, !term.contains("\n"), term != replaced else { return nil }

        let scripts = Set(term.map(script))
        if scripts.isSubset(of: [.hiragana, .other]) { return nil }  // 助詞や言い回しの修正は辞書に入れない
        // 語の途中にひらがなが入るなら文や言い回し（「英語は対応していない」）。先頭だけなら「お台場」のような語。
        if term.dropFirst().contains(where: { script($0) == .hiragana }) { return nil }
        if term.split(separator: " ").count > 3 { return nil }
        // 言い直しの修正は読みが近い（急 → キュー）か、カタカナを英字に直したもの（クロードコード → Claude Code）。
        // どちらでもなければ、入力した文を消して別の文を書いたとみなす。
        if !isKatakanaSpelledInLatin(replaced, term) {
            guard let pair = misheardPair(term, replaced), pair.term.count >= 2 else { return nil }
            (term, replaced) = pair
        }

        if Set(term.map(script)).isSubset(of: [.latin, .other]) {
            // 大文字・数字を含む語（iPhone, GPT-5）か、普通の辞書にない語（kubectl）だけを登録する。
            // their → there のような言い換えは辞書に入れない。文頭で先頭だけ大文字の語（There）は小文字にして調べる。
            let atSentenceStart = after[..<sb].last(where: { $0 != " " && $0 != "\t" }).map { ".!?。！？\n".contains($0) } ?? true
            let word = atSentenceStart && !term.dropFirst().contains(where: \.isUppercase) ? term.lowercased() : term
            let hasCapsOrDigit = word.contains { $0.isUppercase || $0.isNumber }
            guard hasCapsOrDigit || !isDictionaryWord(word) else { return nil }
        }
        return Learned(term: term, replaced: replaced)
    }

    /// 聞き間違いを直した組を返す。読み（ローマ字）が半分以上同じでなければ nil。
    /// 名前を直すついでに前後の語も書き換えた（棚香さん → 田中部長、先日棚香 → 昨日田中）ときは、読みが近い部分（棚香 → 田中）だけを返す。
    /// 直した後の語を語の切れ目で切り、前か後ろを切り離して比べる。切り離すのは、別の語に書き換えた（さん → 部長）か、
    /// 語を書き足した（棚香 → 田中部長）ときだけ。読みが近いまま（トランスクライブ → transcribe）なら 1 語のままにする。
    /// 変わっていない語の隣を別の語に書き換えただけ（鈴木さん → 鈴木課長）なら nil。
    static func misheardPair(_ term: String, _ replaced: String) -> (term: String, replaced: String)? {
        let termCuts = cuts(term), replacedCuts = cuts(replaced, misheard: true)
        guard let wholeTerm = termCuts.last?.head, let wholeReplaced = replacedCuts.last?.head,
              let whole = distance(wholeTerm.key, wholeReplaced.key) else { return nil }
        var best = (term: term, replaced: replaced, distance: whole)
        for t in termCuts {
            for r in replacedCuts {
                // 前を残す組と、後ろを残す組
                for (keep, rest) in [((t.head, r.head), (t.tail, r.tail)), ((t.tail, r.tail), (t.head, r.head))] {
                    guard !keep.0.text.isEmpty, !keep.1.text.isEmpty, !rest.0.text.isEmpty else { continue }
                    let restDistance = distance(rest.0.key, rest.1.key) ?? 1
                    if keep.0.text == keep.1.text {
                        // さん → 様 も 0.5 になるので、ここだけ 0.5 ちょうどを別の語とみなす
                        if restDistance >= 0.5 { return nil }
                        continue
                    }
                    guard restDistance > 0.5, let d = distance(keep.0.key, keep.1.key), d < best.distance else { continue }
                    best = (keep.0.text, keep.1.text, d)
                }
            }
        }
        return best.distance <= 0.5 ? (best.term, best.replaced) : nil
    }

    /// 語の一部と、その読み（ローマ字。英字はそのまま）
    private struct Piece {
        var text: String
        var key: [Character]
    }

    /// 語の切れ目で前と後ろに分けたもの（丸ごと前・丸ごと後ろも含む）。
    /// 読みは語全体を解析したときのものを使う（「間」だけを読むと「スレッド間」の「かん」にならない）
    private static func cuts(_ s: String, misheard: Bool = false) -> [(head: Piece, tail: Piece)] {
        let ns = s as NSString
        let tokens = ScreenNameFixer.tokens(s)
        let keys = tokens.map { token in
            let reading = token.surface.allSatisfy(\.isASCII) ? token.surface : token.reading
            return Array(reading.lowercased().folding(options: .diacriticInsensitive, locale: nil).filter { $0.isLetter || $0.isNumber })
        }
        var inner = Array(1..<max(tokens.count, 1))
        if misheard {
            // 聞き間違えた語は切れ目がずれる（棚香さん → 棚・香・さん）。文字の種類が変わるところがあれば、そこだけで切る
            let scriptChanges = inner.filter { i in
                let at = String.Index(utf16Offset: tokens[i].range.location, in: s)
                return at > s.startIndex && script(s[s.index(before: at)]) != script(s[at])
            }
            if !scriptChanges.isEmpty { inner = scriptChanges }
        }
        return ([0] + inner + [tokens.count]).map { i in
            let point = i == tokens.count ? ns.length : i == 0 ? 0 : tokens[i].range.location
            return (Piece(text: ns.substring(to: point).trimmingCharacters(in: .whitespaces), key: Array(keys[..<i].joined())),
                    Piece(text: ns.substring(from: point).trimmingCharacters(in: .whitespaces), key: Array(keys[i...].joined())))
        }
    }

    /// 読みの違いの割合。0 なら同じ読み
    private static func distance(_ a: [Character], _ b: [Character]) -> Double? {
        guard !a.isEmpty, !b.isEmpty else { return nil }
        return Double(levenshtein(a, b)) / Double(max(a.count, b.count))
    }

    /// カタカナで書かれた語を英字の綴りに直したか（グロック → Groq）
    static func isKatakanaSpelledInLatin(_ before: String, _ after: String) -> Bool {
        let b = before.filter { !$0.isWhitespace && $0 != "・" }
        let a = after.filter { !$0.isWhitespace }
        return !b.isEmpty && !a.isEmpty && b.allSatisfy { script($0) == .katakana } && a.allSatisfy { script($0) == .latin }
    }

    static func isDictionaryWord(_ word: String) -> Bool {
        let checker = NSSpellChecker.shared
        return word.split(separator: " ").allSatisfy { part in
            checker.checkSpelling(of: String(part), startingAt: 0, language: "en", wrap: false,
                                  inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound
        }
    }

    static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        for i in 1...a.count {
            var cur = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return prev[b.count]
    }

    static func lastRange(of needle: [Character], in hay: [Character]) -> Range<Int>? {
        guard !needle.isEmpty, needle.count <= hay.count else { return nil }
        var i = hay.count - needle.count
        while i >= 0 {
            if hay[i..<i + needle.count].elementsEqual(needle) { return i..<i + needle.count }
            i -= 1
        }
        return nil
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

/// 端末（Ghostty など）の画面の一部。端末はアクセシビリティ API で画面全体を、どの行も同じ幅（表示上の桁数）の文字の並びとして渡してくる。
/// 左右に並べた画面は同じ行に混ざり、折り返した文は行ごとに分かれるので、入力したテキストがある画面だけを切り出し、
/// 折り返した行をつないだ文字列にしてから比べる。画面が上にずれても、切り出した中で行がずれるだけになる。
struct TerminalView: Equatable {
    /// 切り出す桁の範囲
    var columns: Range<Int>
    /// 文を折り返す幅。Claude Code は入力欄の右端を 2 桁空けて折り返す
    var wrapWidth: Int

    init(columns: Range<Int>, wrapWidth: Int? = nil) {
        self.columns = columns
        self.wrapWidth = wrapWidth ?? columns.count
    }

    /// 画面の文字列が端末の画面なら、入力したテキストがある画面を返す。
    /// 右端を何桁空けて折り返すかはアプリで違うので、入力したテキストが 1 つにつながる幅を探す。
    /// 英語は語の切れ目で折り返すので、近い幅でもつながることがある。画面の幅（シェル）、Claude Code の幅、ほかの幅の順に試す
    static func find(_ inserted: String, in value: String) -> TerminalView? {
        for pane in panes(in: value) ?? [] {
            for margin in [0, 2, 1, 3, 4] {
                let view = TerminalView(columns: pane.columns, wrapWidth: pane.columns.count - margin)
                if view.text(value).contains(inserted) { return view }
            }
        }
        return nil
    }

    /// 画面の文字列が端末の画面なら、左右に並べた画面を左から順に返す
    static func panes(in value: String) -> [TerminalView]? {
        let rows = value.components(separatedBy: "\n")
        let widths = Set(rows.map(displayWidth))
        guard rows.count >= 3, widths.count == 1, let width = widths.first, width >= 20 else { return nil }
        // 縦の線がほぼすべての行で同じ桁にあれば、画面の境目
        var lines: [Int: Int] = [:]
        for row in rows {
            var column = 0
            for c in row {
                if "│┃║▕▏|".contains(c) { lines[column, default: 0] += 1 }
                column += displayWidth(c)
            }
        }
        let borders = lines.filter { Double($0.value) >= Double(rows.count) * 0.9 }.keys.sorted()
        let edges = [-1] + borders + [width]
        return zip(edges, edges.dropFirst()).filter { $1 - $0 > 1 }.map { TerminalView(columns: ($0 + 1)..<$1) }
    }

    /// この画面の部分を行ごとに切り出す（行末の空白は除く）
    func rows(_ value: String) -> [String] {
        value.split(separator: "\n", omittingEmptySubsequences: false).map { row in
            var column = 0
            var cells = ""
            for c in row {
                let w = Self.displayWidth(c)
                if column >= columns.lowerBound, column + w <= columns.upperBound { cells.append(c) }
                column += w
            }
            while cells.last == " " { cells.removeLast() }
            return cells
        }
    }

    /// この画面の部分を切り出し、折り返した行をつなぐ
    func text(_ value: String) -> String {
        let width = wrapWidth
        // 右端を空けて折り返すのは端末でなくアプリ（Claude Code）で、英語は語の切れ目で折り返し、行末の空白を消す
        let wrapsWords = width < columns.count
        var out = ""
        var previousEnd: Int?
        for cells in rows(value) {
            let body = cells.drop { $0 == " " }
            let firstWord = body.prefix { $0 != " " }
            if let end = previousEnd, out.last.map(Self.isText) == true, body.contains(where: Self.isText) {
                if end == width, wrapsWords, out.last.map(Self.displayWidth) == 1, body.first.map(Self.displayWidth) == 1 {
                    // 英語の語が折り返す幅にちょうど収まり、次の語が次の行に移った
                    out += " " + body
                } else if end == width || end == width - 1 && body.first.map(Self.displayWidth) == 2 {
                    // 折り返す幅まで埋まっている（文字で折り返した。全角の文字が入らないと 1 桁空く）
                    out += body
                } else if end < width, end + 1 + Self.displayWidth(firstWord) > width {
                    // 次の語が入らなかった（語で折り返した）。折り返しで消えた空白を戻す
                    out += " " + body
                } else {
                    out += "\n" + cells
                }
            } else {
                out += previousEnd == nil ? cells : "\n" + cells
            }
            previousEnd = Self.displayWidth(cells)
        }
        return out
    }

    /// 罫線や空白だけの行はつながない
    private static func isText(_ c: Character) -> Bool { c.isLetter || c.isNumber || c.isPunctuation && !c.isASCII }

    static func displayWidth<S: StringProtocol>(_ s: S) -> Int { s.reduce(0) { $0 + displayWidth($1) } }

    /// 端末での表示幅（全角は 2 桁）
    static func displayWidth(_ c: Character) -> Int {
        guard let v = c.unicodeScalars.first?.value else { return 0 }
        switch v {
        case 0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xA000...0xA4CF,
             0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE4F, 0xFF00...0xFF60, 0xFFE0...0xFFE6,
             0x1F300...0x1F64F, 0x1F900...0x1F9FF, 0x20000...0x3FFFD:
            return 2
        default:
            return 1
        }
    }
}

/// 入力したテキストを入力欄の中で追い、直された語を取り出す（アクセシビリティ API から切り離した純粋なロジック）。
/// 直している途中（消しただけ・変換中のひらがな・打ちかけ）を拾わないよう、内容が前回から変わっていないときに、
/// 入力した直後のテキストと比べる。打ちかけで覚えた語は、同じ語をさらに直したら取り消す。
struct CorrectionTracker {
    struct Changes: Equatable {
        var learned: [CorrectionDetector.Learned] = []
        var forgotten: [CorrectionDetector.Learned] = []
    }

    private let original: [Character]
    /// 前回読んだ入力欄の内容と、その中で入力したテキストがある範囲
    private var last: [Character]
    private var range: Range<Int>
    private var checked: [Character]
    private var learned: [CorrectionDetector.Learned] = []
    private(set) var isFinished = false

    init(value: [Character], range: Range<Int>) {
        original = Array(value[range])
        last = value
        self.range = range
        checked = original
    }

    /// 入力欄の今の内容を渡す。入力したテキストの部分が前回から変わっていなければ、直し終えたとみなして比べる。
    /// 端末ではほかの画面やステータス行が書き換わり続けるので、入力欄全体が変わらなくなるのは待たない。
    mutating func observe(_ value: [Character]) -> Changes {
        guard !isFinished else { return Changes() }
        let previous = Array(last[range])
        if value != last, !track(value) { return finish(nil) }
        return Array(last[range]) == previous ? check() : Changes()
    }

    /// 見るのをやめる。読めた最後の内容で比べる
    mutating func finish(_ value: [Character]?) -> Changes {
        guard !isFinished else { return Changes() }
        if let value { _ = track(value) }
        isFinished = true
        return check()
    }

    /// 1 回の読み取りの間の変更から、入力したテキストの範囲を動かす。変わった箇所ごとに見るので、範囲の外が同時に変わっても追える
    private mutating func track(_ value: [Character]) -> Bool {
        var shift = 0, growth = 0
        for (old, new) in CorrectionDetector.changes(last, value) {
            let delta = new.count - old.count
            if old.lowerBound <= range.lowerBound, old.upperBound >= range.upperBound {
                // 入力したテキストを丸ごと消した（送信して入力欄が空になったときも）か、前後の文と一緒に書き換えた。直した語は覚えたままにする。
                // 入力したテキストだけを書き換えた（1 語だけ入力して、それを直した）ときは追い続ける
                guard old == range, !new.isEmpty else { return false }
                growth += delta
            } else if old.lowerBound >= range.lowerBound, old.upperBound <= range.upperBound {
                // 範囲の中での変更。境目での書き足し（先頭・末尾の語を消して書き直した、続きを書いた）も中に含める
                growth += delta
            } else if old.upperBound <= range.lowerBound {
                shift += delta
            } else if old.lowerBound < range.upperBound {
                return false
            }
        }
        range = (range.lowerBound + shift)..<(range.upperBound + shift + growth)
        last = value
        return true
    }

    private mutating func check() -> Changes {
        let text = Array(last[range])
        guard text != checked else { return Changes() }
        checked = text
        let now = CorrectionDetector.learnedTerms(before: original, after: text)
        // 覚えた語を取り消すのは、同じ語をさらに直したとき（打ちかけの Claude Co → Claude Code）と、元に戻したときだけ。
        // 直した後で文ごと消したときは、覚えたままにする。
        let forgotten = learned.filter { old in
            !now.contains(old) && (text == original || now.contains { $0.replaced == old.replaced })
        }
        let added = now.filter { !learned.contains($0) }
        learned = learned.filter { !forgotten.contains($0) } + added
        return Changes(learned: added, forgotten: forgotten)
    }
}

/// 入力した直後から 1 分間、入力欄の内容を見て、ユーザーが単語を直したら辞書に追加する。
/// 入力欄の内容はこの Mac の中でだけ比較し、どこにも送らない。
@MainActor
final class CorrectionWatcher {
    /// 辞書に入れる。辞書が変わったら true を返す（取り消すのは、ここで変えたものだけ）
    var onLearn: (_ term: String, _ replaced: String) -> Bool = { _, _ in false }
    var onForget: (_ term: String, _ replaced: String) -> Void = { _, _ in }

    private var element: AXUIElement?
    /// 端末なら、入力したテキストがある画面
    private var view: TerminalView?
    private var tracker: CorrectionTracker?
    private var added: [CorrectionDetector.Learned] = []
    private var timer: Timer?
    private var startTask: Task<Void, Never>?
    private var deadline = Date()

    func start(inserted: String) {
        stop()
        startTask = Task { @MainActor [weak self] in
            // 貼り付けた内容が入力欄に出るまで待つ（Electron 系のアプリは遅い）
            for wait in [700, 800, 1500] {
                try? await Task.sleep(for: .milliseconds(wait))
                guard !Task.isCancelled, let self else { return }
                if self.watch(inserted) { return }
            }
        }
    }

    func stop() {
        startTask?.cancel()
        startTask = nil
        guard tracker != nil else { return }
        apply(tracker?.finish(element.flatMap(read)))
        end()
    }

    private func watch(_ inserted: String) -> Bool {
        guard let element = TextInserter.focusedElement(), let value = TextInserter.value(of: element) else { return false }
        view = TerminalView.find(inserted, in: value)
        let hay = Array(view?.text(value) ?? value)
        guard let r = CorrectionDetector.lastRange(of: Array(inserted), in: hay) else { return false }
        // 応答しないアプリで、1 秒ごとの読み取りがメインスレッドを止めないようにする
        AXUIElementSetMessagingTimeout(element, 0.25)
        self.element = element
        tracker = CorrectionTracker(value: hay, range: r)
        added = []
        deadline = Date().addingTimeInterval(60)
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        return true
    }

    private func read(_ element: AXUIElement) -> [Character]? {
        TextInserter.value(of: element).map { Array(view?.text($0) ?? $0) }
    }

    private func poll() {
        guard let element, tracker != nil else { return }
        let value = read(element)
        if let value, Date() < deadline {
            apply(tracker?.observe(value))
            if tracker?.isFinished == true { end() }
        } else {
            apply(tracker?.finish(value))
            end()
        }
    }

    private func apply(_ changes: CorrectionTracker.Changes?) {
        guard let changes else { return }
        for l in changes.forgotten where added.contains(l) {
            onForget(l.term, l.replaced)
            added.removeAll { $0 == l }
        }
        for l in changes.learned where onLearn(l.term, l.replaced) {
            added.append(l)
        }
    }

    private func end() {
        timer?.invalidate()
        timer = nil
        tracker = nil
        element = nil
        view = nil
    }
}
