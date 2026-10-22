import Foundation

/// エージェントへの指示で話したファイル名を、作業フォルダにある実際の表記に直す。AI で整形する前に、音の近さで決める。
///   エージェントインプットを直して → AgentInput を直して
///   パッケージドットスウィフト → Package.swift、リードミーファイル → README ファイル
///   アット エージェントインプット → @Sources/Koebumi/AI/AgentInput.swift（Claude Code でファイルを添付する形）
///   agent input（音声認識が英字で分けて書いた）→ AgentInput
enum FileNameFixer {
    struct Result: Equatable {
        var text: String
        /// 直した名前（整形の AI に、この表記を変えないよう渡す）
        var names: [String] = []
    }

    /// 名前を集めたファイル。stem は拡張子を除いた名前、sound は英語として読んだ子音の並び
    private struct Entry {
        var path: String
        var name: String
        var stem: String
        var ext: String
        var sound: [Character]
        var vowels: [Character]
        /// 2 語以上をつないだ名前（AgentInput・build-app）。1 語の名前（Package・README）は、ふつうの言葉と見分けられないので、
        /// 拡張子や「ファイル」を付けて話したときだけ直す
        var isCompound: Bool
    }

    static func fix(_ text: String, files: ProjectFiles) -> Result {
        let entries = Self.entries(files.paths)
        guard !entries.isEmpty else { return Result(text: text) }
        var result = Result(text: text)
        result = replacing(in: result, pattern: katakanaRun) { run in match(katakana: run, in: entries) }
        result = replacing(in: result, pattern: latinRun) { run in match(latin: run, in: entries) }
        return result
    }

    /// 音声認識のヒントにする名前。変更中のファイルを先にし、2 語以上の名前だけを渡す（1 語の名前はふつうの言葉と同じなので要らない）
    static func hints(_ files: ProjectFiles, limit: Int = 30) -> [String] {
        let changed = Set(files.changed)
        let entries = Self.entries(files.changed + files.paths.filter { !changed.contains($0) })
        return Array(AgentWorkspace.unique(entries.filter(\.isCompound).map(\.stem)).prefix(limit))
    }

    // MARK: - 名前

    private static func entries(_ paths: [String]) -> [Entry] {
        paths.compactMap { path in
            let name = (path as NSString).lastPathComponent
            let ext = (name as NSString).pathExtension
            let stem = ext.isEmpty ? name : String(name.dropLast(ext.count + 1))
            let words = Self.words(stem)
            guard !words.isEmpty else { return nil }
            let english = words.joined(separator: " ")
            return Entry(path: path, name: name, stem: stem, ext: ext.lowercased(), sound: Phonetic.key(english: english),
                         vowels: Phonetic.vowels(english: english), isCompound: words.count >= 2)
        }
    }

    /// 名前を語に分ける（AgentInputTests → agent input tests、README → readme、build-app → build app）
    private static func words(_ stem: String) -> [String] {
        stem.matches(of: wordPattern).map { stem[$0.range].lowercased() }
    }

    private static let wordPattern = try! Regex(#"[A-Z]+(?![a-z])|[A-Z]?[a-z]+"#)

    // MARK: - カタカナで話した名前

    /// カタカナの語（音声認識が空白や「・」で区切ったものもつなぐ）
    private static let katakanaRun = try! Regex(#"[ァ-ヺー]+(?:[ 　・][ァ-ヺー]+)*"#)

    private static func match(katakana run: String, in entries: [Entry]) -> String? {
        var spoken = run.filter { $0 != " " && $0 != "　" && $0 != "・" }
        // 「アット」で始めたら、Claude Code でファイルを添付する形（@パス）にする
        let mention = spoken.hasPrefix("アット")
        if mention { spoken.removeFirst(3) }
        // 「リードミーファイル」の「ファイル」は残す
        let fileWord = spoken.hasSuffix("ファイル") && spoken.count > 4
        if fileWord { spoken.removeLast(4) }
        var ext: String?
        if let dot = spoken.range(of: "ドット", options: .backwards) {
            ext = String(spoken[dot.upperBound...])
            spoken = String(spoken[..<dot.lowerBound])
        }
        guard !spoken.isEmpty else { return nil }
        let strong = mention || fileWord || ext != nil
        var candidates = entries.filter { strong || $0.isCompound }
        if let ext {
            candidates = candidates.filter { extensionMatches(spoken: ext, $0.ext) }
            guard !candidates.isEmpty else { return nil }
        }
        let key = Phonetic.key(romaji: Phonetic.romaji(katakana: spoken))
        // ふつうの言葉と取り違えないよう、拡張子などを付けずに話した名前は子音が 3 つ以上のものだけ（メインビュー → MainView）
        guard key.count >= (strong ? 2 : 3) else { return nil }
        guard let best = closest(key: key, vowels: Phonetic.vowels(romaji: Phonetic.romaji(katakana: spoken)), in: candidates) else { return nil }
        if mention {
            // 同じ名前のファイルがいくつもあれば、いちばん浅いもの（README.md と docs/README.md なら README.md）。同じ深さなら決めない
            let depth = { (entry: Entry) in entry.path.split(separator: "/").count }
            let shallowest = best.filter { depth($0) == best.map(depth).min() }
            return shallowest.count == 1 ? "@" + shallowest[0].path : nil
        }
        return ext != nil ? best[0].name : best[0].stem + (fileWord ? " ファイル" : "")
    }

    /// 音がいちばん近い名前。同じ名前のファイルが別のフォルダにあれば、すべて返す。名前が違うのに同じくらい近ければ nil。
    /// 子音が 3 つまでなら同じ並びのもの（濁点の違いは 3 つで 1 つまで）、それより長ければ違いが 4 分の 1 までのもの
    private static func closest(key: [Character], vowels: [Character], in entries: [Entry]) -> [Entry]? {
        let limit = key.count < 3 ? 0 : key.count == 3 ? 0.5 / 3 : 0.25
        let scored = entries.map { ($0, Phonetic.distance(key, $0.sound)) }.filter { $0.1 <= limit + 1e-9 }
        guard let best = scored.map(\.1).min() else { return nil }
        let nearest = scored.filter { $0.1 == best }.map(\.0)
        // 子音が同じなら母音の並びが近いほう
        let ranked = nearest.map { ($0, Phonetic.ratio(vowels, $0.vowels)) }
        guard let top = ranked.map(\.1).min() else { return nil }
        let winners = ranked.filter { $0.1 == top }.map(\.0)
        return Set(winners.map(\.stem)).count == 1 ? winners : nil
    }

    /// 話した拡張子（スウィフト・エムディー・json）が、ファイルの拡張子か
    private static func extensionMatches(spoken: String, _ ext: String) -> Bool {
        if spoken.lowercased() == ext { return true }
        if extensionReadings[ext]?.contains(spoken) == true { return true }
        // 語として読む拡張子（swift・json・toml）は音で比べる
        let key = Phonetic.key(romaji: Phonetic.romaji(katakana: spoken))
        return key.count >= 2 && key == Phonetic.key(english: ext)
    }

    /// 文字を 1 つずつ読む拡張子と、音で比べにくい拡張子の読み方
    private static let extensionReadings: [String: [String]] = [
        "md": ["エムディー", "エムディ", "マークダウン"], "py": ["パイ", "ピーワイ"], "ts": ["ティーエス"], "tsx": ["ティーエスエックス"],
        "js": ["ジェイエス", "ジェーエス"], "jsx": ["ジェイエスエックス"], "rs": ["アールエス"], "rb": ["アールビー"], "go": ["ゴー"],
        "txt": ["テキスト", "ティーエックスティー"], "yml": ["ヤムル", "ヤメル", "ワイエムエル"], "yaml": ["ヤムル", "ヤメル"],
        "sh": ["シェル", "エスエイチ"], "html": ["エイチティーエムエル"], "css": ["シーエスエス"], "kt": ["ケーティー"],
        "c": ["シー"], "h": ["エイチ"], "cpp": ["シーピーピー"], "sql": ["エスキューエル", "シークエル"], "json": ["ジェイソン", "ジェーソン"],
    ]

    // MARK: - 英字で話した名前

    /// 音声認識が英字で書いた語の並び（agent input、agent input.swift）
    private static let latinRun = try! Regex(#"[A-Za-z][A-Za-z0-9]*(?:[ ._-][A-Za-z0-9]+)*"#)

    /// 英字は綴りが同じもの（大文字小文字と区切りだけが違う）だけを直す。2 語以上の名前だけ
    private static func match(latin run: String, in entries: [Entry]) -> String? {
        let key = lettersKey(run)
        if let entry = entries.first(where: { $0.isCompound && lettersKey($0.name) == key }) { return entry.name }
        return entries.first(where: { $0.isCompound && lettersKey($0.stem) == key })?.stem
    }

    private static func lettersKey(_ s: String) -> String { String(s.lowercased().filter { $0.isLetter || $0.isNumber }) }

    // MARK: - 置き換え

    /// pattern に合う部分を、replacement が返した表記に置き換える。英字の並びは、文の中の数語だけが名前のこともあるので、
    /// 長い並びから順に部分も試す
    private static func replacing(in result: Result, pattern: Regex<AnyRegexOutput>, _ replacement: (String) -> String?) -> Result {
        var text = "", names = result.names
        var cursor = result.text.startIndex
        for m in result.text.matches(of: pattern) {
            text += result.text[cursor..<m.range.lowerBound]
            cursor = m.range.upperBound
            let run = String(result.text[m.range])
            if let name = replacement(run) {
                text += name
                if name != run { names.append(name.replacingOccurrences(of: " ファイル", with: "")) }
                continue
            }
            // 「fix the agent input please」の「agent input」、「テスト エージェントインプット」の「エージェントインプット」
            var pieces = run.split(whereSeparator: { $0 == " " || $0 == "　" }).map(String.init)
            var start = 0
            while start < pieces.count {
                let found = stride(from: min(pieces.count - start, 4), through: 1, by: -1).lazy.compactMap { length -> (Int, String)? in
                    let part = pieces[start..<(start + length)].joined(separator: " ")
                    guard length < pieces.count, let name = replacement(part), name != part else { return nil }
                    return (length, name)
                }.first
                if let (length, name) = found {
                    pieces.replaceSubrange(start..<(start + length), with: [name])
                    names.append(name)
                }
                start += 1
            }
            text += pieces.joined(separator: " ")
        }
        text += result.text[cursor...]
        return Result(text: text, names: AgentWorkspace.unique(names))
    }
}
