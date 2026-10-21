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

    /// 1 か所だけ変わったとみなして差分を取る（共通の前方・後方を除いた部分）
    static func diff(_ a: [Character], _ b: [Character]) -> Edit? {
        guard a != b else { return nil }
        var p = 0
        while p < a.count, p < b.count, a[p] == b[p] { p += 1 }
        var ea = a.count, eb = b.count
        while ea > p, eb > p, a[ea - 1] == b[eb - 1] {
            ea -= 1
            eb -= 1
        }
        return Edit(a, b, old: p..<ea, new: p..<eb)
    }

    /// 変わった箇所をすべて取り出す。同じ語の中の変更（機会学修 → 機械学習）は 1 か所にまとめる。
    static func edits(_ a: [Character], _ b: [Character]) -> [Edit] {
        guard a != b else { return [] }
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in b.difference(from: a) {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        var spans: [(old: Range<Int>, new: Range<Int>)] = []
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
            if let last = spans.last, a[last.old.upperBound..<si].allSatisfy(isWordCharacter) {
                spans[spans.count - 1] = (last.old.lowerBound..<i, last.new.lowerBound..<j)
            } else {
                spans.append((si..<i, sj..<j))
            }
        }
        return spans.map { Edit(a, b, old: $0.old, new: $0.new) }
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
        guard !edit.old.isEmpty, !edit.new.isEmpty else { return nil }
        // 数を書き換えた（3時 → 4時、10 → 12）のは話した内容の修正なので、聞き取られ方として覚えない
        let isNumber: (String) -> Bool = { $0.contains(where: \.isNumber) && $0.allSatisfy { $0.isNumber || ",.:/-".contains($0) } }
        if isNumber(edit.old) && isNumber(edit.new) { return nil }
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

    /// 入力欄の今の内容を渡す
    mutating func observe(_ value: [Character]) -> Changes {
        guard !isFinished else { return Changes() }
        if value == last { return check() }
        return track(value) ? Changes() : finish(nil)
    }

    /// 見るのをやめる。読めた最後の内容で比べる
    mutating func finish(_ value: [Character]?) -> Changes {
        guard !isFinished else { return Changes() }
        if let value { _ = track(value) }
        isFinished = true
        return check()
    }

    /// 1 回の読み取りの間の変更から、入力したテキストの範囲を動かす
    private mutating func track(_ value: [Character]) -> Bool {
        guard let edit = CorrectionDetector.diff(last, value) else { return true }
        let delta = edit.newEnd - edit.oldEnd
        if edit.oldStart <= range.lowerBound, edit.oldEnd >= range.upperBound {
            // 入力したテキストを丸ごと消した（送信して入力欄が空になったときも）か、前後の文と一緒に書き換えた。直した語は覚えたままにする。
            // 入力したテキストだけを書き換えた（1 語だけ入力して、それを直した）ときは追い続ける
            guard edit.oldStart == range.lowerBound, edit.oldEnd == range.upperBound, edit.newEnd > edit.newStart else { return false }
            range = range.lowerBound..<(range.upperBound + delta)
        } else if edit.oldStart >= range.lowerBound, edit.oldEnd <= range.upperBound {
            // 範囲の中での変更。境目での書き足し（先頭・末尾の語を消して書き直した、続きを書いた）も中に含める
            range = range.lowerBound..<(range.upperBound + delta)
        } else if edit.oldEnd <= range.lowerBound {
            range = (range.lowerBound + delta)..<(range.upperBound + delta)
        } else if edit.oldStart < range.upperBound {
            return false
        }
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
        let value = element.flatMap { TextInserter.value(of: $0) }
        apply(tracker?.finish(value.map(Array.init)))
        end()
    }

    private func watch(_ inserted: String) -> Bool {
        guard let element = TextInserter.focusedElement(), let value = TextInserter.value(of: element) else { return false }
        let hay = Array(value)
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

    private func poll() {
        guard let element, tracker != nil else { return }
        let value = TextInserter.value(of: element).map(Array.init)
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
    }
}
