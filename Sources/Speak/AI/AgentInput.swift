import Foundation

/// 端末のエージェント（Claude Code・Codex）に話した内容のうち、送信とスラッシュコマンドを扱う。
/// どちらも AI を使わない決まった処理で、整形の前に行う。
enum AgentInput {
    // MARK: - 送信

    /// 最後に「送信」と言ったか。言っていたら、その語を除いた書き起こしを返す。
    /// 「データを送信」のように文の中で使った語は、命令とみなさない（直前が区切りか空白のときだけ）
    static func splitSubmit(_ raw: String) -> (text: String, submit: Bool) {
        // カタカナ語の最後の「ト」を、音声認識が助詞の「と」にすることがある（コンテクスト 送信 → コンテクスと送信）
        let raw = raw.replacingOccurrences(of: #"(?<=[ァ-ヺー])と(?=送信)"#, with: "ト ", options: .regularExpression)
        let pattern = #"(?<![^\s、。，．,.!！?？])(?:送信|そうしん|エンター|submit|press enter)[\s、。，．,.!！]*$"#
        guard let r = raw.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return (raw, false) }
        // 「直して、送信」の「、」は残さない（「。」は文の終わりなので残す）
        return (raw[..<r.lowerBound].trimmingCharacters(in: CharacterSet(charactersIn: " 　、，,")), true)
    }

    // MARK: - スラッシュコマンド

    /// 「スラッシュ コンパクト」のように、スラッシュコマンドだけを話したら「/compact」を返す。
    /// 知らないコマンドや、続けて別のことも話したときは nil（いつもどおり整形する）
    static func slashCommand(_ raw: String, commands: [String]) -> String? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        // 音声認識が「スラッシュ」を縮めて書くことがある（スラス・スラシュ）
        guard let prefix = text.range(of: #"^(?:スラッシュ(?:コマンド)?|スラッシ|スラシュ|スラス|slash(?:\s+command)?|/|／)[\s、，,]*"#,
                                      options: [.regularExpression, .caseInsensitive]) else { return nil }
        var spoken = text[prefix.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: " 　、。，．,.!！"))
        // 英語の名前の後に残った「と」は、カタカナ語の最後の「ト」（コンテクスト → Contextと）なので除く
        if let last = spoken.last, "とをでに".contains(last), spoken.dropLast().allSatisfy(\.isASCII) { spoken.removeLast() }
        guard !spoken.isEmpty else { return nil }
        if spoken.allSatisfy({ $0.isASCII }) {
            let key = latinKey(spoken)
            if let exact = commands.first(where: { names($0).contains { latinKey($0) == key } }) { return "/" + exact }
            // 音声認識が英語の名前を崩して書いたもの（grill me → Grealmi・Giri me）は、英語として読んだ音とローマ字として読んだ音で比べる。
            // 子音が 1 つだけの音（hogehoge → s）は、短いコマンド（usage）に一致しやすいので使わない
            let sounds = [Phonetic.key(english: spoken), Phonetic.key(romaji: key)].filter { $0.count >= 2 }
            return closest(romaji: key, sounds: sounds, vowels: Phonetic.vowels(english: spoken), commands: commands)
        }
        // 日本語で書いた名前は、読みのローマ字（読みやす → yomiyasu）と、英語の発音（コンパクト → compact）の近いほうで比べる
        let tokens = ScreenNameFixer.tokens(spoken)
        guard !tokens.isEmpty, tokens.allSatisfy({ !$0.reading.isEmpty || $0.surface.allSatisfy(\.isASCII) }) else { return nil }
        let romaji = latinKey(tokens.map { $0.reading.isEmpty ? $0.surface : $0.reading }.joined())
        return closest(romaji: romaji, sounds: [Phonetic.key(romaji: romaji)], vowels: Phonetic.vowels(romaji: romaji), commands: commands)
    }

    /// 音がいちばん近いコマンド。子音が 2 つまでの名前は子音の並びが同じものだけ、3 つなら濁点の有無の違い 1 つまで、
    /// それより長ければ違いが 4 分の 1 までのもの
    private static func closest(romaji: String, sounds: [[Character]], vowels: [Character], commands: [String]) -> String? {
        let sounds = sounds.filter { !$0.isEmpty }
        guard let shortest = sounds.map(\.count).min() else { return nil }
        let scored = commands.map { command -> (command: String, distance: Double, spelling: Double) in
            let spelling = names(command).map { Phonetic.ratio(Array(romaji), Array(latinKey($0))) }.min() ?? 1
            let sound = names(command).flatMap { name in
                let english = Phonetic.key(english: name.replacingOccurrences(of: "-", with: " "))
                return sounds.map { Phonetic.distance($0, english) }
            }.min() ?? 1
            return (command, min(spelling, sound), spelling)
        }
        let limit = shortest < 3 ? 0 : shortest == 3 ? 0.5 / 3 : 0.25
        guard let best = scored.map(\.distance).min(), best <= limit + 1e-9 else { return nil }
        // 子音が同じ（クリア → clear・color）なら母音の並びが近いほう。それも同じなら綴りが近いほう（グリルのみ → grill-me・grilling）。
        // ただし子音が 3 つまでの短い名前は、綴りでは決めない（声浪 koerou → clear・color は、どちらとも言えない）
        let ranked = scored.filter { $0.distance == best }.map { candidate in
            (candidate.command, Phonetic.ratio(vowels, Phonetic.vowels(english: candidate.command.replacingOccurrences(of: "-", with: " "))),
             shortest > 3 ? candidate.spelling : 0)
        }
        guard let top = ranked.min(by: { ($0.1, $0.2) < ($1.1, $1.2) }),
              ranked.filter({ $0.1 == top.1 && $0.2 == top.2 }).count == 1
        else { return nil }
        return "/" + top.0
    }

    /// コマンドの呼び方。複数形のコマンドは単数でも呼べる（ワークフロー → workflows）
    private static func names(_ command: String) -> [String] {
        command.count > 3 && command.hasSuffix("s") ? [command, String(command.dropLast())] : [command]
    }

    /// 小文字の英字と数字だけにする（読みの長音の記号も外す: kopī → kopi）
    private static func latinKey(_ s: String) -> String {
        String(s.lowercased().folding(options: .diacriticInsensitive, locale: nil).filter { $0.isLetter || $0.isNumber })
    }
}

/// カタカナで書いた語と英語の綴りを、子音の並びで比べる（コンパクト・compact はどちらも k m p k t）。
/// 英語は発音の決まり（語末の er を読まない、ge・gi は濁った音など）で、カタカナはローマ字にしてから子音を取り出す
enum Phonetic {
    static func key(katakana: String) -> [Character] { key(romaji: romaji(katakana: katakana)) }

    static func romaji(katakana: String) -> String {
        let latin = katakana.filter { $0 != "・" && !$0.isWhitespace }.applyingTransform(.toLatin, reverse: false) ?? ""
        return latin.folding(options: .diacriticInsensitive, locale: nil).lowercased().filter(\.isLetter)
    }

    static func key(romaji: String) -> [Character] {
        // ン の後の p・b・m は m（コンパクト konpakuto → kompakuto）
        consonants(romaji.lowercased().replacingOccurrences(of: #"n(?=[pbm])"#, with: "m", options: .regularExpression))
    }

    /// 母音の並び（子音が同じ語を見分ける）。英語の y は i として数え、続いた同じ母音はまとめる
    static func vowels(romaji: String) -> [Character] { vowelSequence(romaji.lowercased()) }
    static func vowels(english: String) -> [Character] { vowelSequence(english.lowercased().replacingOccurrences(of: "y", with: "i")) }

    private static func vowelSequence(_ s: String) -> [Character] {
        var out: [Character] = []
        for c in s where "aeiou".contains(c) && out.last != c { out.append(c) }
        return out
    }

    static func key(english: String) -> [Character] {
        var s = english.lowercased().filter { $0.isLetter || $0 == " " }
        let rules: [(String, String)] = [
            (#"tion|sion"#, "syon"), (#"c(?=[eiy])"#, "s"), (#"g(?=[eiy])"#, "j"),
            // 母音の後の r は、次が母音でなければ読まない（recorder → レコーダー、clear → クリア）
            (#"(?<=[aeiou])r+(?![aeiouy])"#, ""),
        ]
        for (pattern, replacement) in rules {
            s = s.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return consonants(s.filter(\.isLetter))
    }

    /// 子音だけを残す。両方に共通の言い換え（sh → s、l → r、v → b など）をしてから、母音と h・w・y を除き、続いた同じ音をまとめる
    private static func consonants(_ s: String) -> [Character] {
        var s = s
        // ch は k と分けるため、大文字の C にしておく
        for (a, b) in [("tch", "C"), ("ch", "C"), ("sh", "s"), ("ph", "f"), ("th", "s"), ("ck", "k"), ("qu", "kw"), ("x", "ks")] {
            s = s.replacingOccurrences(of: a, with: b)
        }
        let map: [Character: Character] = ["l": "r", "v": "b", "z": "s", "j": "s", "c": "k", "q": "k"]
        var out: [Character] = []
        for c in s {
            guard !"aeiouhwy".contains(c) else { continue }
            let m = map[c] ?? c
            if out.last != m { out.append(m) }
        }
        return out
    }

    /// 子音の並びの違いの割合。0 なら同じ音。濁点の有無の違い（k と g、t と d、p と b）は半分と数える（グリルミー → クリーム）。
    /// 最初の子音が違えば別の語とみなす（say lang → seiran は近いが、grilling ではない）
    static func distance(_ a: [Character], _ b: [Character]) -> Double {
        guard let first = a.first, let other = b.first, first == other || voicingPairs.contains([first, other]) else { return 1 }
        var row = (0...b.count).map(Double.init)
        for (i, x) in a.enumerated() {
            var diagonal = row[0]
            row[0] = Double(i + 1)
            for (j, y) in b.enumerated() {
                let cost = x == y ? 0 : voicingPairs.contains([x, y]) ? 0.5 : 1
                (diagonal, row[j + 1]) = (row[j + 1], min(row[j + 1] + 1, row[j] + 1, diagonal + cost))
            }
        }
        return row[b.count] / Double(max(a.count, b.count))
    }

    private static let voicingPairs: Set<[Character]> = [["k", "g"], ["g", "k"], ["t", "d"], ["d", "t"], ["p", "b"], ["b", "p"]]

    /// 文字の違いの割合（編集距離を長いほうの長さで割る）
    static func ratio(_ a: [Character], _ b: [Character]) -> Double {
        guard max(a.count, b.count) > 0 else { return 0 }
        return Double(CorrectionDetector.levenshtein(a, b)) / Double(max(a.count, b.count))
    }
}
