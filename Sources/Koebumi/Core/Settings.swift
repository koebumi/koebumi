import Combine
import Foundation

struct AppSettings: Codable, Equatable {
    // 一般
    var uiLanguage: UILanguage = .systemDefault
    var appearance: Appearance = .system
    var sidebarMaterial: SidebarMaterial = .transparent
    var voiceBarAppearance: VoiceBarAppearance = .theme
    /// 録音中に書き起こした内容を、音声バーの上の札に出す（録音しながら書き起こすエンジンのときだけ）。初めは出さない
    var showLiveTranscript = false
    var launchAtLogin = false
    var showInDock = true
    var onboardingCompleted = false

    // ショートカット（各操作に複数登録できる）
    var dictateShortcuts: [Shortcut] = [.fn]
    var translateShortcuts: [Shortcut] = [.fnLeftShift]
    var askShortcuts: [Shortcut] = [.fnSpace]
    var pasteLastShortcuts: [Shortcut] = [.commandOptionV]
    var revertLastShortcuts: [Shortcut] = [.commandOptionZ]

    // オーディオ
    var microphoneUID: String?  // nil = 自動検出（システムの既定マイク。既定が Bluetooth なら内蔵マイク）
    var interactionSounds = true
    var muteWhileDictating = false

    // 言語
    var dictationLanguages: [String] = [Locale.preferredLanguages.first?.hasPrefix("ja") == false ? "en-US" : "ja-JP"]
    var activeDictationLanguage: String?
    var translationTargets: [String] = ["en-US"]
    var activeTranslationTarget: String?

    // 音声認識（BYOK）
    var sttProvider: STTProvider = .apple
    var sttModels: [String: String] = [:]  // provider → model
    var sttBaseURLs: [String: String] = [:]  // provider → base URL

    // テキスト整形（BYOK）
    var llmProvider: LLMProvider = .appleOnDevice
    var claudeModel: String = ClaudeModel.opus.rawValue
    var codexModel = ""  // 空なら Codex の既定のモデル
    var compatService: CompatService = .openai
    var compatModels: [String: String] = [:]  // service → model
    var compatBaseURLs: [String: String] = [:]  // service → base URL
    var webSearch = true

    // 履歴・プライバシー
    var historyRetention: Retention = .forever
    var keepAudio = true
    var keepResultInClipboard = false

    // パーソナライズ・辞書
    var personalizationEnabled = true
    var autoAddDictionary = true
    var categoryStyles: [String: StylePreset] = [:]  // AppCategory → preset
    var appCategoryOverrides: [String: AppCategory] = [:]  // bundle ID → category
    /// 端末で Claude Code・Codex が動いていたら、AI チャットとして整形する
    var detectCodingAgents = true
    /// エージェントに「送信」と言うと Enter を押し、「スラッシュ 〜」はスラッシュコマンドにする
    var agentVoiceCommands = true
    var japaneseNotation = JapaneseNotation()
    /// 「チャット」に分類したアプリでの句読点（どの言語にも使う）
    var chatPunctuation: ChatPunctuation = .noPunctuation
    var contextAwareness: ContextAwareness = .localOnly
    /// メールでは、返信先のメールに合わせて書き出しの挨拶と相手の敬称を直す
    var mailReplyStyle = true
    /// 呼び出す言葉だけを話すと入力する定型文（署名・挨拶など）
    var snippets: [Snippet] = []

    init() {}

    func shortcuts(for mode: Mode) -> [Shortcut] {
        switch mode {
        case .dictate: return dictateShortcuts
        case .translate: return translateShortcuts
        case .ask: return askShortcuts
        }
    }

    mutating func setShortcuts(_ list: [Shortcut], for mode: Mode) {
        switch mode {
        case .dictate: dictateShortcuts = list
        case .translate: translateShortcuts = list
        case .ask: askShortcuts = list
        }
    }

    var currentDictationLanguage: String {
        if let a = activeDictationLanguage, dictationLanguages.contains(a) { return a }
        return dictationLanguages.first ?? "ja-JP"
    }

    var currentTranslationTarget: String {
        if let a = activeTranslationTarget, translationTargets.contains(a) { return a }
        return translationTargets.first ?? "en-US"
    }

    func sttModel(_ p: STTProvider) -> String {
        let v = sttModels[p.rawValue] ?? ""
        return v.isEmpty ? p.defaultModel : v
    }

    /// この Mac で動かす音声認識モデル（sttProvider が .local のときに使う）
    var localSpeechModel: LocalSpeechModel {
        LocalSpeechModel(rawValue: sttModel(.local)) ?? .qwen3Small
    }

    /// 音声認識に言語を 1 つ指定する必要があるか。Apple の音声認識と、言語を判定しないモデルは、音声バーで選んだ言語で認識する。
    var sttNeedsFixedLanguage: Bool {
        sttProvider == .apple || (sttProvider == .local && !localSpeechModel.detectsLanguage)
    }

    /// 音声認識に渡す言語。指定が要らないエンジンには話す言語をすべて渡し、自動判定に任せる。
    func sttLanguages(current: String) -> [String] {
        sttNeedsFixedLanguage ? [current] : dictationLanguages
    }

    /// 画面に出す音声認識の名前
    var sttTitle: String {
        sttProvider == .local ? localSpeechModel.title : sttProvider.title
    }

    /// 文中に出す音声認識の短い名前
    var sttName: String {
        switch sttProvider {
        case .apple: return t("Apple の音声認識", "Apple speech recognition")
        case .local: return localSpeechModel.title
        case .openai, .groq: return sttProvider.title
        case .custom: return t("カスタムの音声認識", "Custom speech recognition")
        }
    }

    func sttBaseURL(_ p: STTProvider) -> String {
        let v = sttBaseURLs[p.rawValue] ?? ""
        return v.isEmpty ? p.defaultBaseURL : v
    }

    func compatModel(_ s: CompatService) -> String {
        let v = compatModels[s.rawValue] ?? ""
        return v.isEmpty ? s.defaultModel : v
    }

    func compatBaseURL(_ s: CompatService) -> String {
        let v = compatBaseURLs[s.rawValue] ?? ""
        return v.isEmpty ? s.defaultBaseURL : v
    }

    func style(for category: AppCategory) -> StylePreset {
        categoryStyles[category.rawValue] ?? .auto
    }

    // 新しい項目を追加しても古い設定ファイルを読めるよう、欠けたキーは既定値で埋める。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        func v<T: Decodable>(_ key: CodingKeys, _ def: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? def
        }
        uiLanguage = v(.uiLanguage, d.uiLanguage)
        appearance = v(.appearance, d.appearance)
        sidebarMaterial = v(.sidebarMaterial, d.sidebarMaterial)
        voiceBarAppearance = v(.voiceBarAppearance, d.voiceBarAppearance)
        showLiveTranscript = v(.showLiveTranscript, d.showLiveTranscript)
        launchAtLogin = v(.launchAtLogin, d.launchAtLogin)
        showInDock = v(.showInDock, d.showInDock)
        onboardingCompleted = v(.onboardingCompleted, d.onboardingCompleted)
        dictateShortcuts = v(.dictateShortcuts, d.dictateShortcuts)
        translateShortcuts = v(.translateShortcuts, d.translateShortcuts)
        askShortcuts = v(.askShortcuts, d.askShortcuts)
        pasteLastShortcuts = v(.pasteLastShortcuts, d.pasteLastShortcuts)
        revertLastShortcuts = v(.revertLastShortcuts, d.revertLastShortcuts)
        microphoneUID = v(.microphoneUID, d.microphoneUID)
        interactionSounds = v(.interactionSounds, d.interactionSounds)
        muteWhileDictating = v(.muteWhileDictating, d.muteWhileDictating)
        dictationLanguages = v(.dictationLanguages, d.dictationLanguages)
        activeDictationLanguage = v(.activeDictationLanguage, d.activeDictationLanguage)
        translationTargets = v(.translationTargets, d.translationTargets)
        activeTranslationTarget = v(.activeTranslationTarget, d.activeTranslationTarget)
        sttProvider = v(.sttProvider, d.sttProvider)
        sttModels = v(.sttModels, d.sttModels)
        sttBaseURLs = v(.sttBaseURLs, d.sttBaseURLs)
        llmProvider = v(.llmProvider, d.llmProvider)
        claudeModel = v(.claudeModel, d.claudeModel)
        codexModel = v(.codexModel, d.codexModel)
        compatService = v(.compatService, d.compatService)
        compatModels = v(.compatModels, d.compatModels)
        compatBaseURLs = v(.compatBaseURLs, d.compatBaseURLs)
        webSearch = v(.webSearch, d.webSearch)
        historyRetention = v(.historyRetention, d.historyRetention)
        keepAudio = v(.keepAudio, d.keepAudio)
        keepResultInClipboard = v(.keepResultInClipboard, d.keepResultInClipboard)
        personalizationEnabled = v(.personalizationEnabled, d.personalizationEnabled)
        autoAddDictionary = v(.autoAddDictionary, d.autoAddDictionary)
        categoryStyles = v(.categoryStyles, d.categoryStyles)
        appCategoryOverrides = v(.appCategoryOverrides, d.appCategoryOverrides)
        detectCodingAgents = v(.detectCodingAgents, d.detectCodingAgents)
        agentVoiceCommands = v(.agentVoiceCommands, d.agentVoiceCommands)
        japaneseNotation = v(.japaneseNotation, d.japaneseNotation)
        chatPunctuation = v(.chatPunctuation, Self.legacyChatPunctuation(decoder))
        contextAwareness = v(.contextAwareness, d.contextAwareness)
        mailReplyStyle = v(.mailReplyStyle, d.mailReplyStyle)
        snippets = v(.snippets, d.snippets)
    }

    /// チャットの句読点は、以前は日本語の表記ルールの中にあった。その前は「チャットでは文末の「。」を付けない」のオン・オフだった
    private enum LegacyKeys: String, CodingKey {
        case japaneseNotation, chatPunctuation, omitChatPeriod
    }

    /// 以前の設定を引き継ぐ。どこにもなければ以前の初期値の「そのまま」にする（「句読点を付けない」は新しく使い始めた人の初期値）
    private static func legacyChatPunctuation(_ decoder: Decoder) -> ChatPunctuation {
        guard let old = try? decoder.container(keyedBy: LegacyKeys.self).nestedContainer(keyedBy: LegacyKeys.self, forKey: .japaneseNotation)
        else { return .keep }
        if let rule = try? old.decodeIfPresent(ChatPunctuation.self, forKey: .chatPunctuation) { return rule }
        return (try? old.decodeIfPresent(Bool.self, forKey: .omitChatPeriod)) == true ? .noFinalPeriod : .keep
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    private static let fileName = "settings.json"

    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            L10n.current = settings.uiLanguage
            Storage.save(settings, to: Self.fileName)
        }
    }

    private init() {
        let loaded = Storage.load(AppSettings.self, from: Self.fileName) ?? AppSettings()
        settings = loaded
        L10n.current = loaded.uiLanguage
    }

    // API キーはキーチェーンに保存する
    func apiKey(_ account: String) -> String { Keychain.get(account) ?? "" }

    func setAPIKey(_ value: String, for account: String) {
        objectWillChange.send()
        Keychain.set(value.trimmingCharacters(in: .whitespacesAndNewlines), for: account)
    }
}
