import Foundation

/// Typeless の 3 つの操作: ディクテーション / 翻訳 / Ask anything
enum Mode: String, Codable, CaseIterable, Identifiable {
    case dictate, translate, ask
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dictate: return t("ディクテーション", "Dictate")
        case .translate: return t("翻訳", "Translate")
        case .ask: return t("Ask anything", "Ask anything")
        }
    }

    var symbol: String {
        switch self {
        case .dictate: return "mic.fill"
        case .translate: return "globe"
        case .ask: return "sparkles"
        }
    }
}

/// 入力先アプリの種類。アプリごとのトーン調整に使う。
enum AppCategory: String, Codable, CaseIterable, Identifiable {
    case email, chat, document, code, ai, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .email: return t("メール", "Email")
        case .chat: return t("チャット", "Chat")
        case .document: return t("ドキュメント・メモ", "Docs & notes")
        case .code: return t("コーディング", "Coding")
        case .ai: return t("AI チャット", "AI chat")
        case .other: return t("その他", "Other")
        }
    }

    var symbol: String {
        switch self {
        case .email: return "envelope"
        case .chat: return "bubble.left.and.bubble.right"
        case .document: return "doc.text"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .ai: return "sparkles"
        case .other: return "square.grid.2x2"
        }
    }

    /// 既定のトーン（パーソナライズ前）
    var defaultStyleDescription: String {
        switch self {
        case .email: return "Polished and polite email prose with proper greetings preserved; in Japanese use appropriate keigo (です/ます)."
        case .chat: return "Casual, conversational chat message. Short sentences. No greeting or sign-off unless spoken. In Japanese keep the speaker's casual/polite level."
        case .document: return "Clear, well-structured writing. Use paragraphs and lists where the speaker enumerates."
        case .code: return "Concise technical writing. Keep code identifiers, file names, commands and technical terms verbatim (use backticks only if the speaker clearly means code)."
        case .ai: return "A clear, well-organized prompt for an AI assistant. Preserve every requirement the speaker mentions."
        case .other: return "Natural, clean writing that matches how the speaker talks."
        }
    }
}

enum StylePreset: String, Codable, CaseIterable, Identifiable {
    case auto, business, formal, neutral, casual
    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return t("自動（パーソナライズ）", "Auto (personalized)")
        case .business: return t("ビジネス敬語", "Business formal")
        case .formal: return t("フォーマル", "Formal")
        case .neutral: return t("ニュートラル", "Neutral")
        case .casual: return t("カジュアル", "Casual")
        }
    }

    var promptDescription: String? {
        switch self {
        case .auto: return nil
        case .business:
            return "Very formal business register. In Japanese, use business keigo with です/ます: 尊敬語 for other people's actions and 謙譲語 for the speaker's own (見る→ご覧になる/拝見する, 言う→おっしゃる/申し上げる, 行く・来る→いらっしゃる/伺う・参る, する→なさる/いたす, もらう→いただく), and avoid double honorifics such as おっしゃられる or ご覧になられる. Example: 社長が食べたいって言ってたお菓子、買っときました → 社長が召し上がりたいとおっしゃっていたお菓子を買っておきました。"
        case .formal: return "Formal and polite register (in Japanese: です/ます with natural 丁寧語・敬語)."
        case .neutral: return "Neutral, plain register."
        case .casual: return "Casual, friendly register (in Japanese: くだけた口調 when the speaker uses it)."
        }
    }

    /// アプリの種類の既定トーンに、ユーザーが選んだ言葉づかいを重ねた指示
    func styleDescription(for category: AppCategory) -> String {
        guard let p = promptDescription else { return category.defaultStyleDescription }
        return category.defaultStyleDescription
            + " The user chose this register for this kind of app, and it overrides the register above: " + p
            + " Rewrite sentence endings and honorifics to this register even if the speaker talked more casually, without changing the content."
    }
}

enum Retention: String, Codable, CaseIterable, Identifiable {
    case forever, year, month, week, day, never
    var id: String { rawValue }

    var title: String {
        switch self {
        case .forever: return t("無期限", "Forever")
        case .year: return t("1年", "1 year")
        case .month: return t("1か月", "1 month")
        case .week: return t("1週間", "1 week")
        case .day: return t("24時間", "24 hours")
        case .never: return t("保存しない", "Never")
        }
    }

    /// 保存期間（秒）。nil は無期限。
    var interval: TimeInterval? {
        switch self {
        case .forever: return nil
        case .year: return 365 * 86400
        case .month: return 30 * 86400
        case .week: return 7 * 86400
        case .day: return 86400
        case .never: return 0
        }
    }
}

enum Appearance: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return t("システムに合わせる", "System")
        case .light: return t("ライト", "Light")
        case .dark: return t("ダーク", "Dark")
        }
    }
}

/// サイドバーの背景。透明はデスクトップをぼかして透かし、色付きは不透明なグレーで塗る。
enum SidebarMaterial: String, Codable, CaseIterable, Identifiable {
    case transparent, tinted
    var id: String { rawValue }
    var title: String {
        switch self {
        case .transparent: return t("透明", "Transparent")
        case .tinted: return t("色付き", "Tinted")
        }
    }
}

// MARK: - AI プロバイダ（BYOK）

/// 音声認識エンジン
enum STTProvider: String, Codable, CaseIterable, Identifiable {
    case apple, local, openai, groq, custom
    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: return t("Apple オンデバイス（キー不要）", "Apple on-device (no key)")
        case .local: return t("この Mac のモデル（キー不要）", "Model on this Mac (no key)")
        case .openai: return "OpenAI"
        case .groq: return "Groq"
        case .custom: return t("カスタム（OpenAI 互換）", "Custom (OpenAI-compatible)")
        }
    }

    var keyAccount: String? {
        switch self {
        case .apple, .local: return nil
        case .openai: return "openai"
        case .groq: return "groq"
        case .custom: return "custom-stt"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .apple, .local: return ""
        case .openai: return "https://api.openai.com/v1"
        case .groq: return "https://api.groq.com/openai/v1"
        case .custom: return "http://localhost:8080/v1"
        }
    }

    var defaultModel: String {
        switch self {
        case .apple: return ""
        case .local: return LocalSpeechModel.qwen3Small.rawValue
        case .openai: return "gpt-4o-transcribe"
        case .groq: return "whisper-large-v3-turbo"
        case .custom: return "whisper-1"
        }
    }
}

/// テキスト整形・翻訳・Ask に使う LLM
enum LLMProvider: String, Codable, CaseIterable, Identifiable {
    case appleOnDevice, claude, claudeCode, codex, openAICompatible, none
    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleOnDevice: return t("Apple オンデバイス（キー不要）", "Apple on-device (no key)")
        case .claude: return "Claude (Anthropic)"
        case .claudeCode: return t("Claude のサブスク（Claude Code 経由）", "Claude subscription (via Claude Code)")
        case .codex: return t("ChatGPT のサブスク（Codex 経由）", "ChatGPT subscription (via Codex)")
        case .openAICompatible: return t("OpenAI 互換（OpenAI・Groq・OpenRouter・Gemini・Ollama など）", "OpenAI-compatible (OpenAI, Groq, OpenRouter, Gemini, Ollama…)")
        case .none: return t("整形しない（認識結果をそのまま入力）", "None (insert raw transcript)")
        }
    }
}

/// OpenAI 互換 API のプリセット。ベース URL と既定モデルを埋めるだけで、どれも書き換え可能。
enum CompatService: String, Codable, CaseIterable, Identifiable {
    case openai, groq, openrouter, gemini, ollama, custom
    var id: String { rawValue }

    var title: String {
        switch self {
        case .openai: return "OpenAI"
        case .groq: return "Groq"
        case .openrouter: return "OpenRouter"
        case .gemini: return "Google Gemini"
        case .ollama: return t("Ollama（ローカル）", "Ollama (local)")
        case .custom: return t("カスタム", "Custom")
        }
    }

    var keyAccount: String {
        switch self {
        case .openai: return "openai"
        case .groq: return "groq"
        case .openrouter: return "openrouter"
        case .gemini: return "gemini"
        case .ollama: return "ollama"
        case .custom: return "custom-llm"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openai: return "https://api.openai.com/v1"
        case .groq: return "https://api.groq.com/openai/v1"
        case .openrouter: return "https://openrouter.ai/api/v1"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta/openai"
        case .ollama: return "http://localhost:11434/v1"
        case .custom: return "http://localhost:1234/v1"
        }
    }

    var defaultModel: String {
        switch self {
        case .openai: return "gpt-5-mini"
        case .groq: return "openai/gpt-oss-120b"
        case .openrouter: return "openai/gpt-5-mini"
        case .gemini: return "gemini-2.5-flash"
        case .ollama: return "qwen3:8b"
        case .custom: return "local-model"
        }
    }

    var requiresKey: Bool { self != .ollama && self != .custom }
}

enum ClaudeModel: String, CaseIterable, Identifiable {
    case opus = "claude-opus-5-5"
    case sonnet = "claude-sonnet-5-5"
    case haiku = "claude-haiku-5-5"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .opus: return "Claude Opus 5.5"
        case .sonnet: return "Claude Sonnet 5.5"
        case .haiku: return t("Claude Haiku 5.5（最速）", "Claude Haiku 5.5 (fastest)")
        }
    }
}

// MARK: - 言語

struct LanguageOption: Identifiable, Hashable {
    let id: String  // BCP-47
    var name: String {
        let loc = Locale(identifier: L10n.current == .en ? "en" : "ja")
        return loc.localizedString(forIdentifier: id) ?? id
    }
}

enum Languages {
    /// クラウド音声認識向けの主な言語・地域バリアント
    static let dictation: [String] = [
        "ja-JP", "en-US", "en-GB", "en-AU", "en-CA", "en-IN",
        "zh-CN", "zh-TW", "zh-HK", "yue-CN", "ko-KR",
        "es-ES", "es-MX", "es-US", "fr-FR", "fr-CA", "de-DE", "it-IT",
        "pt-BR", "pt-PT", "nl-NL", "sv-SE", "da-DK", "nb-NO", "fi-FI",
        "pl-PL", "cs-CZ", "ru-RU", "uk-UA", "tr-TR", "el-GR", "he-IL",
        "ar-SA", "hi-IN", "bn-IN", "ta-IN", "th-TH", "vi-VN", "id-ID",
        "ms-MY", "fil-PH", "hu-HU", "ro-RO",
    ]

    /// 翻訳先として選べる言語
    static let translationTargets: [String] = [
        "en-US", "en-GB", "ja-JP", "zh-CN", "zh-TW", "ko-KR",
        "es-ES", "es-MX", "fr-FR", "de-DE", "it-IT", "pt-BR", "pt-PT",
        "nl-NL", "sv-SE", "pl-PL", "ru-RU", "uk-UA", "tr-TR",
        "ar-SA", "hi-IN", "th-TH", "vi-VN", "id-ID", "ms-MY", "fil-PH",
    ]

    static func name(_ id: String) -> String { LanguageOption(id: id).name }

    /// 音声バーに出す短い言語名（例: "JA"）。同じ言語の地域違いが並ぶときは地域も付ける（"EN-US" と "EN-GB"）。
    static func shortName(_ id: String, among ids: [String]) -> String {
        let code = isoCode(id)
        guard ids.filter({ isoCode($0) == code }).count > 1,
              let region = Locale(identifier: id).region?.identifier else { return code.uppercased() }
        return "\(code)-\(region)".uppercased()
    }

    /// プロンプトに渡す英語の言語名（例: "Japanese (Japan)"）
    static func englishName(_ id: String) -> String {
        Locale(identifier: "en").localizedString(forIdentifier: id) ?? id
    }

    /// 空白で単語を区切らない言語か
    static func isUnspaced(_ id: String) -> Bool {
        let lang = Locale(identifier: id).language.languageCode?.identifier ?? id
        return ["ja", "zh", "yue", "th", "lo", "km", "my"].contains(lang)
    }

    /// ISO-639-1 の言語コード（Whisper の language パラメータ用）
    static func isoCode(_ id: String) -> String {
        Locale(identifier: id).language.languageCode?.identifier ?? id
    }

    /// 文章がその言語の文字で書かれているか（翻訳が訳されずに元の言語のまま返ってきていないかを見る）。
    /// 文字で判定できない言語は true を返す。
    static func isWritten(_ text: String, in id: String) -> Bool {
        let scalars = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !scalars.isEmpty else { return false }
        func share(_ ranges: [ClosedRange<UInt32>]) -> Double {
            Double(scalars.filter { s in ranges.contains { $0.contains(s.value) } }.count) / Double(scalars.count)
        }
        let kana: [ClosedRange<UInt32>] = [0x3040...0x30FF]
        let han: [ClosedRange<UInt32>] = [0x4E00...0x9FFF, 0x3400...0x4DBF]
        let hangul: [ClosedRange<UInt32>] = [0xAC00...0xD7AF, 0x1100...0x11FF, 0x3130...0x318F]
        let latin: [ClosedRange<UInt32>] = [0x41...0x5A, 0x61...0x7A, 0xC0...0x24F, 0x1E00...0x1EFF]
        switch isoCode(id) {
        case "ja": return share(kana) > 0.05 || (share(han) > 0.5 && share(latin) < 0.5)
        case "zh", "yue": return share(han) > 0.5 && share(kana) == 0
        case "ko": return share(hangul) > 0.5
        case "ru", "uk": return share([0x400...0x4FF]) > 0.5
        case "el": return share([0x370...0x3FF]) > 0.5
        case "he": return share([0x590...0x5FF]) > 0.5
        case "ar": return share([0x600...0x6FF]) > 0.5
        case "hi": return share([0x900...0x97F]) > 0.5
        case "bn": return share([0x980...0x9FF]) > 0.5
        case "ta": return share([0xB80...0xBFF]) > 0.5
        case "th": return share([0xE00...0xE7F]) > 0.5
        case "en", "es", "fr", "de", "it", "pt", "nl", "sv", "da", "nb", "fi", "pl", "cs", "tr", "vi", "id", "ms", "fil", "hu", "ro":
            return share(latin) > 0.7
        default: return true
        }
    }
}
