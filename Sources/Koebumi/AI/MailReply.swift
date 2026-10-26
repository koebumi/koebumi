import Foundation

/// 返信先のメール（画面に出ている受信メール）から読んだ、相手の名前と間柄。
/// この Mac の中で画面の文字から読む。宛名の敬称と書き出しの挨拶をそろえるのに使う。
struct MailReplyContext: Equatable {
    /// 相手の姓（差出人の表示名か、受信メールでの名乗り）
    var name: String?
    /// 相手の姓名（表示名が「東海林 太郎」なら「東海林太郎」）
    var fullName: String?
    /// 相手に付ける敬称（様・さん）
    var honorific = "様"
    /// 社外の相手か。受信メールの挨拶が「お世話になっております」なら true、「お疲れ様です」なら false、どちらもなければ nil
    var external: Bool?

    /// 宛名（東海林様）
    var addressee: String? { name.map { $0 + honorific } }
    /// 書き出しの挨拶。社内の相手には「お疲れ様です。」、それ以外は「お世話になっております。」
    var greeting: String { external == false ? "お疲れ様です。" : "お世話になっております。" }
}

/// 日本語のメールの宛名と挨拶を、返信先のメールに合わせる決まった処理（AI を使わない）
enum MailReply {
    private static let externalGreeting = #"(?:いつも|大変)?(?:お世話になっております|お世話になります|お世話様です)"#
    private static let internalGreeting = #"(?:お疲れ様|お疲れさま|おつかれさま)(?:です|でございます)"#
    private static let familyName = #"[\p{Han}々]{1,4}|[\p{Katakana}ー]{2,8}"#
    /// 差出人の表示名とアドレス（東海林 太郎 <shoji@example.co.jp>）。Gmail は名前とアドレスを別の行に出す
    private static let sender = #"(?m)^([^\n]*?)(?<![\p{Han}\p{Katakana}ー々])([\p{Han}々]{1,7}|[\p{Katakana}ー]{2,12})(?:[ 　]([\p{Han}\p{Hiragana}\p{Katakana}ー々]{1,8}))?[ 　]*\n?[ 　]*[<＜][^<>＜＞\s@]+@[^<>＜＞\s]+[>＞]"#
    /// 受信メールの書き出しの宛名の行（矢野様・矢野さん・株式会社ABC 矢野様）。返信する人の名前と、相手が使った敬称がわかる
    private static let opening = #"(?m)^[>\s　]*(?:[^\n]{0,30}[ 　])?("# + familyName + #")(?:[ 　]?(?:"# + familyName + #"))?[ 　]?(様|さま|さん|殿)[、,]?[ \t　]*$"#
    /// 挨拶の後の名乗り（株式会社ABC の東海林です）
    private static let introduction = "(?:" + externalGreeting + "|" + internalGreeting
        + #")[。．、！!\s　]*(?:[^。．\n、ごお][^。．\n]{0,29}?の)?([\p{Han}々]{2,4}|[\p{Katakana}ー]{2,8})(?:です|でございます|と申します)[。．]"#
    /// 行頭の名乗り（情報科学研究科　田中です。）。挨拶（こんにちは）より先に名乗るメールもある
    private static let lineIntroduction = #"(?m)^[>\s　]*(?:[^。．\n、ごお][^。．\n、]{0,29}?(?:の|[ 　]))?([\p{Han}々]{2,4}|[\p{Katakana}ー]{2,8})(?:です|でございます|と申します)[。．]"#

    /// 画面の文字から返信先を読む。Apple Mail は返信の引用を入力欄のカーソルより後に、Spark は作成欄の下に、Gmail はスレッドを入力欄より前に出す。
    /// カーソルや入力欄より後ろの文字は先頭（いちばん新しいメール）を、入力欄より前の文字は最後（入力欄に近い、いちばん新しいメール）を先に見る
    static func context(from s: SurroundingText) -> MailReplyContext? {
        let texts = [(s.after, true), (s.screenAfter, true), (s.screen, false)].filter { !$0.0.isEmpty }
        guard !texts.isEmpty else { return nil }
        func find(_ pattern: String) -> [String]? {
            texts.lazy.compactMap { allMatches(pattern, in: $0.0, newestFirst: $0.1).first }.first
        }

        var c = MailReplyContext()
        if let greeting = find(externalGreeting + "|" + internalGreeting)?[0] {
            c.external = greeting.range(of: internalGreeting, options: .regularExpression) == nil
        }
        // 受信メールの宛名は、返信する人（自分）の名前。差出人の候補から外す
        let opening = find(opening)
        let isMe = { (n: String) in opening.map { $0[1].hasPrefix(n) || n.hasPrefix($0[1]) } ?? false }
        if let honorific = opening?[2] {
            c.honorific = honorific == "さん" ? "さん" : "様"
        } else if c.external == false {
            c.honorific = "さん"
        }

        senders: for (text, newestFirst) in texts {
            for m in allMatches(sender, in: text, newestFirst: newestFirst) where !isMe(m[2]) {
                // 宛先・CC の行は、自分かほかの受信者
                if m[1].range(of: #"^\s*(?:To|Cc|CC|Bcc|BCC|宛先)\s*[:：]"#, options: .regularExpression) != nil { continue }
                c.name = m[2]
                c.fullName = m[3].isEmpty ? nil : m[2] + m[3]
                break senders
            }
        }
        if c.name == nil, let intro = [introduction, lineIntroduction].lazy.compactMap({ find($0)?[1] })
            .first(where: { name in !isMe(name) && texts.contains { signs($0.0, as: name) } }) {
            c.name = intro
        }
        if let full = c.name, c.fullName == nil, let family = family(of: full) {
            // 表示名が空白なしの姓名（東海林太郎）なら、姓だけを宛名に使う
            c.name = family
            c.fullName = full
        }
        return c.name == nil && c.external == nil ? nil : c
    }

    /// 書き出しの挨拶と、相手の名前の敬称を直す。話していない内容は足さない
    static func adjust(_ text: String, context c: MailReplyContext) -> String {
        guard text.contains(where: { CharClass($0) == .kana }) else { return text }
        var t = text
        if let external = c.external {
            t = replaceGreeting(t, from: external ? internalGreeting : externalGreeting, to: external ? "お世話になっております" : "お疲れ様です")
        }
        if c.honorific == "様", let name = c.name {
            // 社外の相手を「さん」と呼んだら「様」にする（「様」を「さん」には変えない）
            let names = [c.fullName, name].compactMap { $0 }.map(NSRegularExpression.escapedPattern)
            t = t.replacingOccurrences(of: "(" + names.joined(separator: "|") + ")(?:さん|さま)", with: "$1様", options: .regularExpression)
        }
        return t
    }

    /// 頼まれて書いた下書き（Ask anything）を返信先に合わせる。挨拶で始まり宛名がなければ、宛名の行を足す
    static func finishDraft(_ text: String, context c: MailReplyContext) -> String {
        let t = adjust(text, context: c)
        guard let addressee = c.addressee, let name = c.name, !t.contains(name),
              t.range(of: "^(?:" + externalGreeting + "|" + internalGreeting + ")", options: .regularExpression) != nil
        else { return t }
        return addressee + "\n\n" + t
    }

    /// 書き出し（最初の 3 行）の行頭か、同じ行の宛名の後ろにある挨拶を 1 つだけ置き換える
    private static func replaceGreeting(_ text: String, from pattern: String, to greeting: String) -> String {
        let re = try! NSRegularExpression(pattern: #"(?m)^([ \t　]*(?:[^\n、,。]{1,16}(?:様|さん|さま|各位|殿)[、,　 ]*)?)(?:"# + pattern + ")")
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              ns.substring(to: m.range.location).filter(\.isNewline).count < 3
        else { return text }
        return ns.replacingCharacters(in: m.range, with: ns.substring(with: m.range(at: 1)) + greeting)
    }

    /// 署名のように、名前で終わる行があるか（東海林 太郎・営業部 東海林）。名乗りに見えるだけの文（議事録です）を名前とみなさない
    private static func signs(_ text: String, as name: String) -> Bool {
        let n = NSRegularExpression.escapedPattern(for: name)
        return text.range(of: #"(?m)(?:^|[ 　])"# + n + #"(?:[ 　]?[\p{Han}\p{Hiragana}々]{1,4})?[ \t　]*$"#, options: .regularExpression) != nil
    }

    /// 空白のない姓名（東海林太郎）を、macOS の日本語解析で姓と名に分ける。分けられなければ nil
    private static func family(of full: String) -> String? {
        guard full.count >= 3, full.allSatisfy({ CharClass($0) == .han }) else { return nil }
        let tokens = ScreenNameFixer.tokens(full)
        guard tokens.count == 2 else { return nil }
        return tokens[0].surface
    }

    /// マッチごとの文字列（0 番が全体、続けてグループ）。newestFirst が false なら後ろのマッチから並べる
    private static func allMatches(_ pattern: String, in text: String, newestFirst: Bool) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        let found = re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
            (0..<m.numberOfRanges).map { i in m.range(at: i).location == NSNotFound ? "" : ns.substring(with: m.range(at: i)) }
        }
        return newestFirst ? found : found.reversed()
    }
}
