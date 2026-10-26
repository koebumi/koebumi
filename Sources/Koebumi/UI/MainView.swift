import Combine
import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
    case workspace, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .workspace: return t("ワークスペース", "Workspace")
        case .settings: return t("設定", "Settings")
        }
    }
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case home, history, dictionary, style
    case general, shortcuts, audio, language, engines, privacy
    var id: String { rawValue }

    /// メニューバーの「設定…」で開くページ
    static let settings: SidebarItem = .general

    var section: SidebarSection {
        switch self {
        case .home, .history, .dictionary, .style: return .workspace
        default: return .settings
        }
    }

    var title: String {
        switch self {
        case .home: return t("ホーム", "Home")
        case .history: return t("履歴", "History")
        case .dictionary: return t("辞書", "Dictionary")
        case .style: return t("スタイル", "Style")
        case .general: return t("一般", "General")
        case .shortcuts: return t("ショートカット", "Shortcuts")
        case .audio: return t("オーディオ", "Audio")
        case .language: return t("言語", "Languages")
        case .engines: return t("AI エンジン", "AI engines")
        case .privacy: return t("プライバシー", "Privacy")
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .history: return "clock.arrow.circlepath"
        case .dictionary: return "character.book.closed"
        case .style: return "wand.and.stars"
        case .general: return "gearshape"
        case .shortcuts: return "command"
        case .audio: return "mic"
        case .language: return "globe"
        case .engines: return "cube"
        case .privacy: return "lock"
        }
    }

    /// サイドバーの検索で拾う語
    var keywords: [String] {
        switch self {
        case .home: return ["統計", "使い方", "stats", "usage"]
        case .history: return ["過去", "コピー", "再処理", "recent", "copy", "retry"]
        case .dictionary: return ["単語", "用語", "CSV", "スキル", "Claude Code", "word", "vocabulary", "skill"]
        case .style: return ["トーン", "パーソナライズ", "文体", "アプリ", "tone", "personalization", "app"]
        case .general: return ["外観", "テーマ", "ダーク", "ライト", "透明", "表示言語", "ログイン", "Dock", "クリップボード", "音声バー", "appearance", "theme", "dark", "light", "login", "clipboard", "voice bar"]
        case .shortcuts: return ["キー", "Fn", "ホットキー", "貼り付け", "keyboard", "hotkey", "key", "paste"]
        case .audio: return ["マイク", "サウンド", "ミュート", "音量", "microphone", "sound", "mute"]
        case .language: return ["翻訳", "話す言語", "translation", "translate"]
        case .engines: return ["AI", "API", "キー", "Claude", "OpenAI", "Groq", "Gemini", "Ollama", "モデル", "音声認識", "model", "key", "speech",
                               "サブスク", "ChatGPT", "Codex", "Claude Code", "subscription"]
        case .privacy: return ["データ", "保存", "削除", "音声", "data", "retention", "delete"]
        }
    }

    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return ([title, section.title] + keywords).contains { $0.localizedCaseInsensitiveContains(q) }
    }
}

@MainActor
final class Navigation: ObservableObject {
    static let shared = Navigation()
    @Published var selection: SidebarItem = .home
    @Published var showOnboarding = false

    func go(_ item: SidebarItem) {
        withAnimation(.smooth(duration: 0.28)) { selection = item }
    }
}

/// 権限とショートカットの状態。どれも通知が来ないので定期的に確かめる。
@MainActor
final class SystemStatus: ObservableObject {
    @Published private(set) var microphone = Permissions.microphoneGranted
    @Published private(set) var accessibility = Permissions.accessibilityGranted
    @Published private(set) var hotkeysRunning = false
    private var timer: AnyCancellable?

    init(controller: DictationController) {
        hotkeysRunning = controller.hotkeys.isRunning
        timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect().sink { [weak self, weak controller] _ in
            guard let self else { return }
            let mic = Permissions.microphoneGranted
            let ax = Permissions.accessibilityGranted
            let running = controller?.hotkeys.isRunning ?? false
            if mic != microphone { microphone = mic }
            if ax != accessibility { accessibility = ax }
            if running != hotkeysRunning { hotkeysRunning = running }
        }
    }

    var missingCount: Int { (microphone ? 0 : 1) + (accessibility ? 0 : 1) }
}

struct MainView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var navigation: Navigation
    @EnvironmentObject var controller: DictationController

    var body: some View {
        MainLayout(controller: controller)
            .id(settingsStore.settings.uiLanguage)  // 表示言語を変えたら全体を描き直す
            .sheet(isPresented: $navigation.showOnboarding) {
                OnboardingView()
            }
    }
}

private struct MainLayout: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @StateObject private var status: SystemStatus

    init(controller: DictationController) {
        _status = StateObject(wrappedValue: SystemStatus(controller: controller))
    }

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: Metrics.sidebarWidth)
            VStack(spacing: 0) {
                TopBar()
                    .frame(height: Metrics.titlebarHeight)
                ContentPanel()
            }
            .padding(.trailing, 8)
            .padding(.bottom, 8)
        }
        .background(ShellBackground(material: settingsStore.settings.sidebarMaterial))
        .ignoresSafeArea()
        .environmentObject(status)
        .frame(minWidth: 900, minHeight: 600)
    }
}

// MARK: - サイドバー

private struct Sidebar: View {
    @EnvironmentObject var navigation: Navigation
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var status: SystemStatus
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @Namespace private var namespace

    private var results: [SidebarItem] { SidebarItem.allCases.filter { $0.matches(query) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: Metrics.titlebarHeight)  // 信号ボタンの列

            SearchField(placeholder: t("検索", "Search"), text: $query, shortcut: ["⌘", "K"], focus: $searchFocused)
                .onSubmit { if let first = results.first { navigation.go(first); query = "" } }
                .padding(.horizontal, 12)
                .padding(.top, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(SidebarSection.allCases) { section in
                        let items = results.filter { $0.section == section }
                        if !items.isEmpty {
                            Text(section.title)
                                .font(.ui(12, .medium))
                                .foregroundStyle(Palette.textTertiary)
                                .padding(.horizontal, 10)
                                .padding(.top, 18)
                                .padding(.bottom, 6)
                            ForEach(items) { item in
                                SidebarRow(title: item.title, symbol: item.symbol,
                                           selected: navigation.selection == item, namespace: namespace) {
                                    navigation.go(item)
                                }
                            }
                        }
                    }
                    if results.isEmpty {
                        Text(t("一致する項目はありません", "No matches"))
                            .font(.ui(12.5))
                            .foregroundStyle(Palette.textTertiary)
                            .padding(.horizontal, 10)
                            .padding(.top, 18)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .animation(.smooth(duration: 0.25), value: navigation.selection)
            }
            .scrollIndicators(.never)
            .mask(EdgeFade(top: 6, bottom: 18))

            footer
        }
        .background {
            Button("") { searchFocused = true }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            SidebarRow(title: t("セットアップ", "Setup"), symbol: "checklist", selected: false, namespace: namespace) {
                navigation.showOnboarding = true
            } trailing: {
                if status.missingCount > 0 {
                    Badge(text: "\(status.missingCount)", tone: .neutral, symbol: "exclamationmark")
                } else {
                    SymbolBadge(symbol: "checkmark", size: 14)
                }
            }
            HStack(spacing: 7) {
                // 幅が足りないので、バージョンは表示せずツールチップに出す
                HStack(spacing: 7) {
                    KoebumiMark(size: 14, color: Palette.textSecondary)
                    Text("Koebumi")
                        .font(.ui(12.5, .medium))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                        .fixedSize()
                }
                .help("Koebumi " + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""))
                Spacer(minLength: 8)
                SegmentedControl(selection: $settingsStore.settings.appearance,
                                 options: [.light, .dark, .system],
                                 title: { $0.title },
                                 symbol: { $0.symbol },
                                 iconOnly: true)
            }
            .padding(.horizontal, 10)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .overlay(alignment: .top) {
            Rectangle().fill(Palette.divider).frame(height: 1).padding(.horizontal, 22)
        }
    }
}

extension Appearance {
    var shortTitle: String {
        switch self {
        case .system: return t("システム", "System")
        default: return title
        }
    }

    var symbol: String {
        switch self {
        case .system: return "display"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
}

private struct SidebarRow<Trailing: View>: View {
    var title: String
    var symbol: String
    var selected: Bool
    var namespace: Namespace.ID
    var action: () -> Void
    @ViewBuilder var trailing: Trailing
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13.5, weight: selected ? .medium : .regular))
                    .frame(width: 18)
                Text(title)
                    .font(.ui(13.5, selected ? .medium : .regular))
                    .lineLimit(1)
                Spacer(minLength: 4)
                trailing
            }
            .foregroundStyle(selected ? Palette.text : Palette.sidebarText)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Palette.selection)
                        .matchedGeometryEffect(id: "selection", in: namespace)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.hover)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension SidebarRow where Trailing == EmptyView {
    init(title: String, symbol: String, selected: Bool, namespace: Namespace.ID, action: @escaping () -> Void) {
        self.init(title: title, symbol: symbol, selected: selected, namespace: namespace, action: action) { EmptyView() }
    }
}

// MARK: - タイトルバー

private struct TopBar: View {
    @EnvironmentObject var navigation: Navigation
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var controller: DictationController
    @EnvironmentObject var status: SystemStatus

    var body: some View {
        HStack(spacing: 9) {
            KoebumiMark(size: 16)
            Text("Koebumi")
                .font(.ui(13.5, .semibold))
                .foregroundStyle(Palette.text)
            Rectangle()
                .fill(Palette.textTertiary.opacity(0.5))
                .frame(width: 1, height: 14)
                .padding(.horizontal, 3)
            Text(navigation.selection.section.title)
                .foregroundStyle(Palette.textSecondary)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
            Text(navigation.selection.title)
                .foregroundStyle(Palette.textSecondary)
                .contentTransition(.opacity)
                .id(navigation.selection)
            Spacer(minLength: 12)
            statusPill
        }
        .font(.ui(13.5))
        .padding(.leading, 12)
        .padding(.trailing, 2)
        .padding(.top, 1)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
    }

    @ViewBuilder
    private var statusPill: some View {
        if status.missingCount > 0 {
            Button { navigation.showOnboarding = true } label: {
                pill(symbol: "exclamationmark") {
                    Text(t("セットアップが必要です", "Finish setup"))
                }
            }
            .buttonStyle(.plain)
        } else if controller.phase == .recording {
            pill(color: Palette.inverse, pulsing: true) {
                Text(t("録音中", "Listening"))
            }
        } else {
            pill(color: Palette.textTertiary, pulsing: false) {
                Text(t("準備完了", "Ready"))
                if let shortcut = settingsStore.settings.dictateShortcuts.first {
                    ShortcutKeys(shortcut: shortcut, compact: true)
                }
            }
        }
    }

    /// symbol を渡すと、点の代わりに白黒の丸に記号を置く
    private func pill<Content: View>(color: Color = .clear, pulsing: Bool = false, symbol: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 7) {
            if let symbol {
                SymbolBadge(symbol: symbol, size: 14)
            } else {
                StatusDot(color: color, pulsing: pulsing)
            }
            content()
        }
        .font(.ui(12, .medium))
        .foregroundStyle(Palette.textSecondary)
        .padding(.leading, 10)
        .padding(.trailing, 5)
        .frame(height: 28)
        .background(Capsule().fill(Palette.hover))
    }
}

struct StatusDot: View {
    var color: Color
    var pulsing: Bool
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .background(
                Circle()
                    .fill(color.opacity(0.35))
                    .scaleEffect(pulse ? 2.6 : 1)
                    .opacity(pulse ? 0 : 1)
            )
            .onAppear {
                guard pulsing else { return }
                withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) { pulse = true }
            }
    }
}

// MARK: - 本文

private struct ContentPanel: View {
    @EnvironmentObject var navigation: Navigation

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.panelRadius, style: .continuous)
        ZStack {
            page
                .id(navigation.selection)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 6)), removal: .opacity))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.panel)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Palette.panelBorder))
        .shadow(color: .black.opacity(0.05), radius: 1.5, y: 1)
    }

    @ViewBuilder
    private var page: some View {
        switch navigation.selection {
        case .home: HomeView()
        case .history: HistoryView()
        case .dictionary: DictionaryView()
        case .style: StyleView()
        case .general: GeneralSettingsPage()
        case .shortcuts: ShortcutSettingsPage()
        case .audio: AudioSettingsPage()
        case .language: LanguageSettingsPage()
        case .engines: EngineSettingsPage()
        case .privacy: PrivacySettingsPage()
        }
    }
}
