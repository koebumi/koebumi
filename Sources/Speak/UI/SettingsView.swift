import AppKit
import Combine
import Speech
import SwiftUI

// MARK: - 一般

struct GeneralSettingsPage: View {
    @EnvironmentObject var settingsStore: SettingsStore

    var body: some View {
        Page {
            PageHeader(title: t("一般", "General"))

            SettingsGroup {
                TileRow(title: t("テーマ", "Theme"), subtitle: t("Speak の見た目を選びます", "Choose how Speak looks")) {
                    ForEach([Appearance.system, .light, .dark]) { appearance in
                        ChoiceTile(title: appearance.shortTitle, selected: settingsStore.settings.appearance == appearance) {
                            settingsStore.settings.appearance = appearance
                        } preview: {
                            ThemePreview(appearance: appearance)
                        }
                    }
                }
                TileRow(title: t("サイドバー", "Sidebar"), subtitle: t("背景をデスクトップに透かすか、色で塗るかを選びます", "Let the desktop show through, or use a solid tint")) {
                    ForEach(SidebarMaterial.allCases) { material in
                        ChoiceTile(title: material.title, selected: settingsStore.settings.sidebarMaterial == material) {
                            settingsStore.settings.sidebarMaterial = material
                        } preview: {
                            MaterialPreview(material: material)
                        }
                    }
                }
                SettingRow(title: t("表示言語", "Interface language"), subtitle: t("メニューと画面の言語", "Language for menus and windows")) {
                    PopupPicker(selection: $settingsStore.settings.uiLanguage, options: UILanguage.allCases, title: { $0.displayName }, minWidth: 110)
                }
            }

            SectionLabel(t("起動とウィンドウ", "Startup & window"))
            SettingsGroup {
                ToggleRow(title: t("ログイン時に起動", "Launch at login"),
                          subtitle: t("Mac にログインすると、メニューバーで待機します", "Start in the menu bar when you log in"),
                          isOn: Binding(
                              get: { settingsStore.settings.launchAtLogin },
                              set: {
                                  settingsStore.settings.launchAtLogin = $0
                                  LoginItem.set($0)
                              }
                          ))
                ToggleRow(title: t("Dock にアイコンを表示", "Show app in Dock"),
                          subtitle: t("オフにするとメニューバーだけに表示します", "When off, Speak lives only in the menu bar"),
                          isOn: $settingsStore.settings.showInDock)
                ToggleRow(title: t("入力した結果をクリップボードにも残す", "Keep results in the clipboard"),
                          subtitle: t("貼り付けたあとも、結果をもう一度ペーストできます", "Paste the last result again after it is inserted"),
                          isOn: $settingsStore.settings.keepResultInClipboard)
            }
        }
    }
}

/// タイトルを左上、選択肢のタイルを右に並べる行（Aside の「Tab style」）
private struct TileRow<Tiles: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var tiles: Tiles

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.ui(13.5, .medium)).foregroundStyle(Palette.text)
                Text(subtitle).font(.ui(12.5)).foregroundStyle(Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
            HStack(alignment: .top, spacing: 10) { tiles }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct ChoiceTile<Preview: View>: View {
    var title: String
    var selected: Bool
    var action: () -> Void
    @ViewBuilder var preview: Preview
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                preview
                    .frame(width: 92, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.black.opacity(0.08)))
                    .padding(3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(selected ? Palette.accent : (hovering ? Palette.controlBorder : .clear), lineWidth: 2)
                    )
                Text(title)
                    .font(.ui(12, selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Palette.text : Palette.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// テーマの見本（小さなウィンドウ）
private struct ThemePreview: View {
    var appearance: Appearance

    var body: some View {
        switch appearance {
        case .light: MiniWindow(dark: false)
        case .dark: MiniWindow(dark: true)
        case .system:
            ZStack {
                MiniWindow(dark: false)
                MiniWindow(dark: true)
                    .mask(
                        GeometryReader { geo in
                            Path { p in
                                p.move(to: CGPoint(x: geo.size.width * 0.62, y: 0))
                                p.addLine(to: CGPoint(x: geo.size.width, y: 0))
                                p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                                p.addLine(to: CGPoint(x: geo.size.width * 0.38, y: geo.size.height))
                                p.closeSubpath()
                            }
                        }
                    )
            }
        }
    }
}

private struct MiniWindow: View {
    var dark: Bool
    var translucent = false

    var body: some View {
        let shell = Color(nsColor: NSColor(hex: dark ? 0x151618 : 0xf5f6f8))
        let panel = Color(nsColor: NSColor(hex: dark ? 0x1f2024 : 0xffffff))
        let line = dark ? Color.white.opacity(0.16) : Color.black.opacity(0.1)
        let strong = dark ? Color.white.opacity(0.32) : Color.black.opacity(0.22)
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 2.5) {
                    Circle().fill(Color(red: 1, green: 0.37, blue: 0.34))
                    Circle().fill(Color(red: 1, green: 0.74, blue: 0.18))
                    Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25))
                }
                .frame(height: 4)
                .padding(.bottom, 3)
                Capsule().fill(strong).frame(width: 18, height: 3)
                Capsule().fill(line).frame(width: 14, height: 3)
                Capsule().fill(line).frame(width: 16, height: 3)
                Capsule().fill(line).frame(width: 12, height: 3)
                Spacer()
            }
            .padding(5)
            .frame(width: 30)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(translucent ? Color.clear : shell)
            VStack(alignment: .leading, spacing: 4) {
                Capsule().fill(strong).frame(width: 24, height: 4)
                RoundedRectangle(cornerRadius: 2).fill(line).frame(height: 9)
                RoundedRectangle(cornerRadius: 2).fill(line).frame(height: 9)
                Spacer()
            }
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(panel))
            .padding([.top, .trailing, .bottom], 4)
        }
        .background(translucent ? Color.clear : shell)
    }
}

/// サイドバーの背景の見本。壁紙の上に小さなウィンドウを置く。
private struct MaterialPreview: View {
    var material: SidebarMaterial
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            LinearGradient(colors: [Color(red: 0.2, green: 0.45, blue: 0.95), Color(red: 0.45, green: 0.3, blue: 0.85), Color(red: 0.95, green: 0.55, blue: 0.7)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            switch material {
            case .transparent:
                ZStack {
                    Color(nsColor: NSColor(hex: dark ? 0x1d1e21 : 0xf4f5f7, alpha: dark ? 0.55 : 0.5))
                    MiniWindow(dark: dark, translucent: true)
                }
            case .tinted:
                MiniWindow(dark: dark)
            }
        }
    }
}

// MARK: - ショートカット

struct ShortcutSettingsPage: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var controller: DictationController
    @EnvironmentObject var status: SystemStatus
    @State private var recording: (Mode, Int?)?  // (操作, 置き換える位置。nil は追加)

    var body: some View {
        Page {
            PageHeader(title: t("ショートカット", "Shortcuts"),
                       subtitle: t("キーをクリックすると変更できます。1 つの操作に複数のショートカットを登録できます。", "Click a shortcut to change it. Each action can have several shortcuts."))

            if !status.hotkeysRunning {
                Callout(symbol: "exclamationmark.triangle.fill",
                        text: t("ショートカットを使うにはアクセシビリティの許可が必要です", "Accessibility permission is required for shortcuts")) {
                    Button(t("設定を開く", "Open Settings")) {
                        Permissions.requestAccessibility()
                        Permissions.openAccessibilitySettings()
                    }
                    .buttonStyle(.aside(compact: true))
                }
            }

            SettingsGroup {
                ForEach(Mode.allCases) { mode in
                    HStack(spacing: 14) {
                        IconTile(symbol: mode.symbol, tint: mode.tint, size: 30)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(mode.title).font(.ui(13.5, .medium)).foregroundStyle(Palette.text)
                            Text(description(mode)).font(.ui(12.5)).foregroundStyle(Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        shortcutList(mode)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                SettingRow(title: t("キャンセル", "Cancel"), subtitle: t("録音・処理を止め、回答カードを閉じます", "Stops recording or processing and closes the answer card"), symbol: nil) {
                    KeyCap(text: "Esc")
                }
            }

            SectionLabel(t("Fn（🌐）キー", "Fn (🌐) key"))
            SettingsGroup {
                SettingRow(title: t("「🌐キーを押して」を「何もしない」に", "Set “Press 🌐 key to” to “Do Nothing”"),
                           subtitle: t("Fn キーで音声入力するには、システム設定 > キーボード でこの設定が必要です。",
                                       "Required in System Settings > Keyboard to dictate with Fn.")) {
                    Button(t("キーボード設定", "Keyboard settings")) { Permissions.openKeyboardSettings() }
                        .buttonStyle(.aside)
                }
                SettingRow(title: t("ハンズフリーとプッシュトゥトーク", "Hands-free and push-to-talk"),
                           subtitle: t("ディクテーションのキーは、短く押すとハンズフリー（もう一度押して確定）、押し続けると離したときに確定します。押し続けている途中で Shift や Space を足すと翻訳・Ask に切り替わります。",
                                       "Tap the Dictate key for hands-free (press again to finish), or hold it and release to finish. While holding, add Shift or Space to switch to Translate or Ask."))
            }
        }
    }

    private func description(_ mode: Mode) -> String {
        switch mode {
        case .dictate: return t("話した内容を整えて入力", "Polish what you say and type it")
        case .translate: return t("話した内容を翻訳して入力", "Translate what you say and type it")
        case .ask: return t("選択テキストの書き換えや質問", "Rewrite a selection or ask a question")
        }
    }

    private func shortcutList(_ mode: Mode) -> some View {
        let list = settingsStore.settings.shortcuts(for: mode)
        return HStack(spacing: 6) {
            ForEach(Array(list.enumerated()), id: \.offset) { index, shortcut in
                ShortcutChip(recording: isRecording(mode, index), removable: index > 0) {
                    ShortcutKeys(shortcut: shortcut)
                } onTap: {
                    startRecording(mode, index)
                } onRemove: {
                    var l = list
                    l.remove(at: index)
                    settingsStore.settings.setShortcuts(l, for: mode)
                }
            }
            if isRecording(mode, nil) {
                ShortcutChip(recording: true, removable: false) { EmptyView() } onTap: {} onRemove: {}
            } else {
                IconButton(symbol: "plus", help: t("ショートカットを追加", "Add another shortcut")) { startRecording(mode, nil) }
            }
        }
    }

    private func isRecording(_ mode: Mode, _ index: Int?) -> Bool {
        guard let r = recording else { return false }
        return r.0 == mode && r.1 == index
    }

    private func startRecording(_ mode: Mode, _ index: Int?) {
        recording = (mode, index)
        controller.hotkeys.captureNextShortcut { shortcut in
            defer { recording = nil }
            guard let shortcut else { return }
            var list = settingsStore.settings.shortcuts(for: mode)
            if let index, list.indices.contains(index) {
                list[index] = shortcut
            } else if !list.contains(shortcut) {
                list.append(shortcut)
            }
            settingsStore.settings.setShortcuts(list, for: mode)
        }
    }
}

/// 登録済みのショートカット。クリックで録り直し、ホバーで削除ボタンを出す。
private struct ShortcutChip<Keys: View>: View {
    var recording: Bool
    var removable: Bool
    @ViewBuilder var keys: Keys
    var onTap: () -> Void
    var onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            Group {
                if recording {
                    HStack(spacing: 6) {
                        StatusDot(color: Palette.accent, pulsing: true)
                        Text(t("キーを押す…", "Press keys…"))
                    }
                    .font(.ui(12, .medium))
                    .foregroundStyle(Palette.accent)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.accent.opacity(0.1)))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.accent.opacity(0.4)))
                } else {
                    keys
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hovering ? Palette.hover : .clear))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(t("クリックして変更", "Click to change"))
        .overlay(alignment: .topTrailing) {
            if removable && hovering && !recording {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Palette.inverseText)
                        .frame(width: 14, height: 14)
                        .background(Circle().fill(Palette.textSecondary))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
                .help(t("削除", "Remove"))
                .transition(.scale.combined(with: .opacity))
            }
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

// MARK: - オーディオ

@MainActor
final class MicTester: ObservableObject {
    @Published var level: Float = 0
    @Published var running = false
    @Published var error: String?
    private let recorder = AudioRecorder()

    func toggle(deviceUID: String?) {
        if running {
            _ = recorder.stop()
            running = false
            level = 0
            return
        }
        recorder.onLevel = { [weak self] in self?.level = $0 }
        do {
            try recorder.start(deviceUID: deviceUID)
            running = true
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func stop() {
        if running { toggle(deviceUID: nil) }
    }
}

struct AudioSettingsPage: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @StateObject private var tester = MicTester()
    @State private var devices: [InputDevice] = []

    var body: some View {
        Page {
            PageHeader(title: t("オーディオ", "Audio"))

            SettingsGroup {
                SettingRow(title: t("マイク", "Microphone"), subtitle: t("音声入力に使うデバイス", "The input device used for dictation")) {
                    PopupPicker(selection: $settingsStore.settings.microphoneUID,
                                options: [String?.none] + devices.map { Optional($0.uid) },
                                title: deviceName, symbol: { _ in "mic" }, minWidth: 180)
                }
                SettingRow(title: t("マイクのテスト", "Test microphone"),
                           subtitle: tester.error ?? t("話しかけて入力レベルを確かめます", "Speak to check the input level")) {
                    HStack(spacing: 12) {
                        LevelBars(level: tester.level, active: tester.running)
                        Button(tester.running ? t("停止", "Stop") : t("テスト", "Test")) {
                            tester.toggle(deviceUID: settingsStore.settings.microphoneUID)
                        }
                        .buttonStyle(.aside(tester.running ? .primary : .secondary))
                    }
                }
            }
            .onAppear { devices = AudioDevices.inputDevices() }
            .onDisappear { tester.stop() }

            SectionLabel(t("サウンド", "Sounds"))
            SettingsGroup {
                ToggleRow(title: t("インタラクションサウンド", "Interaction sounds"),
                          subtitle: t("録音の開始・終了・キャンセルを音で知らせます", "Play a sound when recording starts, stops or is cancelled"),
                          isOn: $settingsStore.settings.interactionSounds)
                ToggleRow(title: t("音声入力中は他の音声をミュート", "Mute other audio while dictating"),
                          subtitle: t("音楽や動画の音を止めて、声を聞き取りやすくします", "Silence music and videos so your voice comes through"),
                          isOn: $settingsStore.settings.muteWhileDictating)
            }
        }
    }

    private func deviceName(_ uid: String?) -> String {
        guard let uid else {
            return t("自動検出", "Auto-detect") + (AudioDevices.defaultInputName().map { "（\($0)）" } ?? "")
        }
        return devices.first { $0.uid == uid }?.name ?? uid
    }
}

struct LevelBars: View {
    var level: Float
    var active = true

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<14, id: \.self) { i in
                let lit = active && Float(i) / 14 < level
                Capsule()
                    .fill(lit ? (i > 10 ? Palette.warning : Palette.accent) : Palette.meter)
                    .frame(width: 4, height: 6 + CGFloat(i) * 0.9)
            }
        }
        .frame(height: 20, alignment: .bottom)
        .animation(.linear(duration: 0.08), value: level)
    }
}

// MARK: - 言語

struct LanguageSettingsPage: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var appleLocales: [String] = []

    private var availableDictation: [String] {
        settingsStore.settings.sttProvider == .apple && !appleLocales.isEmpty ? appleLocales : Languages.dictation
    }

    var body: some View {
        Page {
            PageHeader(title: t("言語", "Languages"),
                       subtitle: t("話す言語と翻訳先を、使う順に並べます。", "List the languages you speak and translate into, in order of use."))

            SectionLabel(title: t("話す言語", "Languages you speak"),
                         subtitle: settingsStore.settings.sttProvider == .apple
                             ? t("Apple の音声認識は先頭の言語で認識します。録音中は音声バーで切り替えられます。", "Apple speech recognition uses the first language; switch it on the voice bar while recording.")
                             : t("クラウドの音声認識は言語を自動判定し、混在した発話にも対応します。", "Cloud recognition detects the language automatically, including mixed speech.")) {
                addMenu(options: availableDictation, existing: settingsStore.settings.dictationLanguages) {
                    settingsStore.settings.dictationLanguages.append($0)
                }
            }
            orderedList(\.dictationLanguages)
                .task(id: settingsStore.settings.sttProvider) {
                    appleLocales = await SpeechTranscriber.supportedLocales.map { $0.identifier(.bcp47) }.sorted { Languages.name($0) < Languages.name($1) }
                }

            SectionLabel(title: t("翻訳先", "Translation targets"),
                         subtitle: t("先頭が既定の翻訳先です。翻訳中に音声バーで切り替えられます。", "The first one is the default; switch on the voice bar while translating.")) {
                addMenu(options: Languages.translationTargets, existing: settingsStore.settings.translationTargets) {
                    settingsStore.settings.translationTargets.append($0)
                }
            }
            orderedList(\.translationTargets)
        }
    }

    private func addMenu(options: [String], existing: [String], add: @escaping (String) -> Void) -> some View {
        MenuButton(trailing: true, entries: {
            options.filter { !existing.contains($0) }.map { lang in .item(Languages.name(lang)) { add(lang) } }
        }) {
            Label(t("追加", "Add"), systemImage: "plus")
        }
        .buttonStyle(.aside(compact: true))
    }

    private func orderedList(_ keyPath: WritableKeyPath<AppSettings, [String]>) -> some View {
        let list = settingsStore.settings[keyPath: keyPath]
        return SettingsGroup {
            ForEach(Array(list.enumerated()), id: \.element) { index, lang in
                HStack(spacing: 12) {
                    Text("\(index + 1)")
                        .font(.ui(11.5, .medium).monospacedDigit())
                        .foregroundStyle(Palette.textTertiary)
                        .frame(width: 16)
                    Text(Languages.name(lang)).font(.ui(13.5, .medium)).foregroundStyle(Palette.text)
                    if index == 0 { Badge(text: t("既定", "Default")) }
                    Spacer()
                    HStack(spacing: 0) {
                        IconButton(symbol: "chevron.up", help: t("上へ", "Move up")) { move(keyPath, index, -1) }
                            .disabled(index == 0)
                        IconButton(symbol: "chevron.down", help: t("下へ", "Move down")) { move(keyPath, index, 1) }
                            .disabled(index == list.count - 1)
                        IconButton(symbol: "minus.circle", help: t("削除", "Remove")) {
                            settingsStore.settings[keyPath: keyPath].remove(at: index)
                        }
                        .disabled(list.count <= 1)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .frame(minHeight: 48)
            }
        }
    }

    private func move(_ keyPath: WritableKeyPath<AppSettings, [String]>, _ index: Int, _ delta: Int) {
        var list = settingsStore.settings[keyPath: keyPath]
        let j = index + delta
        guard list.indices.contains(j) else { return }
        list.swapAt(index, j)
        withAnimation(.smooth(duration: 0.25)) { settingsStore.settings[keyPath: keyPath] = list }
    }
}

// MARK: - AI エンジン

struct EngineSettingsPage: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var assetStatus: String?
    @State private var downloading = false
    @State private var testResult: (ok: Bool, text: String)?
    @State private var testing = false

    private var s: AppSettings { settingsStore.settings }

    var body: some View {
        Page {
            PageHeader(title: t("AI エンジン", "AI engines"),
                       subtitle: t("キーなしでも Apple のオンデバイスモデルで動きます。自分の API キー（BYOK）も使えます。", "Speak works with Apple's on-device models without a key, or with your own API keys (BYOK)."))

            SectionLabel(t("音声認識", "Speech recognition"))
            SettingsGroup {
                SettingRow(title: t("エンジン", "Engine"), subtitle: t("話した声を文字にします", "Turns your voice into text")) {
                    PopupPicker(selection: $settingsStore.settings.sttProvider, options: STTProvider.allCases, title: { $0.title }, minWidth: 180)
                }
                if s.sttProvider == .apple {
                    SettingRow(title: t("音声モデル", "Speech model"), subtitle: assetStatus ?? "…") {
                        HStack(spacing: 8) {
                            if downloading { ProgressView().controlSize(.small) }
                            Button(t("ダウンロード", "Download")) { downloadAssets() }
                                .buttonStyle(.aside)
                                .disabled(downloading)
                        }
                    }
                    .task(id: s.currentDictationLanguage) { await refreshAssetStatus() }
                } else {
                    let p = s.sttProvider
                    if let account = p.keyAccount {
                        SettingRow(title: t("API キー", "API key") + (p == .custom ? t("（任意）", " (optional)") : "")) {
                            APIKeyField(account: account)
                        }
                    }
                    SettingRow(title: t("モデル", "Model")) {
                        AsideTextField(placeholder: p.defaultModel, text: dictBinding(\.sttModels, p.rawValue)).frame(width: 260)
                    }
                    SettingRow(title: t("ベース URL", "Base URL")) {
                        AsideTextField(placeholder: p.defaultBaseURL, text: dictBinding(\.sttBaseURLs, p.rawValue)).frame(width: 260)
                    }
                }
            }

            SectionLabel(t("文章の整形・翻訳・Ask anything", "Cleanup, translation & Ask anything"))
            SettingsGroup {
                SettingRow(title: t("エンジン", "Engine"), subtitle: t("フィラーを除き、文章を整えます", "Removes fillers and polishes your writing")) {
                    PopupPicker(selection: $settingsStore.settings.llmProvider, options: LLMProvider.allCases, title: { $0.title }, minWidth: 180)
                }
                switch s.llmProvider {
                case .appleOnDevice:
                    let problem = AppleLLMEngine.onDeviceStatus
                    SettingRow(title: t("状態", "Status"),
                               subtitle: problem ?? t("この Mac 上で処理します。インターネットは不要です。", "Runs on this Mac, no internet needed.")) {
                        if problem != nil {
                            Button(t("Apple Intelligence の設定", "Apple Intelligence settings")) { Permissions.openAppleIntelligenceSettings() }
                                .buttonStyle(.aside)
                        } else {
                            Badge(text: t("利用可能", "Available"), tone: .success, symbol: "checkmark")
                        }
                    }
                case .claude:
                    SettingRow(title: "Anthropic API key") {
                        APIKeyField(account: "anthropic")
                    }
                    SettingRow(title: t("モデル", "Model")) {
                        PopupPicker(selection: $settingsStore.settings.claudeModel, options: ClaudeModel.allCases.map(\.rawValue),
                                    title: { raw in ClaudeModel(rawValue: raw)?.title ?? raw }, minWidth: 180)
                    }
                    ToggleRow(title: t("Ask anything で Web 検索を使う", "Use web search in Ask anything"),
                              subtitle: t("最新の情報が必要な質問に、検索結果を使って答えます", "Answers questions that need fresh information using search results"),
                              isOn: $settingsStore.settings.webSearch)
                case .openAICompatible:
                    let svc = s.compatService
                    SettingRow(title: t("サービス", "Service")) {
                        PopupPicker(selection: $settingsStore.settings.compatService, options: CompatService.allCases, title: { $0.title }, minWidth: 180)
                    }
                    SettingRow(title: t("API キー", "API key") + (svc.requiresKey ? "" : t("（任意）", " (optional)"))) {
                        APIKeyField(account: svc.keyAccount)
                    }
                    SettingRow(title: t("モデル", "Model"), subtitle: t("サービスで使えるモデル名に書き換えてください", "Use a model name your service offers")) {
                        AsideTextField(placeholder: svc.defaultModel, text: dictBinding(\.compatModels, svc.rawValue)).frame(width: 260)
                    }
                    SettingRow(title: t("ベース URL", "Base URL")) {
                        AsideTextField(placeholder: svc.defaultBaseURL, text: dictBinding(\.compatBaseURLs, svc.rawValue)).frame(width: 260)
                    }
                case .none:
                    SettingRow(title: t("簡易整形のみ", "Basic cleanup only"),
                               subtitle: t("フィラー除去などの簡易整形だけを行います。翻訳と Ask anything は使えません。", "Only basic filler removal. Translation and Ask anything are unavailable."))
                }
                SettingRow(title: t("接続をテスト", "Test connection"),
                           subtitle: testResult == nil ? t("短い例文を整形して、応答時間を確かめます", "Polishes a short sample and measures the response time") : nil) {
                    HStack(spacing: 8) {
                        if testing { ProgressView().controlSize(.small) }
                        Button(t("テスト", "Test")) { runTest() }
                            .buttonStyle(.aside)
                            .disabled(testing || s.llmProvider == .none)
                    }
                }
                if let testResult {
                    RowContent {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: testResult.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .foregroundStyle(testResult.ok ? Palette.success : Palette.danger)
                            Text(testResult.text)
                                .font(.ui(12.5))
                                .foregroundStyle(Palette.textSecondary)
                                .lineSpacing(2)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .background(Palette.hover.opacity(0.5))
                }
            }
            Footnote(text: t("API キーは macOS のキーチェーンに保存されます。音声とテキストは選んだサービスにだけ送られます。",
                             "API keys are stored in the macOS Keychain. Audio and text are sent only to the services you choose."),
                     symbol: "key")
        }
    }

    private func dictBinding(_ keyPath: WritableKeyPath<AppSettings, [String: String]>, _ key: String) -> Binding<String> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath][key] ?? "" },
            set: { settingsStore.settings[keyPath: keyPath][key] = $0.trimmingCharacters(in: .whitespaces) }
        )
    }

    private func refreshAssetStatus() async {
        let lang = s.currentDictationLanguage
        let status = await AppleTranscriber.assetStatus(locale: lang)
        let name = Languages.name(lang)
        switch status {
        case .installed: assetStatus = t("\(name) の音声モデル: インストール済み", "\(name) speech model: installed")
        case .downloading: assetStatus = t("\(name) の音声モデル: ダウンロード中", "\(name) speech model: downloading")
        case .supported: assetStatus = t("\(name) の音声モデル: 未ダウンロード（初回に自動で取得します）", "\(name) speech model: not downloaded yet (fetched on first use)")
        case .unsupported: assetStatus = t("\(name) は Apple の音声認識に対応していません", "\(name) is not supported by Apple speech recognition")
        @unknown default: assetStatus = nil
        }
    }

    private func downloadAssets() {
        downloading = true
        Task {
            _ = try? await AppleTranscriber.ensureAssets(locale: s.currentDictationLanguage)
            await refreshAssetStatus()
            downloading = false
        }
    }

    private func runTest() {
        guard let engine = LLMFactory.make(settings: s) else { return }
        testing = true
        testResult = nil
        let request = PolishRequest(
            transcript: L10n.current == .en ? "um so let's meet at three, no, four pm tomorrow" : "えーと、明日の会議は、あの、3時に、いや4時にしましょう",
            mode: .dictate, sourceLanguages: [s.currentDictationLanguage], targetLanguage: nil,
            appName: "Speak", category: .chat, styleDescription: AppCategory.chat.defaultStyleDescription,
            personalStyle: nil, vocabulary: [], corrections: []
        )
        Task {
            let start = Date()
            do {
                let out = try await engine.polish(request)
                withAnimation(.smooth) { testResult = (true, String(format: "%.1fs — ", Date().timeIntervalSince(start)) + out) }
            } catch {
                withAnimation(.smooth) { testResult = (false, error.localizedDescription) }
            }
            testing = false
        }
    }
}

/// キーチェーンに保存する API キーの入力欄
struct APIKeyField: View {
    var account: String
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var value = ""
    @State private var saved = false

    var body: some View {
        HStack(spacing: 8) {
            AsideTextField(placeholder: "sk-…", text: $value, secure: true, onSubmit: save)
                .frame(width: 200)
            if saved {
                Badge(text: t("保存済み", "Saved"), tone: .success, symbol: "checkmark")
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else {
                Button(t("保存", "Save"), action: save)
                    .buttonStyle(.aside)
                    .disabled(value.isEmpty)
            }
        }
        .animation(.smooth(duration: 0.2), value: saved)
        .onAppear {
            value = settingsStore.apiKey(account)
            saved = !value.isEmpty
        }
        .onChange(of: account) {
            value = settingsStore.apiKey(account)
            saved = !value.isEmpty
        }
        .onChange(of: value) {
            if value != settingsStore.apiKey(account) { saved = false }
        }
    }

    private func save() {
        settingsStore.setAPIKey(value, for: account)
        saved = !value.isEmpty
    }
}

// MARK: - プライバシー

struct PrivacySettingsPage: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var history: HistoryStore
    @State private var confirmDelete = false

    var body: some View {
        Page {
            PageHeader(title: t("プライバシー", "Privacy"),
                       subtitle: t("履歴・音声・辞書・学習した文体はすべてこの Mac の中に保存され、外部に送信されません。",
                                   "History, audio, dictionary and learned style are stored only on this Mac."))

            SettingsGroup {
                SettingRow(title: t("履歴の保存期間", "Keep history"), subtitle: t("期間を過ぎた履歴は自動で削除します", "Older history is deleted automatically")) {
                    PopupPicker(selection: $settingsStore.settings.historyRetention, options: Retention.allCases, title: { $0.title }, minWidth: 120)
                }
                ToggleRow(title: t("音声を保存する", "Save audio"),
                          subtitle: t("履歴からの再処理と音声のダウンロードに使います", "Used to retry and download recordings from History"),
                          isOn: $settingsStore.settings.keepAudio)
            }
            .onChange(of: settingsStore.settings.historyRetention) { _, new in
                history.prune(retention: new)
                if new == .never { history.deleteAll() }
            }

            SectionLabel(t("データ", "Data"))
            SettingsGroup {
                SettingRow(title: t("データフォルダ", "Data folder"), subtitle: Storage.root.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) {
                    Button(t("Finder で開く", "Show in Finder")) { NSWorkspace.shared.open(Storage.root) }
                        .buttonStyle(.aside)
                }
                SettingRow(title: t("すべてのデータを削除", "Delete all data"),
                           subtitle: t("履歴・音声・辞書・学習内容を削除します。元に戻せません。", "Deletes history, audio, dictionary and learned style. This cannot be undone.")) {
                    Button(t("削除…", "Delete…")) { confirmDelete = true }
                        .buttonStyle(.aside(.destructive))
                }
            }
            .confirmationDialog(t("履歴・音声・辞書・学習内容をすべて削除しますか？", "Delete all history, audio, dictionary and learned style?"), isPresented: $confirmDelete) {
                Button(t("すべて削除", "Delete everything"), role: .destructive) {
                    history.deleteAll()
                    for e in DictionaryStore.shared.entries { DictionaryStore.shared.delete(e) }
                    PersonalizationStore.shared.reset()
                }
            }
        }
    }
}
