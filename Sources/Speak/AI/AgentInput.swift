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
        guard let prefix = text.range(of: #"^(?:スラッシュ(?:コマンド)?|slash(?:\s+command)?|/|／)[\s、，,]*"#,
                                      options: [.regularExpression, .caseInsensitive]) else { return nil }
        var spoken = text[prefix.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: " 　、。，．,.!！"))
        // 英語の名前の後に残った「と」は、カタカナ語の最後の「ト」（コンテクスト → Contextと）なので除く
        if let last = spoken.last, "とをでに".contains(last), spoken.dropLast().allSatisfy(\.isASCII) { spoken.removeLast() }
        guard !spoken.isEmpty else { return nil }
        if spoken.allSatisfy({ $0.isASCII }) {
            let key = latinKey(spoken)
            return commands.first { command in names(command).contains { latinKey($0) == key } }.map { "/" + $0 }
        }
        // 日本語で書いた名前は、読みのローマ字（読みやす → yomiyasu）と、英語の発音（コンパクト → compact）の近いほうで比べる
        let tokens = ScreenNameFixer.tokens(spoken)
        guard !tokens.isEmpty, tokens.allSatisfy({ !$0.reading.isEmpty || $0.surface.allSatisfy(\.isASCII) }) else { return nil }
        let romaji = latinKey(tokens.map { $0.reading.isEmpty ? $0.surface : $0.reading }.joined())
        let sound = Phonetic.key(romaji: romaji)
        guard !sound.isEmpty else { return nil }
        let scored = commands.map { command -> (String, Double) in
            let distances = names(command).map { name in
                min(Phonetic.ratio(Array(romaji), Array(latinKey(name))),
                    Phonetic.distance(sound, Phonetic.key(english: name.replacingOccurrences(of: "-", with: " "))))
            }
            return (command, distances.min() ?? 1)
        }
        guard let best = scored.map(\.1).min(), best <= (sound.count <= 3 ? 0 : 0.25) else { return nil }
        // 子音が同じ（クリア → clear・color）なら、母音の並びが近いほう
        let tied = scored.filter { $0.1 == best }.map(\.0)
        let vowels = Phonetic.vowels(romaji: romaji)
        let ranked = tied.map { ($0, Phonetic.ratio(vowels, Phonetic.vowels(english: $0.replacingOccurrences(of: "-", with: " ")))) }
        guard let top = ranked.map(\.1).min(), ranked.filter({ $0.1 == top }).count == 1, let pick = ranked.first(where: { $0.1 == top })
        else { return nil }
        return "/" + pick.0
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

    /// 違いの割合。0 なら同じ音
    static func distance(_ a: [Character], _ b: [Character]) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 1 }
        return ratio(a, b)
    }

    /// 文字の違いの割合（編集距離を長いほうの長さで割る）
    static func ratio(_ a: [Character], _ b: [Character]) -> Double {
        guard max(a.count, b.count) > 0 else { return 0 }
        return Double(CorrectionDetector.levenshtein(a, b)) / Double(max(a.count, b.count))
    }
}
