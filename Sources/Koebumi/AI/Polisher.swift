import Foundation

/// 認識結果から入力するテキストを作る。アプリと CLI（--polish）で同じ処理を通す。
/// 表記の統一と辞書の置き換え → AI 整形 → 出力の検証 → 表記の統一 → 日本語の表記ルール・チャットの句読点・画面の文脈に合わせる、の順に行う。
enum Polisher {
    /// CLI の --verbose: 使わなかった AI の出力を標準エラーに書く（開発用）
    nonisolated(unsafe) static var verbose = false

    struct Output: Equatable {
        var text: String
        /// AI 整形を諦めて簡易整形にしたときの理由（ユーザーに知らせる）
        var warning: String?
    }

    /// AI に渡す前の決まった下処理（Ask の質問にも使う）
    static func prepare(_ transcript: String, aliases: [String: String]) -> String {
        VocabularyReplacer.apply(TextNormalizer.normalize(SpokenCommands.apply(transcript)), aliases: aliases)
    }

    static func run(_ request: PolishRequest, engine: LLMEngine?) async throws -> Output {
        var request = request
        request.transcript = prepare(request.transcript, aliases: request.aliases)
        let cleaned = BasicCleaner.clean(request.transcript)
        // フィラーしか話していない（「えーと、あのー」）なら、AI に渡しても何も残らない
        guard !cleaned.isEmpty else { return Output(text: "") }
        let fallback = fit(cleaned, request)
        guard let engine else {
            if request.mode == .translate {
                throw LLMError.unavailable(t("翻訳には AI エンジンが必要です（設定 > AI エンジン）", "Translation needs an AI engine (Settings > AI engines)"))
            }
            return Output(text: fallback)
        }
        do {
            if request.mode == .translate {
                // フィラーは訳すと「Um,」などとして残るので、訳す前に取り除く
                request.transcript = cleaned
                // 小さいモデルは訳さずに元の言語のまま返すことがあるので、翻訳先の文字で書かれているか確かめて 1 回だけやり直す
                let target = request.targetLanguage ?? "en-US"
                for attempt in 0..<2 {
                    let text = finish(try await engine.polish(request), request)
                    if !text.isEmpty, Languages.isWritten(text, in: target) { return Output(text: fit(text, request)) }
                    NSLog("Koebumi: translation is not in \(target) (attempt \(attempt + 1))")
                    if verbose { FileHandle.standardError.write(Data("rejected: \(text)\n".utf8)) }
                }
                throw LLMError.unavailable(t("\(Languages.name(target)) に翻訳できませんでした。もう一度試すか、設定で別の AI エンジンを選んでください",
                                             "Could not translate into \(Languages.name(target)). Try again or choose another AI engine in Settings"))
            }
            // 小さいモデルは同じ入力でもまれに崩れるので、不自然な出力なら 1 回だけやり直す
            // メールと、フォーマルな口調を選んだときは、です・ます調にしてよい
            let mayBePolite = request.category == .email || request.styleDescription.contains("敬語") || request.styleDescription.contains("keigo")
            for attempt in 0..<2 {
                var text = finish(try await engine.polish(request), request)
                if !mayBePolite { text = OutputGuard.keepingCasualQuestions(source: request.transcript, output: text) }
                if OutputGuard.accepts(source: request.transcript, output: text, vocabulary: request.vocabulary, allowsRewording: request.allowsRewording),
                   OutputGuard.keepsCorrection(source: request.transcript, output: text),
                   OutputGuard.keepsQuantityParticles(source: request.transcript, output: text),
                   mayBePolite || OutputGuard.keepsRegister(source: request.transcript, output: text) {
                    return Output(text: fit(text, request))
                }
                // 質問に答えた・内容を落とした・言い直しを取り違えたなど、整形として不自然な出力は使わない
                NSLog("Koebumi: rejected AI output (attempt \(attempt + 1)). source=\(request.transcript.count) output=\(text.count)")
                if verbose { FileHandle.standardError.write(Data("rejected: \(text)\n".utf8)) }
            }
            return Output(text: fallback)
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            if request.mode == .translate { throw error }
            // 整形に失敗しても話した内容は失わない
            let warning = t("AI 整形に失敗したため認識結果を入力しました: ", "AI cleanup failed, inserted the transcript: ") + error.localizedDescription
            return Output(text: fallback, warning: warning)
        }
    }

    /// AI の出力の表記をそろえ、辞書の表記に直す
    private static func finish(_ polished: String, _ request: PolishRequest) -> String {
        let text = request.mode == .dictate ? BasicCleaner.removeFillers(polished) : polished
        return VocabularyReplacer.apply(ListTidier.tidy(TextNormalizer.normalize(text)), aliases: request.aliases)
    }

    /// 入力する直前に、日本語の表記ルール、チャットの句読点、画面に合わせた人名の表記、カーソル前後とのつなぎ方をそろえる
    static func fit(_ text: String, _ request: PolishRequest) -> String {
        var t = text
        // 文頭で大文字にされた名前（build-app → Build-app、iPhone → IPhone）を、辞書や作業フォルダの表記に戻す
        for term in request.vocabulary where term.first?.isLowercase == true {
            let capitalized = NSRegularExpression.escapedPattern(for: term.prefix(1).uppercased() + term.dropFirst())
            t = t.replacingOccurrences(of: "(?<![A-Za-z0-9])" + capitalized + "(?![A-Za-z0-9])", with: term, options: .regularExpression)
        }
        if let n = request.notation { t = JapaneseFormatter.apply(t, notation: n) }
        if request.category == .chat {
            let rule = request.mode == .translate ? request.chatPunctuation.forTranslation : request.chatPunctuation
            t = rule.apply(t)
        }
        if let s = request.surrounding {
            t = ScreenNameFixer.apply(t, reference: [s.screen, s.before, s.after].joined(separator: "\n"))
            t = ContextJoiner.join(t, before: s.before, after: s.after)
        }
        return t
    }
}

/// AI の整形結果が「話した内容をきれいにしたもの」になっているかを確かめる。
/// 小さいモデルは書き起こしの質問に答えたり、断ったり、大きく省いたりすることがあるため。
enum OutputGuard {
    private static let refusalMarkers = [
        "申し訳ありません", "申し訳ございません", "お手伝いできません", "対応できません", "AIとして", "AI として", "言語モデル",
        "I'm sorry", "I am sorry", "I can't help", "I cannot help", "I can't assist", "I cannot assist", "As an AI", "language model",
    ]

    /// allowsRewording: 言葉づかいを指定して言い換えさせるとき（敬語化など）は、文字の重なりが少なくても受け入れる
    static func accepts(source: String, output: String, vocabulary: [String] = [], allowsRewording: Bool = false) -> Bool {
        let s = letters(source)
        // 辞書の語（カタカナを英語表記に直したものなど）は、話した内容と文字が重ならなくても正しい
        var stripped = output
        for term in vocabulary.sorted(by: { $0.count > $1.count }) where !term.isEmpty {
            stripped = stripped.replacingOccurrences(of: term, with: " ", options: .caseInsensitive)
        }
        let o = letters(stripped)
        guard !letters(output).isEmpty else { return s.isEmpty }
        if s.isEmpty { return false }
        // 話していない内容を大量に足した（質問に答えた・続きを書いた）
        if o.count > s.count * 3 / 2 + 20 { return false }
        // 大部分を落とした（フィラーと言い直しを除いても 3 割未満）
        let cleaned = letters(BasicCleaner.clean(source))
        if cleaned.count >= 20, o.count * 10 < cleaned.count * 3 { return false }
        // 出力の大部分が、話した内容に出てこない文字の並びでできている（短い出力ほど厳しく見る）
        if o.count >= 4, overlap(o, s) < (allowsRewording ? 0.12 : o.count < 12 ? 0.5 : 0.3) { return false }
        for marker in refusalMarkers where output.localizedCaseInsensitiveContains(marker) && !source.localizedCaseInsensitiveContains(marker) {
            return false
        }
        return true
    }

    /// 言い直しがあるとき、言い直した後の語が出力に残っているか（「9時、違う、9時半」なら「9時半」）
    static func keepsCorrection(source: String, output: String) -> Bool {
        guard let c = Prompts.correction(in: source) else { return true }
        let head = letters(c.after).prefix(3)
        guard head.count >= 2 else { return true }
        return String(letters(output)).contains(String(head))
    }

    /// 時刻・金額などの後の「に」「から」「まで」を AI が変えたり、足したり、落としたりしていないか
    /// （「3時に 4時からの会議」→「3時から4時からの会議」や「3時、4時からの会議」は意味が変わる）。
    /// 言い直しで消えた数（「3時、いや4時」の「3時」）は比べない。
    static func keepsQuantityParticles(source: String, output: String) -> Bool {
        let pattern = #"([0-9]+(?:時半|時|分|日|月|年|円|万円|人|名|個|件|回|ドル|%))(までに|から|まで|より|に)?"#
        func particles(_ text: String) -> [String: Set<String>] {
            var map: [String: Set<String>] = [:]
            for m in text.matches(of: try! Regex(pattern)) {
                let quantity = String(m.output[1].substring ?? "")
                let particle = String(m.output[2].substring ?? "")
                // 「3時より」は「3時から」の改まった言い方（ビジネス敬語で言い換える）なので同じとみなす
                map[quantity, default: []].insert(particle == "より" ? "から" : particle)
            }
            return map
        }
        let original = particles(source)
        for (quantity, used) in particles(output) {
            guard let said = original[quantity] else { continue }
            if used.contains(where: { !said.contains($0) }) { return false }
        }
        return true
    }

    /// 丁寧語の目印。話した中にこれがなければ、くだけた口調で話している。
    private static let politeMarkers = ["です", "ます", "ました", "ません", "ましょう", "ください", "下さい", "でしょう", "ございます"]

    private static func isPolite(_ text: String) -> Bool {
        politeMarkers.contains { text.contains($0) }
    }

    /// です・ます調で話していないのに AI が足した「ですか」を外す（「今何時ですか？」→「今何時？」）
    static func keepingCasualQuestions(source: String, output: String) -> String {
        guard !isPolite(source) else { return output }
        return output.replacingOccurrences(of: #"(?:ですか|でしょうか)[？?。]"#, with: "？", options: .regularExpression)
    }

    /// くだけた口調で話したのに、AI が です・ます調に書き換えていないか（「間違ってた」→「間違っていました」）
    static func keepsRegister(source: String, output: String) -> Bool {
        isPolite(source) || !isPolite(output)
    }

    /// 文字と数字だけを小文字で取り出す（空白・句読点・記号を除く）
    static func letters(_ text: String) -> [Character] {
        text.lowercased().filter { $0.isLetter || $0.isNumber }.map { $0 }
    }

    /// a の 2 文字の並びのうち、b にも出てくるものの割合
    static func overlap(_ a: [Character], _ b: [Character]) -> Double {
        guard a.count >= 2, b.count >= 2 else { return a == b ? 1 : 0 }
        let pairs = Set(zip(b, b.dropFirst()).map { String([$0, $1]) })
        let hits = zip(a, a.dropFirst()).filter { pairs.contains(String([$0, $1])) }.count
        return Double(hits) / Double(a.count - 1)
    }
}
