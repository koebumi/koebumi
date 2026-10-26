import Foundation

/// 定型文（署名・挨拶など）。呼び出す言葉だけを 1 つの文として話すと、登録した文を AI に通さずにそのまま入力する
struct Snippet: Codable, Identifiable, Equatable {
    var id = UUID()
    /// 呼び出す言葉（署名）
    var trigger: String
    /// 入力する文。{宛名} と {挨拶} は返信先のメールに合わせて置き換える
    var text: String
}

/// 話した内容の最初と最後にある、呼び出す言葉だけの文を定型文にする（AI を使わない決まった処理）
enum SnippetExpander {
    static let addresseeToken = "{宛名}"
    static let greetingToken = "{挨拶}"
    /// 呼び出す言葉として比べる長さの上限（文字数）
    private static let maxTriggerLength = 30
    private static let delimiters: Set<Character> = ["。", "、", "，", "．", ",", ".", "!", "！", "?", "？", "\n", " ", "　", "\t"]

    struct Parts: Equatable {
        var leading: [Snippet] = []
        /// AI で整形する部分
        var body: String
        var trailing: [Snippet] = []

        var hasSnippets: Bool { !leading.isEmpty || !trailing.isEmpty }
    }

    /// 書き起こしの最初と最後から、呼び出す言葉だけを話した文を取り出す（「よろしくお願いします。署名」→ 本文と「署名」）。
    /// 文の中で使った語（「署名をお願いします」）は呼び出しとみなさない
    static func split(_ transcript: String, snippets: [Snippet]) -> Parts {
        var parts = Parts(body: transcript.trimmingCharacters(in: .whitespacesAndNewlines))
        let usable = snippets.filter { !key($0.trigger).isEmpty && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !usable.isEmpty else { return parts }
        while let (snippet, rest) = matchEnd(parts.body, usable) {
            parts.trailing.insert(snippet, at: 0)
            parts.body = rest
        }
        while let (snippet, rest) = matchStart(parts.body, usable) {
            parts.leading.append(snippet)
            parts.body = rest
        }
        return parts
    }

    /// 定型文の本文。宛名がわからないときは、{宛名} だけの行とその後の空行を書かない。{挨拶} は相手が社内なら「お疲れ様です。」
    static func render(_ snippet: Snippet, reply: MailReplyContext?) -> String {
        var lines: [String] = []
        var dropBlank = false
        for line in snippet.text.components(separatedBy: "\n") {
            let blank = line.trimmingCharacters(in: .whitespaces).isEmpty
            if line.contains(addresseeToken), reply?.addressee == nil,
               line.replacingOccurrences(of: addresseeToken, with: "").trimmingCharacters(in: .whitespaces).isEmpty {
                dropBlank = true
                continue
            }
            if dropBlank, blank { dropBlank = false; continue }
            dropBlank = false
            lines.append(line.replacingOccurrences(of: addresseeToken, with: reply?.addressee ?? "")
                .replacingOccurrences(of: greetingToken, with: (reply ?? MailReplyContext()).greeting))
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
    }

    /// 整形した本文と定型文を、1 行空けてつなぐ
    static func join(_ parts: Parts, body: String, reply: MailReplyContext?) -> String {
        (parts.leading.map { render($0, reply: reply) } + [body] + parts.trailing.map { render($0, reply: reply) })
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    /// 本文を整形するときのカーソル前後。定型文と接する側は、カーソル前後の代わりに定型文を見せる（本文は定型文と段落を分けて入れる）
    static func surrounding(_ s: SurroundingText?, around parts: Parts, reply: MailReplyContext?) -> SurroundingText? {
        guard var s else { return nil }
        if !parts.leading.isEmpty { s.before = parts.leading.map { render($0, reply: reply) }.joined(separator: "\n\n") + "\n\n" }
        if !parts.trailing.isEmpty { s.after = "\n\n" + parts.trailing.map { render($0, reply: reply) }.joined(separator: "\n\n") }
        return s
    }

    /// 定型文から入れるとき、カーソルの前の行に文があれば段落を分ける（「よろしくお願いいたします。」の後に「署名」）
    static func leadingBreak(_ parts: Parts, before: String?) -> String {
        guard !parts.leading.isEmpty || (parts.body.isEmpty && parts.hasSnippets),
              let last = before?.last, !last.isNewline else { return "" }
        return "\n\n"
    }

    /// 呼び出す言葉と、話した言葉が同じか。表記（署名・しょめい・ショメイ）が違っても、読みが同じなら同じとみなす
    static func matches(_ spoken: String, _ trigger: String) -> Bool {
        let a = key(spoken), b = key(trigger)
        if !a.isEmpty, a == b { return true }
        let ra = reading(spoken), rb = reading(trigger)
        return !ra.isEmpty && ra == rb
    }

    /// 比べるための表記（空白と記号を除き、カタカナはひらがなに、英字は小文字にする）
    private static func key(_ s: String) -> String {
        let hiragana = s.applyingTransform(.hiraganaToKatakana, reverse: true) ?? s
        return String(hiragana.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// 読みのローマ字（署名 → shomei）
    private static func reading(_ s: String) -> String {
        String(ScreenNameFixer.tokens(s).map { $0.reading.isEmpty ? $0.surface : $0.reading }.joined()
            .lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// 最後の文が呼び出す言葉なら、その定型文と残りを返す。区切りの後から始まる、いちばん長い一致を使う
    private static func matchEnd(_ text: String, _ snippets: [Snippet]) -> (Snippet, String)? {
        let chars = Array(text)
        var end = chars.count
        while end > 0, delimiters.contains(chars[end - 1]) { end -= 1 }
        guard end > 0 else { return nil }
        var best: (snippet: Snippet, start: Int)?
        var start = end - 1
        while start >= 0, end - start <= maxTriggerLength {
            if (start == 0 || delimiters.contains(chars[start - 1]) || endsSentence(chars[..<start])) && !delimiters.contains(chars[start]),
               let s = snippets.first(where: { matches(String(chars[start..<end]), $0.trigger) }) {
                best = (s, start)
            }
            start -= 1
        }
        guard let best else { return nil }
        // 「〜です、署名」の「、」と空白は残さない（「。」は文の終わりなので残す）
        var restEnd = best.start
        while restEnd > 0, " 　\t、，,\n".contains(chars[restEnd - 1]) { restEnd -= 1 }
        return (best.snippet, String(chars[..<restEnd]))
    }

    /// 丁寧語の文末で終わっているか。音声認識が句点を付けずに次の語を続けたとき（お願いします署名）も、ここで文が切れたとみなす
    private static func endsSentence(_ chars: ArraySlice<Character>) -> Bool {
        let tail = String(chars.suffix(4))
        return ["ます", "です", "ました", "でした", "ください", "ません", "ましょう"].contains { tail.hasSuffix($0) }
    }

    /// 最初の文が呼び出す言葉なら、その定型文と残りを返す
    private static func matchStart(_ text: String, _ snippets: [Snippet]) -> (Snippet, String)? {
        let chars = Array(text)
        var begin = 0
        while begin < chars.count, delimiters.contains(chars[begin]) { begin += 1 }
        guard begin < chars.count else { return nil }
        var best: (snippet: Snippet, end: Int)?
        var end = begin + 1
        while end <= chars.count, end - begin <= maxTriggerLength {
            if (end == chars.count || delimiters.contains(chars[end])) && !delimiters.contains(chars[end - 1]),
               let s = snippets.first(where: { matches(String(chars[begin..<end]), $0.trigger) }) {
                best = (s, end)
            }
            end += 1
        }
        guard let best else { return nil }
        var restStart = best.end
        while restStart < chars.count, delimiters.contains(chars[restStart]) { restStart += 1 }
        return (best.snippet, String(chars[restStart...]))
    }
}
