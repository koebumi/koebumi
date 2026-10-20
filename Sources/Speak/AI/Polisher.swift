import Foundation

/// 認識結果から入力するテキストを作る。アプリと CLI（--polish）で同じ処理を通す。
/// 表記の統一と辞書の置き換え → AI 整形 → 出力の検証 → 表記の統一、の順に行う。
enum Polisher {
    struct Output: Equatable {
        var text: String
        /// AI 整形を諦めて簡易整形にしたときの理由（ユーザーに知らせる）
        var warning: String?
    }

    /// AI に渡す前の決まった下処理（Ask の質問にも使う）
    static func prepare(_ transcript: String, aliases: [String: String]) -> String {
        VocabularyReplacer.apply(TextNormalizer.normalize(transcript), aliases: aliases)
    }

    static func run(_ request: PolishRequest, engine: LLMEngine?) async throws -> Output {
        var request = request
        request.transcript = prepare(request.transcript, aliases: request.aliases)
        let fallback = finish(BasicCleaner.clean(request.transcript), request)
        guard let engine else {
            if request.mode == .translate {
                throw LLMError.unavailable(t("翻訳には AI エンジンが必要です（設定 > AI エンジン）", "Translation needs an AI engine (Settings > AI engines)"))
            }
            return Output(text: fallback)
        }
        do {
            let polished = try await engine.polish(request)
            let text = VocabularyReplacer.apply(TextNormalizer.normalize(polished), aliases: request.aliases)
            if request.mode == .translate {
                guard !text.isEmpty else { throw LLMError.badResponse }
                return Output(text: finish(text, request))
            }
            guard OutputGuard.accepts(source: request.transcript, output: text, minOverlap: request.allowsRewording ? 0.12 : 0.3) else {
                // 質問に答えた・内容を落としたなど、整形として不自然な出力は使わない
                NSLog("Speak: rejected AI output, using basic cleanup. source=\(request.transcript.count) output=\(text.count)")
                return Output(text: fallback)
            }
            return Output(text: finish(text, request))
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            if request.mode == .translate { throw error }
            // 整形に失敗しても話した内容は失わない
            let warning = t("AI 整形に失敗したため認識結果を入力しました: ", "AI cleanup failed, inserted the transcript: ") + error.localizedDescription
            return Output(text: fallback, warning: warning)
        }
    }

    /// 日本語の表記ルール、画面に合わせた人名の表記、カーソル前後とのつなぎ方を最後にそろえる
    static func finish(_ text: String, _ request: PolishRequest) -> String {
        var t = text
        if let n = request.notation { t = JapaneseFormatter.apply(t, notation: n, category: request.category) }
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

    /// minOverlap: 言葉づかいを指定して言い換えさせるとき（敬語化など）は、文字の重なりが少なくても受け入れる
    static func accepts(source: String, output: String, minOverlap: Double = 0.3) -> Bool {
        let s = letters(source), o = letters(output)
        guard !o.isEmpty else { return s.isEmpty }
        if s.isEmpty { return false }
        // 話していない内容を大量に足した（質問に答えた・続きを書いた）
        if o.count > s.count * 3 / 2 + 20 { return false }
        // 大部分を落とした（フィラーと言い直しを除いても 3 割未満）
        let cleaned = letters(BasicCleaner.clean(source))
        if cleaned.count >= 20, o.count * 10 < cleaned.count * 3 { return false }
        // 出力の大部分が、話した内容に出てこない文字の並びでできている
        if o.count >= 12, overlap(o, s) < minOverlap { return false }
        for marker in refusalMarkers where output.localizedCaseInsensitiveContains(marker) && !source.localizedCaseInsensitiveContains(marker) {
            return false
        }
        return true
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
