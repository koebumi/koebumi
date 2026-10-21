import AppKit
import ApplicationServices

/// 入力したテキストをユーザーが直したかを判定する純粋なロジック（辞書の自動追加用）
enum CorrectionDetector {
    struct Edit: Equatable {
        var start: Int  // 変更前テキスト上の開始位置
        var oldEnd: Int
        var newEnd: Int  // 変更後テキスト上の終了位置
        var old: String
        var new: String
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
        return Edit(start: p, oldEnd: ea, newEnd: eb, old: String(a[p..<ea]), new: String(b[p..<eb]))
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
    static func learnedTerm(before: [Character], after: [Character], edit: Edit) -> (term: String, replaced: String)? {
        guard !edit.old.isEmpty, !edit.new.isEmpty else { return nil }
        var s = edit.start
        var ea = edit.oldEnd
        var eb = edit.newEnd
        if let firstNew = after[safe: s], isWordCharacter(firstNew) {
            while s > 0, isWordCharacter(after[s - 1]) { s -= 1 }
        }
        if let lastNew = after[safe: eb - 1], isWordCharacter(lastNew) {
            while eb < after.count, isWordCharacter(after[eb]), ea < before.count {
                eb += 1
                ea += 1
            }
        }
        let term = String(after[s..<eb]).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let replaced = String(before[s..<ea]).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard term.count >= 2, term.count <= 40, !replaced.isEmpty, !term.contains("\n"), term != replaced else { return nil }

        let scripts = Set(term.map(script))
        if scripts.isSubset(of: [.hiragana, .other]) { return nil }  // 助詞や言い回しの修正は辞書に入れない
        // 語の途中にひらがなが入るなら文や言い回し（「英語は対応していない」）。先頭だけなら「お台場」のような語。
        if term.dropFirst().contains(where: { script($0) == .hiragana }) { return nil }
        if term.split(separator: " ").count > 3 { return nil }
        // 言い直しの修正は読みが近い（急 → キュー）か、カタカナを英字に直したもの（クロードコード → Claude Code）。
        // どちらでもなければ、入力した文を消して別の文を書いたとみなす。
        guard soundsAlike(term, replaced) || isKatakanaSpelledInLatin(replaced, term) else { return nil }

        if scripts.isSubset(of: [.latin, .other]) {
            // 大文字・数字を含む語（iPhone, GPT-5）か、普通の辞書にない語（kubectl）だけを登録する。
            // their → there のような言い換えは辞書に入れない。
            let hasCapsOrDigit = term.contains { $0.isUppercase || $0.isNumber }
            guard hasCapsOrDigit || !isDictionaryWord(term) else { return nil }
        }
        return (term, replaced)
    }

    /// 読み（ローマ字）が半分以上同じか。漢字とかなは macOS の日本語解析で読み、英字はそのまま比べる。
    static func soundsAlike(_ a: String, _ b: String) -> Bool {
        func key(_ s: String) -> [Character] {
            let reading = ScreenNameFixer.tokens(s).map { $0.surface.allSatisfy(\.isASCII) ? $0.surface : $0.reading }.joined()
            return Array(reading.lowercased().folding(options: .diacriticInsensitive, locale: nil).filter { $0.isLetter || $0.isNumber })
        }
        let ka = key(a), kb = key(b)
        guard !ka.isEmpty, !kb.isEmpty else { return false }
        return Double(levenshtein(ka, kb)) <= Double(max(ka.count, kb.count)) * 0.5
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
            if Array(hay[i..<i + needle.count]) == needle { return i..<i + needle.count }
            i -= 1
        }
        return nil
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

/// 入力した直後から 1 分間、入力欄の内容を見て、ユーザーが単語を直したら辞書に追加する。
/// 入力欄の内容はこの Mac の中でだけ比較し、どこにも送らない。
@MainActor
final class CorrectionWatcher {
    var onLearn: (_ term: String, _ replaced: String) -> Void = { _, _ in }

    private var element: AXUIElement?
    private var baseline: [Character] = []
    private var range: Range<Int> = 0..<0
    private var timer: Timer?
    private var startTask: Task<Void, Never>?
    private var deadline = Date()

    func start(inserted: String) {
        stop()
        startTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard let self, !Task.isCancelled,
                  let element = TextInserter.focusedElement(), let value = TextInserter.value(of: element) else { return }
            let hay = Array(value)
            guard let r = CorrectionDetector.lastRange(of: Array(inserted), in: hay) else { return }
            self.element = element
            self.baseline = hay
            self.range = r
            self.deadline = Date().addingTimeInterval(60)
            self.timer?.invalidate()
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.poll() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    func stop() {
        startTask?.cancel()
        startTask = nil
        if timer != nil { poll() }
        timer?.invalidate()
        timer = nil
        element = nil
    }

    private func poll() {
        guard let element, Date() < deadline, let value = TextInserter.value(of: element) else {
            timer?.invalidate()
            timer = nil
            return
        }
        let current = Array(value)
        guard let edit = CorrectionDetector.diff(baseline, current) else { return }
        let delta = edit.newEnd - edit.oldEnd
        if edit.oldEnd <= range.lowerBound {
            range = (range.lowerBound + delta)..<(range.upperBound + delta)
        } else if edit.start >= range.upperBound {
            // 入力したテキストより後ろでの変更（続きを書いている）
        } else if edit.start >= range.lowerBound, edit.oldEnd <= range.upperBound {
            if let learned = CorrectionDetector.learnedTerm(before: baseline, after: current, edit: edit) {
                onLearn(learned.term, learned.replaced)
            }
            range = range.lowerBound..<(range.upperBound + delta)
        } else {
            timer?.invalidate()
            timer = nil
            return
        }
        baseline = current
    }
}
