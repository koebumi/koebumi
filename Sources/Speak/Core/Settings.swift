import Combine
import Foundation

struct AppSettings: Codable, Equatable {
    // 一般
    var uiLanguage: UILanguage = .systemDefault
    var appearance: Appearance = .system
    var sidebarMaterial: SidebarMaterial = .transparent
    var launchAtLogin = false
    var showInDock = true
    var onboardingCompleted = false

    // ショートカット（各操作に複数登録できる）
    var dictateShortcuts: [Shortcut] = [.fn]
    var translateShortcuts: [Shortcut] = [.fnLeftShift]
    var askShortcuts: [Shortcut] = [.fnSpace]

    // オーディオ
    var microphoneUID: String?  // nil = 自動検出（システムの既定マイク）
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
        launchAtLogin = v(.launchAtLogin, d.launchAtLogin)
        showInDock = v(.showInDock, d.showInDock)
        onboardingCompleted = v(.onboardingCompleted, d.onboardingCompleted)
        dictateShortcuts = v(.dictateShortcuts, d.dictateShortcuts)
        translateShortcuts = v(.translateShortcuts, d.translateShortcuts)
        askShortcuts = v(.askShortcuts, d.askShortcuts)
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
