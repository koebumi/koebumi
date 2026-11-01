import Foundation

/// この Mac で動かす音声認識モデル。並びは設定画面の並び。
/// 多くは speech-swift で動かす。Haas は speech.cpp（`SpeechCppModel`）、Granite はこのアプリの中の MLX のコード（`GraniteSpeechCTCModel`）で動かす。
/// 速さと正確さは 5 段階。M3 で読み上げ音声（日本語・英語・中国語と、日本語と英語が続く発話）を認識させて決めた。
enum LocalSpeechModel: String, Codable, CaseIterable, Identifiable {
    case qwen3Small = "qwen3-asr-0.6b"
    case qwen3Large = "qwen3-asr-1.7b"
    case moss = "moss-transcribe-diarize"
    case whisperTurbo = "whisper-large-v3-turbo"
    case cohere = "cohere-transcribe"
    case nemotron = "nemotron-3.5-asr-streaming"
    case haas = "haas-ja-v1.0"
    case granite = "granite-speech-5.0-turboctc"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .qwen3Small: return "Qwen3-ASR 0.6B"
        case .qwen3Large: return "Qwen3-ASR 1.7B"
        case .moss: return "MOSS Transcribe Diarize"
        case .whisperTurbo: return "Whisper Large v3 Turbo"
        case .cohere: return "Cohere Transcribe"
        case .nemotron: return "Nemotron 3.5 ASR Streaming"
        case .haas: return "Haas ja v1.0"
        case .granite: return "Granite Speech 5.0 TurboCTC"
        }
    }

    /// 作った組織
    var maker: String {
        switch self {
        case .qwen3Small, .qwen3Large: return "Qwen"
        case .moss: return "OpenMOSS"
        case .whisperTurbo: return "OpenAI"
        case .cohere: return "Cohere"
        case .nemotron: return "NVIDIA"
        case .haas: return "Third Intelligence"
        case .granite: return "IBM"
        }
    }

    /// Hugging Face のリポジトリ。speech-swift 向けに変換された重み、speech.cpp 向けの GGUF、元の重み（Granite）のどれか
    var repo: String {
        switch self {
        case .qwen3Small: return "aufklarer/Qwen3-ASR-0.6B-MLX-4bit"
        case .qwen3Large: return "aufklarer/Qwen3-ASR-1.7B-MLX-4bit"
        case .moss: return "aufklarer/MOSS-Transcribe-Diarize-0.9B-MLX-5bit"
        case .whisperTurbo: return "aufklarer/Whisper-Large-v3-Turbo-CoreML"
        case .cohere: return "aufklarer/Cohere-Transcribe-2B-MLX-5bit"
        case .nemotron: return "aufklarer/Nemotron-3.5-ASR-Streaming-0.6B-CoreML-INT8"
        case .haas: return "sakasegawa/Haas-ja-v1.0-GGUF"
        case .granite: return "ibm-granite/granite-speech-5.0-470m-turboctc"
        }
    }

    /// ダウンロードの大きさ（バイト）。表示用の目安。
    var downloadBytes: Int64 {
        switch self {
        case .qwen3Small: return 680_000_000
        case .qwen3Large: return 2_100_000_000
        case .moss: return 1_000_000_000
        case .whisperTurbo: return 1_500_000_000
        case .cohere: return 1_600_000_000
        case .nemotron: return 642_000_000
        case .haas: return 656_000_000
        case .granite: return 948_000_000
        }
    }

    var speed: Int {
        switch self {
        case .qwen3Small, .cohere, .nemotron, .haas, .granite: return 5
        case .qwen3Large, .moss: return 4
        case .whisperTurbo: return 3
        }
    }

    var accuracy: Int {
        switch self {
        case .qwen3Large, .moss, .haas: return 5
        case .qwen3Small, .whisperTurbo, .granite: return 4
        case .cohere, .nemotron: return 3
        }
    }

    /// 話した言語を自動で判定するか。しないモデルには、音声バーで選んだ言語を渡す。
    /// Haas は日本語だけを認識するので、音声バーで日本語を選んだときだけ使える
    var detectsLanguage: Bool { self != .cohere && self != .haas }

    /// 対応する言語の数
    var languageCount: Int {
        switch self {
        case .qwen3Small, .qwen3Large: return 30
        case .moss: return 50
        case .whisperTurbo: return 99
        case .cohere: return 14
        case .nemotron: return 75
        case .haas: return 1
        case .granite: return 7
        }
    }

    var isRecommended: Bool { self == .qwen3Small }

    var summary: String {
        switch self {
        case .qwen3Small:
            return t("一番速く、話し終えてすぐ文字になります。迷ったらこれを選んでください。",
                     "The fastest. Text appears right after you stop speaking. Pick this if unsure.")
        case .qwen3Large:
            return t("0.6B より正確です。日本語の文に続けて英語の文を話しても、両方を書き起こします。",
                     "More accurate than 0.6B. Transcribes both sentences when you switch languages mid-utterance.")
        case .moss:
            return t("会議の書き起こし向けのモデルです。日本語の文に続けて英語の文を話しても、両方を書き起こします。",
                     "Built for meeting transcripts. Transcribes both sentences when you switch languages mid-utterance.")
        case .whisperTurbo:
            return t("対応する言語が一番多いモデルです。日本語と中国語には句読点が付かないので、AI の整形で補います。",
                     "Supports the most languages. Japanese and Chinese come without punctuation, which AI cleanup adds.")
        case .cohere:
            return t("言語を自動で判定しないので、音声バーで選んだ言語で認識します。日本語は最初の部分が抜けることがあります。",
                     "Does not detect the language; it uses the one chosen on the voice bar. Japanese may lose its first words.")
        case .nemotron:
            return t("話している途中から、0.32 秒ごとに文字が出ます。日本語の正確さは Qwen3-ASR より少し劣ります。",
                     "Text appears while you speak, every 0.32 s. Japanese is a little less accurate than Qwen3-ASR.")
        case .haas:
            return t("日本語専用で、日本語を一番正確に書き起こします。日本語以外の言語は認識しません。speech.cpp で動かします。",
                     "Japanese only, and the most accurate for Japanese. Does not transcribe other languages. Runs on speech.cpp.")
        case .granite:
            return t("日本語・英語など 7 言語に対応します。音声全体を一度に認識するので速いモデルです。日本語には句読点がほとんど付かないので、AI の整形で補います。",
                     "Supports 7 languages, including Japanese and English. Fast, since it reads the whole audio at once. Japanese comes with little punctuation, which AI cleanup adds.")
        }
    }

    /// モデルに渡す言語の書き方。nil なら渡さない（自動判定する、または言語を受け取らない）。
    func languageHint(for languages: [String]) -> String? {
        guard self == .cohere || languages.count == 1, let lang = languages.first else { return nil }
        let code = Languages.isoCode(lang)
        switch self {
        case .qwen3Small, .qwen3Large:
            // Qwen3-ASR は "language Japanese" のように英語の言語名で指示する
            return Locale(identifier: "en").localizedString(forLanguageCode: code)
        case .whisperTurbo, .cohere:
            return code
        case .nemotron:
            // Nemotron は "ja-JP" のような BCP-47 の書き方で受け取る。知らない書き方なら自動判定になる
            return lang
        case .moss, .haas, .granite:
            // Haas は日本語だけを認識し、Granite は言語を受け取らない
            return nil
        }
    }

    /// Cohere Transcribe が認識できる言語
    static let cohereLanguages: Set<String> = ["en", "fr", "de", "it", "es", "pt", "el", "nl", "pl", "zh", "ja", "ko", "vi", "ar"]

    /// Granite Speech 5.0 TurboCTC が認識できる言語（モデルカードの Supported Languages）
    static let graniteLanguages: Set<String> = ["en", "fr", "de", "es", "pt", "it", "ja"]

    func supports(_ language: String) -> Bool {
        let code = Languages.isoCode(language)
        switch self {
        case .cohere: return Self.cohereLanguages.contains(code)
        case .haas: return code == "ja"
        case .granite: return Self.graniteLanguages.contains(code)
        default: return true
        }
    }

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: downloadBytes, countStyle: .file)
    }
}

/// 設定画面で選ぶ音声認識。Apple の内蔵・この Mac のモデル・クラウドを 1 つの一覧に並べる。
enum SpeechEngineChoice: Hashable, Identifiable {
    case apple
    case local(LocalSpeechModel)
    case cloud(STTProvider)

    var id: String {
        switch self {
        case .apple: return "apple"
        case .local(let m): return "local." + m.rawValue
        case .cloud(let p): return "cloud." + p.rawValue
        }
    }

    static let onDevice: [SpeechEngineChoice] = [.apple] + LocalSpeechModel.allCases.map { .local($0) }
    static let cloud: [SpeechEngineChoice] = [.cloud(.openai), .cloud(.groq), .cloud(.custom)]

    init(_ settings: AppSettings) {
        switch settings.sttProvider {
        case .apple: self = .apple
        case .local: self = .local(settings.localSpeechModel)
        default: self = .cloud(settings.sttProvider)
        }
    }

    func apply(to settings: inout AppSettings) {
        switch self {
        case .apple: settings.sttProvider = .apple
        case .local(let m):
            settings.sttProvider = .local
            settings.sttModels[STTProvider.local.rawValue] = m.rawValue
        case .cloud(let p): settings.sttProvider = p
        }
    }
}
