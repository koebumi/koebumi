import AppKit
import ApplicationServices

/// 入力欄のカーソル前後の文字列と、同じウィンドウに表示されている文字列。
/// 人名・用語の表記を画面に合わせることと、書きかけの文の続きとして自然につなぐことに使う。どこにも保存しない。
struct SurroundingText: Equatable, Sendable {
    /// 入力欄のカーソル（選択範囲）より前
    var before = ""
    /// 入力欄のカーソル（選択範囲）より後
    var after = ""
    /// 入力欄の外でウィンドウに表示されている文字列（入力欄に近いものを優先）
    var screen = ""

    static let maxBefore = 300
    static let maxAfter = 120
    static let maxScreen = 700

    var isEmpty: Bool { before.isEmpty && after.isEmpty && screen.isEmpty }

    /// 音声認識のヒントにする語（敬称の付いた人名・カタカナ語・英字の固有名詞）
    var terms: [String] { SurroundingTerms.extract([before, after, screen].joined(separator: "\n")) }
}

/// 画面の文脈をどこまで使うか
enum ContextAwareness: String, Codable, CaseIterable, Identifiable {
    case off, localOnly, always
    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return t("使わない", "Off")
        case .localOnly: return t("この Mac で処理するときだけ", "Only when processed on this Mac")
        case .always: return t("クラウドの AI にも送る", "Also send to cloud AI")
        }
    }
}

extension AppSettings {
    /// 文章の整形がこの Mac の中で終わるか（Apple オンデバイス・Ollama・localhost のサーバー）
    var llmRunsLocally: Bool {
        switch llmProvider {
        case .appleOnDevice, .none: return true
        case .claude: return false
        case .openAICompatible:
            return compatService == .ollama || Self.isLocalURL(compatBaseURL(compatService))
        }
    }

    /// 音声認識がこの Mac の中で終わるか
    var sttRunsLocally: Bool {
        sttProvider == .apple || sttProvider == .local || Self.isLocalURL(sttBaseURL(sttProvider))
    }

    /// 画面の文脈を AI 整形のプロンプトに入れてよいか
    var shareSurroundingWithLLM: Bool {
        contextAwareness == .always || (contextAwareness == .localOnly && llmRunsLocally)
    }

    /// 画面から拾った語を音声認識のヒントに渡してよいか
    var shareSurroundingWithSTT: Bool {
        contextAwareness == .always || (contextAwareness == .localOnly && sttRunsLocally)
    }

    static func isLocalURL(_ s: String) -> Bool {
        guard let host = URL(string: s)?.host()?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".local")
    }
}

// MARK: - 読み取り

/// アクセシビリティ API で、フォーカスのある入力欄とそのウィンドウの文字列を読む。
/// 応答の遅いアプリで録音開始を待たせないよう、1 回の問い合わせと全体の時間に上限を設ける。メインスレッド以外で呼ぶ。
enum SurroundingTextReader {
    private static let messagingTimeout: Float = 0.15
    private static let screenTimeBudget: TimeInterval = 0.3
    private static let maxNodes = 2500
    private static let maxDepth = 40
    /// 子をたどらない役割（メニューやボタンの文字は文脈にならない）。
    /// AXTabGroup は入れない（Safari などはページ全体がタブグループの中にある）
    private static let skippedRoles: Set<String> = [
        "AXMenuBar", "AXMenu", "AXMenuItem", "AXMenuButton", "AXButton", "AXPopUpButton", "AXScrollBar",
        "AXToolbar", "AXRadioButton", "AXCheckBox", "AXImage", "AXSecureTextField",
    ]

    /// pid: 入力先アプリ。システム全体の要素からは入力欄を取れないことがある（macOS 27 の CLI で -25204）ため、アプリから先に取る
    static func read(pid: pid_t?, includeScreen: Bool) -> SurroundingText? {
        var focused: AXUIElement?
        if let pid {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, messagingTimeout)
            focused = element(app, kAXFocusedUIElementAttribute)
        }
        if focused == nil {
            let system = AXUIElementCreateSystemWide()
            AXUIElementSetMessagingTimeout(system, messagingTimeout)
            focused = element(system, kAXFocusedUIElementAttribute)
        }
        guard let focused else { return nil }
        AXUIElementSetMessagingTimeout(focused, messagingTimeout)
        // パスワード欄は読まない
        if isSecure(focused) { return nil }

        var result = SurroundingText()
        if let (before, after) = cursorText(focused) {
            result.before = String(before.suffix(SurroundingText.maxBefore))
            result.after = String(after.prefix(SurroundingText.maxAfter))
        }
        if includeScreen, let window = element(focused, kAXWindowAttribute) ?? focusedWindow(of: focused) {
            result.screen = windowText(window, focused: focused)
        }
        return result.isEmpty ? nil : result
    }

    /// カーソル前後の文字列。長い文書でも全体を写さないよう、まずカーソル付近だけを取り出す。
    private static func cursorText(_ el: AXUIElement) -> (String, String)? {
        guard let range = selectedRange(el) else {
            return nil
        }
        let start = max(0, range.location - SurroundingText.maxBefore)
        let end = range.location + range.length + SurroundingText.maxAfter
        if let total = number(el, kAXNumberOfCharactersAttribute) {
            let upper = min(end, total)
            if let part = string(el, forRange: CFRange(location: start, length: upper - start)) {
                let ns = part as NSString
                let cut = min(range.location - start, ns.length)
                let selEnd = min(cut + range.length, ns.length)
                return (ns.substring(to: cut), ns.substring(from: selEnd))
            }
        }
        guard let value = stringValue(el) else { return nil }
        let ns = value as NSString
        let loc = min(range.location, ns.length)
        let selEnd = min(loc + range.length, ns.length)
        return (ns.substring(to: loc), ns.substring(from: selEnd))
    }

    /// ウィンドウ内の文字列を文書の順にたどり、入力欄より前（返信先のメールやチャットの流れ）を優先して集める
    private static func windowText(_ window: AXUIElement, focused: AXUIElement) -> String {
        var beforeFocus: [String] = []
        var afterFocus: [String] = []
        var passedFocus = false
        var nodes = 0
        let deadline = Date().addingTimeInterval(screenTimeBudget)

        func visit(_ el: AXUIElement, depth: Int) {
            guard nodes < maxNodes, depth < maxDepth, Date() < deadline else { return }
            nodes += 1
            AXUIElementSetMessagingTimeout(el, messagingTimeout)
            if CFEqual(el, focused) {
                passedFocus = true
                return
            }
            let role = string(el, kAXRoleAttribute) ?? ""
            if skippedRoles.contains(role) || isSecure(el) { return }
            if role == "AXStaticText" || role == "AXTextArea" || role == "AXTextField" {
                if let text = stringValue(el)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                    if passedFocus { afterFocus.append(text) } else { beforeFocus.append(text) }
                }
                if role != "AXStaticText" { return }
            }
            for child in children(el) { visit(child, depth: depth + 1) }
        }
        visit(window, depth: 0)

        let budget = SurroundingText.maxScreen
        var near = joinUnique(beforeFocus)
        if near.count > budget { near = String(near.suffix(budget)) }
        if near.count < budget / 2 {
            let rest = joinUnique(afterFocus)
            near += (near.isEmpty ? "" : "\n") + rest.prefix(budget - near.count)
        }
        return near.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 連続した同じ文字列（見出しとリンクの重複など）をまとめてつなぐ
    private static func joinUnique(_ parts: [String]) -> String {
        var out: [String] = []
        for p in parts where p != out.last { out.append(p) }
        return out.joined(separator: "\n")
    }

    // MARK: - AX の小さなヘルパー

    private static func isSecure(_ el: AXUIElement) -> Bool {
        string(el, kAXRoleAttribute) == "AXSecureTextField" || string(el, kAXSubroleAttribute) == "AXSecureTextField"
    }

    private static func focusedWindow(of el: AXUIElement) -> AXUIElement? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(el, &pid) == .success else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        return element(app, kAXFocusedWindowAttribute)
    }

    private static func element(_ el: AXUIElement, _ attr: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func children(_ el: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private static func string(_ el: AXUIElement, _ attr: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func stringValue(_ el: AXUIElement) -> String? { string(el, kAXValueAttribute) }

    private static func number(_ el: AXUIElement, _ attr: String) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.intValue
    }

    private static func selectedRange(_ el: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range), range.location >= 0 else { return nil }
        return range
    }

    private static func string(_ el: AXUIElement, forRange range: CFRange) -> String? {
        guard range.length > 0 else { return "" }
        var r = range
        guard let param = AXValueCreate(.cfRange, &r) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(el, kAXStringForRangeParameterizedAttribute as CFString, param, &value) == .success
        else { return nil }
        return value as? String
    }
}

// MARK: - 音声認識のヒント

enum SurroundingTerms {
    private static let patterns = [
        // 敬称の付いた人名（田中さん・佐藤様・鈴木部長）
        #"\p{Han}{1,4}(?=さん|様|さま|くん|君|ちゃん|氏|先生|部長|課長|社長|専務|常務)"#,
        // 姓と名を空白で区切った表示名（チャットの「渡邉 健太」）の姓と名
        #"(?<=^|\s)\p{Han}{1,4}(?=[ 　]\p{Han}{1,4}(?:\s|$))"#,
        #"(?<=\p{Han}[ 　])\p{Han}{1,4}(?=\s|$)"#,
        // 大文字で始まる語の並び（Claude Code, Google Docs）
        #"\b[A-Z][A-Za-z0-9]*(?:[ ][A-Z][A-Za-z0-9]*)+\b"#,
        // 大文字や数字を含む英字の語（iPhone, AWS, GPT-5）
        #"\b[A-Za-z][A-Za-z0-9]*[A-Z0-9][A-Za-z0-9-]*\b"#,
        // 大文字で始まる語（Claude, Slack）
        #"\b[A-Z][a-z]{2,}\b"#,
        // カタカナ語（サービス名・人名）
        #"[\p{Katakana}ー]{3,12}"#,
    ]
    private static let stopwords: Set<String> = [
        "The", "This", "That", "These", "Those", "And", "But", "For", "With", "You", "Your", "Our", "They", "Thanks", "Thank",
        "Hi", "Hello", "Dear", "Best", "Regards", "Please", "What", "When", "Where", "Why", "How", "Yes", "Not", "Are", "Was",
        "From", "Subject", "Date", "Sent", "Reply", "Forward", "Fwd",
    ]

    static func extract(_ text: String, limit: Int = 40) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p, options: [.anchorsMatchLines]) else { continue }
            for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let r = Range(m.range, in: text) else { continue }
                let term = String(text[r])
                let first = String(term.prefix { $0 != " " })
                guard term.count >= 2, !stopwords.contains(term), !stopwords.contains(first), seen.insert(term).inserted else { continue }
                // 「Claude Code」を拾ったら「Claude」「Code」は足さない
                if !term.contains(" "), out.contains(where: { $0.split(separator: " ").contains(Substring(term)) }) { continue }
                out.append(term)
                if out.count >= limit { return out }
            }
        }
        return out
    }
}

// MARK: - 人名の表記

/// 敬称（さん・様など）の前の名前を、読みが同じで画面に出ている表記に直す（渡辺さん → 渡邉さん、しょうじさん → 東海林さん）。
/// 読みは macOS の日本語解析で求める。画面に同じ読みの名前が複数あるときや、元の表記も画面にあるときは直さない。
enum ScreenNameFixer {
    private static let honorifics: Set<String> = [
        "さん", "様", "さま", "くん", "君", "ちゃん", "氏", "先生", "部長", "課長", "社長", "専務", "常務", "係長", "主任",
    ]

    struct Token {
        var surface: String
        var reading: String
        var range: NSRange
    }

    static func apply(_ text: String, reference: String) -> String {
        guard !reference.isEmpty, honorifics.contains(where: text.contains) else { return text }
        var exact: [String: Set<String>] = [:]
        var loose: [String: Set<String>] = [:]
        let onScreen = tokens(reference)
        for t in onScreen where isKanji(t.surface) && (2...4).contains(t.surface.count) {
            exact[t.reading.lowercased(), default: []].insert(t.surface)
            loose[looseKey(t.reading), default: []].insert(t.surface)
        }
        guard !exact.isEmpty else { return text }
        let surfaces = Set(onScreen.map(\.surface))

        let toks = tokens(text)
        var replacements: [(NSRange, String)] = []
        for i in toks.indices where i + 1 < toks.count && honorifics.contains(toks[i + 1].surface) {
            // 敬称の直前の語と、すぐ前に続く漢字の語（「渡辺健太さん」の姓）を見る
            var j = i
            while j >= 0, j >= i - 1 {
                let t = toks[j]
                if j < i, t.range.upperBound != toks[j + 1].range.location || !isKanji(t.surface) { break }
                if let target = match(t, exact: exact, loose: loose), !surfaces.contains(t.surface) {
                    replacements.append((t.range, target))
                }
                j -= 1
            }
        }
        let out = NSMutableString(string: text)
        for (range, target) in replacements.sorted(by: { $0.0.location > $1.0.location }) {
            out.replaceCharacters(in: range, with: target)
        }
        return out as String
    }

    private static func match(_ t: Token, exact: [String: Set<String>], loose: [String: Set<String>]) -> String? {
        let candidates: Set<String>?
        if isKanji(t.surface), t.surface.count >= 2 {
            candidates = exact[t.reading.lowercased()]
        } else if isHiragana(t.surface), t.surface.count >= 3 {
            candidates = exact[t.reading.lowercased()]
        } else if t.surface.allSatisfy({ $0.isASCII && $0.isLetter }), t.surface.count >= 3 {
            // ローマ字の名前（Shoji）は長音の書き方が揺れるので、長音を詰めて比べる
            candidates = loose[looseKey(t.reading)]
        } else {
            candidates = nil
        }
        guard let c = candidates, c.count == 1, let target = c.first, target != t.surface else { return nil }
        return target
    }

    static func tokens(_ s: String) -> [Token] {
        let cf = s as CFString
        let tokenizer = CFStringTokenizerCreate(nil, cf, CFRange(location: 0, length: CFStringGetLength(cf)),
                                                kCFStringTokenizerUnitWord, Locale(identifier: "ja") as CFLocale)
        var out: [Token] = []
        let ns = s as NSString
        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            let r = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let range = NSRange(location: r.location, length: r.length)
            let reading = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String ?? ""
            out.append(Token(surface: ns.substring(with: range), reading: reading, range: range))
        }
        return out
    }

    private static func looseKey(_ reading: String) -> String {
        var k = reading.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        for (long, short) in [("ou", "o"), ("oo", "o"), ("uu", "u"), ("aa", "a"), ("ii", "i"), ("ee", "e")] {
            k = k.replacingOccurrences(of: long, with: short)
        }
        return k
    }

    private static func isKanji(_ s: String) -> Bool { !s.isEmpty && s.allSatisfy { CharClass($0) == .han } }
    private static func isHiragana(_ s: String) -> Bool {
        !s.isEmpty && s.unicodeScalars.allSatisfy { (0x3041...0x309F).contains($0.value) }
    }
}

// MARK: - つなぎ方

/// 入力する文を、カーソル前後の文字列と自然につながるように整える（空白・文頭の大文字・重なった句読点）。AI を使わない。
enum ContextJoiner {
    /// 文の途中で小文字にしてよい語（固有名詞は変えない）
    private static let lowercasable: Set<String> = [
        "The", "A", "An", "And", "But", "So", "Or", "It", "This", "That", "These", "Those", "We", "You", "They",
        "He", "She", "There", "Then", "Also", "If", "When", "Because", "Which", "Who", "To", "In", "On", "At", "For", "With",
    ]

    static func join(_ text: String, before: String, after: String) -> String {
        var t = text
        guard t.first != nil else { return t }
        let prev = before.last
        let next = after.first

        // 書き出しが、カーソルの前にある最後の行（宛名など）と同じなら繰り返さない（「東海林様」の下に「東海林様、…」）
        if let line = before.split(whereSeparator: \.isNewline).last?.trimmingCharacters(in: .whitespaces),
           line.count >= 2, t.hasPrefix(line), let sep = t.dropFirst(line.count).first, "、,，\n ".contains(sep) {
            t = String(t.dropFirst(line.count + 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return text }
        }

        if let prev, !prev.isWhitespace {
            // 前が文の区切りなら、文頭の読点を消す（「です。」+「、それから」）
            if "。．！？、，".contains(prev), let first = t.first, "、，。．".contains(first) {
                t.removeFirst()
            }
            // 英語は前の語とのあいだに空白を入れる
            if isLatin(prev) || ".,!?;:)]}%".contains(prev), isLatin(t.first ?? " ") || "([{".contains(t.first ?? " ") {
                t = " " + t
            }
        }

        // 文の途中に入れるなら先頭を小文字に、文の頭なら大文字にする（英語）
        let trimmedBefore = before.trimmingCharacters(in: .whitespaces)
        if let p = trimmedBefore.last, !p.isNewline {
            let midSentence = isLatin(p) || p == ","
            t = recase(t, toLower: midSentence, toUpper: ".!?".contains(p))
        }

        if let next, !next.isWhitespace, let end = t.last {
            // 後ろが句点なら、入れる文の最後の句点を消す（「。。」にしない）
            if "。．".contains(next), "。．".contains(end) || next == "." && end == "." {
                t.removeLast()
            } else if CharClass(next).isCJK, "。．".contains(end), !(prev.map { "。．！？\n".contains($0) } ?? true) {
                // 日本語の文の途中に差し込むときは文末の「。」を付けない
                t.removeLast()
            } else if next.isLowercase, end == ".", prev.map(isLatin) == true {
                t.removeLast()
            }
            if let end = t.last, isLatin(next), isLatin(end) || ".,!?;:".contains(end) {
                t += " "
            }
        }
        return t
    }

    private static func recase(_ text: String, toLower: Bool, toUpper: Bool) -> String {
        let leading = text.prefix { $0 == " " }
        let body = text.dropFirst(leading.count)
        guard let c = body.first, CharClass(c) == .latin else { return text }
        if toUpper, c.isLowercase {
            return leading + c.uppercased() + body.dropFirst()
        }
        if toLower, c.isUppercase {
            let word = String(body.prefix { $0.isLetter })
            if lowercasable.contains(word) { return leading + word.lowercased() + body.dropFirst(word.count) }
        }
        return text
    }

    private static func isLatin(_ c: Character) -> Bool {
        let cls = CharClass(c)
        return cls == .latin || cls == .digit
    }
}
