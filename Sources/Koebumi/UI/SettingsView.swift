import AppKit
import Combine
import Speech
import SwiftUI

// MARK: - 一般

struct GeneralSettingsPage: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        Page {
            PageHeader(title: t("一般", "General"))

            SettingsGroup {
                TileRow(title: t("テーマ", "Theme"), subtitle: t("Koebumi の見た目を選びます", "Choose how Koebumi looks")) {
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
                TileRow(title: t("音声バー", "Voice bar"), subtitle: t("話しているときに画面の下に出るバーの色を選びます", "Choose the color of the bar shown while you speak")) {
                    ForEach(VoiceBarAppearance.allCases) { appearance in
                        ChoiceTile(title: appearance.title, selected: settingsStore.settings.voiceBarAppearance == appearance) {
                            settingsStore.settings.voiceBarAppearance = appearance
                        } preview: {
                            VoiceBarPreview(appearance: appearance)
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
                          subtitle: t("オフにするとメニューバーだけに表示します", "When off, Koebumi lives only in the menu bar"),
                          isOn: $settingsStore.settings.showInDock)
                ToggleRow(title: t("入力した結果をクリップボードにも残す", "Keep results in the clipboard"),
                          subtitle: t("貼り付けたあとも、結果をもう一度ペーストできます", "Paste the last result again after it is inserted"),
                          isOn: $settingsStore.settings.keepResultInClipboard)
            }

            if updater.isAvailable {
                SectionLabel(t("アップデート", "Updates"))
                SettingsGroup {
                    ToggleRow(title: t("自動でアップデートを確認", "Check for updates automatically"),
                              subtitle: t("1 日 1 回、GitHub で新しい版を確かめます", "Checks GitHub for a new version once a day"),
                              isOn: $updater.automaticallyChecks)
                    SettingRow(title: t("バージョン", "Version"), subtitle: Self.version) {
                        Button(t("今すぐ確認", "Check now")) { updater.checkForUpdates() }
                            .buttonStyle(.aside)
                    }
                }
            }
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
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
                            .strokeBorder(selected ? Palette.inverse : (hovering ? Palette.controlBorder : .clear), lineWidth: 2)
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
                MiniWindow(dark: true).mask(DiagonalHalf())
            }
        }
    }
}

/// 見本を斜めに分けた片側。右をダーク、左をライトで描いて並べる
private struct DiagonalHalf: Shape {
    var dark = true

    func path(in rect: CGRect) -> Path {
        // ライト側は境目から 2pt だけはみ出させ、上に重ねるダーク側との間に隙間を作らない
        let shift: CGFloat = dark ? 0 : 2
        let edge = dark ? rect.width : 0
        return Path { p in
            p.move(to: CGPoint(x: rect.width * 0.62 + shift, y: 0))
            p.addLine(to: CGPoint(x: edge, y: 0))
            p.addLine(to: CGPoint(x: edge, y: rect.height))
            p.addLine(to: CGPoint(x: rect.width * 0.38 + shift, y: rect.height))
            p.closeSubpath()
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
            PreviewWallpaper()
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

/// 音声バーの見本。壁紙の上に小さなバーを置く。テーマと同じは、テーマの見本のシステムと同じく斜めに白黒に分ける。
private struct VoiceBarPreview: View {
    var appearance: VoiceBarAppearance

    var body: some View {
        ZStack {
            PreviewWallpaper()
            switch appearance {
            case .light: MiniVoiceBar(dark: false)
            case .dark: MiniVoiceBar(dark: true)
            case .theme:
                // ライトのバーの縁がダークの端からのぞかないよう、ライトも境目で切る
                MiniVoiceBar(dark: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .mask(DiagonalHalf(dark: false))
                MiniVoiceBar(dark: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .mask(DiagonalHalf())
            }
        }
    }
}

private struct MiniVoiceBar: View {
    var dark: Bool

    var body: some View {
        let ink = dark ? Color.white : Color(nsColor: NSColor(hex: 0x0b0d12))
        HStack(spacing: 6) {
            Circle().fill(ink)
                .frame(width: 13, height: 13)
                .overlay(Image(systemName: "mic.fill").font(.system(size: 6.5, weight: .semibold)).foregroundStyle(dark ? Color.black : Color.white))
            HStack(spacing: 2.2) {
                ForEach(Array([3.0, 6, 9, 5, 7.5, 4, 2].enumerated()), id: \.offset) { _, height in
                    Capsule().fill(ink).frame(width: 1.6, height: height)
                }
            }
        }
        .padding(.leading, 3)
        .padding(.trailing, 10)
        .frame(height: 19)
        .background(Capsule().fill(dark ? Color(nsColor: NSColor(hex: 0x1b1c1f)) : Color.white))
        .overlay(Capsule().strokeBorder(Color.white.opacity(dark ? 0.18 : 0.6), lineWidth: 0.5))
    }
}

/// 見本の後ろに敷く壁紙
private struct PreviewWallpaper: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.2, green: 0.45, blue: 0.95), Color(red: 0.45, green: 0.3, blue: 0.85), Color(red: 0.95, green: 0.55, blue: 0.7)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - ショートカット

struct ShortcutSettingsPage: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var controller: DictationController
    @EnvironmentObject var status: SystemStatus
    @State private var recording: (ShortcutTarget, Int?)?  // (操作, 置き換える位置。nil は追加)

    var body: some View {
        Page {
            PageHeader(title: t("ショートカット", "Shortcuts"),
                       subtitle: t("キーをクリックすると変更できます。1 つの操作に複数のショートカットを登録できます。", "Click a shortcut to change it. Each action can have several shortcuts."))

            if !status.hotkeysRunning {
                Callout(symbol: "exclamationmark",
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
                    // 音声バーの左の丸と同じアイコンにする
                    actionRow(symbol: mode.symbol, title: mode.title, description: description(mode), target: .mode(mode))
                }
                actionRow(symbol: "doc.on.clipboard", title: t("最後の結果を貼り付け", "Paste last result"),
                          description: t("直前の結果を、もう一度カーソル位置に入力します", "Type the most recent result again at the cursor"),
                          target: .pasteLast)
                actionRow(symbol: "arrow.uturn.backward", title: t("AI の整形を元に戻す", "Revert AI cleanup"),
                          description: t("直前に入力した文を、AI で整える前の文に置き換えます。もう一度押すと、AI で整えた文に戻ります",
                                         "Replace the text you just dictated with the version before AI cleanup. Press again to restore it"),
                          target: .revertLast)
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

    private func actionRow(symbol: String, title: String, description: String, target: ShortcutTarget) -> some View {
        HStack(spacing: 14) {
            SymbolBadge(symbol: symbol)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.ui(13.5, .medium)).foregroundStyle(Palette.text)
                Text(description).font(.ui(12.5)).foregroundStyle(Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            shortcutList(target)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func shortcutList(_ target: ShortcutTarget) -> some View {
        let list = shortcuts(target)
        return HStack(spacing: 6) {
            ForEach(Array(list.enumerated()), id: \.offset) { index, shortcut in
                // 録音の操作は 1 つ残す。貼り付けと取り消しは、すべて消して使わないようにできる
                ShortcutChip(recording: isRecording(target, index), removable: index > 0 || target == .pasteLast || target == .revertLast) {
                    ShortcutKeys(shortcut: shortcut)
                } onTap: {
                    startRecording(target, index)
                } onRemove: {
                    var l = list
                    l.remove(at: index)
                    setShortcuts(l, for: target)
                }
            }
            if isRecording(target, nil) {
                ShortcutChip(recording: true, removable: false) { EmptyView() } onTap: {} onRemove: {}
            } else {
                IconButton(symbol: "plus", help: t("ショートカットを追加", "Add another shortcut")) { startRecording(target, nil) }
            }
        }
    }

    private func shortcuts(_ target: ShortcutTarget) -> [Shortcut] {
        switch target {
        case .mode(let mode): return settingsStore.settings.shortcuts(for: mode)
        case .pasteLast: return settingsStore.settings.pasteLastShortcuts
        case .revertLast: return settingsStore.settings.revertLastShortcuts
        }
    }

    private func setShortcuts(_ list: [Shortcut], for target: ShortcutTarget) {
        switch target {
        case .mode(let mode): settingsStore.settings.setShortcuts(list, for: mode)
        case .pasteLast: settingsStore.settings.pasteLastShortcuts = list
        case .revertLast: settingsStore.settings.revertLastShortcuts = list
        }
    }

    private func isRecording(_ target: ShortcutTarget, _ index: Int?) -> Bool {
        guard let r = recording else { return false }
        return r.0 == target && r.1 == index
    }

    private func startRecording(_ target: ShortcutTarget, _ index: Int?) {
        recording = (target, index)
        controller.hotkeys.captureNextShortcut { shortcut in
            defer { recording = nil }
            guard let shortcut else { return }
            var list = shortcuts(target)
            if let index, list.indices.contains(index) {
                list[index] = shortcut
            } else if !list.contains(shortcut) {
                list.append(shortcut)
            }
            setShortcuts(list, for: target)
        }
    }
}

/// ショートカットを登録できる操作
private enum ShortcutTarget: Equatable {
    case mode(Mode)
    case pasteLast
    case revertLast
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
                        StatusDot(color: Palette.inverse, pulsing: true)
                        Text(t("キーを押す…", "Press keys…"))
                    }
                    .font(.ui(12, .medium))
                    .foregroundStyle(Palette.text)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.hover))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.inverse.opacity(0.5)))
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
            let name = AudioDevices.automaticInput()?.name ?? AudioDevices.defaultInputName()
            return t("自動検出", "Auto-detect") + (name.map { "（\($0)）" } ?? "")
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
                    .fill(lit ? Palette.inverse : Palette.meter)
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
                         subtitle: settingsStore.settings.sttNeedsFixedLanguage
                             ? t("\(settingsStore.settings.sttName) は先頭の言語で認識します。録音中は音声バーで切り替えられます。", "\(settingsStore.settings.sttName) uses the first language; switch it on the voice bar while recording.")
                             : t("\(settingsStore.settings.sttName) は話した言語を自動で判定します。", "\(settingsStore.settings.sttName) detects the spoken language automatically.")) {
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
                    if index == 0 { Badge(text: t("既定", "Default"), tone: .neutral) }
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
                       subtitle: t("キーなしでも Apple のオンデバイスモデルで動きます。自分の API キー（BYOK）や、Claude・ChatGPT のサブスクも使えます。",
                                   "Koebumi works with Apple's on-device models without a key, with your own API keys (BYOK), or with your Claude or ChatGPT subscription."))

            SpeechEngineList { choice in
                switch choice {
                case .apple:
                    SettingRow(title: t("音声モデル", "Speech model"), subtitle: assetStatus ?? "…") {
                        HStack(spacing: 8) {
                            if downloading { ProgressView().controlSize(.small) }
                            Button(t("ダウンロード", "Download")) { downloadAssets() }
                                .buttonStyle(.aside)
                                .disabled(downloading)
                        }
                    }
                    .padding(.leading, 30)
                    .task(id: s.currentDictationLanguage) { await refreshAssetStatus() }
                case .local:
                    EmptyView()
                case .cloud(let p):
                    Group {
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
                    .padding(.leading, 30)
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
                            Badge(text: t("利用可能", "Available"), tone: .neutral, symbol: "checkmark")
                        }
                    }
                case .claude:
                    SettingRow(title: "Anthropic API key",
                               subtitle: t("Claude Max・Team プランには毎月 API クレジットが付きます。claude.ai の設定 > Billing の API credits で Console の組織をつなぎ、その組織で作ったキーを入れると、クレジットから払えます。",
                                           "Claude Max and Team plans include monthly API credits. Link a Console organization under API credits in claude.ai Settings > Billing, then enter a key from that organization.")) {
                        APIKeyField(account: "anthropic")
                    }
                    SettingRow(title: t("モデル", "Model")) {
                        PopupPicker(selection: $settingsStore.settings.claudeModel, options: ClaudeModel.allCases.map(\.rawValue),
                                    title: { raw in ClaudeModel(rawValue: raw)?.title ?? raw }, minWidth: 180)
                    }
                    ToggleRow(title: t("Ask anything で Web 検索を使う", "Use web search in Ask anything"),
                              subtitle: t("最新の情報が必要な質問に、検索結果を使って答えます", "Answers questions that need fresh information using search results"),
                              isOn: $settingsStore.settings.webSearch)
                case .claudeCode:
                    ClaudeCodeSettingsRows(model: $settingsStore.settings.claudeModel)
                case .codex:
                    CodexSettingsRows(model: $settingsStore.settings.codexModel)
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
                        HStack(alignment: .top, spacing: 8) {
                            SymbolBadge(symbol: testResult.ok ? "checkmark" : "exclamationmark", size: 16)
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
            appName: "Koebumi", category: .chat, styleDescription: AppCategory.chat.defaultStyleDescription,
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

/// サブスクで動かすエンジン（Claude Code・Codex）のログイン状態の行
private struct SubscriptionStatusRow: View {
    var status: SubscriptionStatus?
    var checking: Bool
    var reload: () -> Void

    var body: some View {
        SettingRow(title: t("状態", "Status"), subtitle: status?.detail ?? t("確認しています…", "Checking…")) {
            HStack(spacing: 8) {
                if checking {
                    ProgressView().controlSize(.small)
                } else if let status {
                    if status.isReady {
                        Badge(text: t("ログイン済み", "Signed in"), tone: .neutral, symbol: "checkmark")
                    } else {
                        Badge(text: t("使えません", "Unavailable"), tone: .warning, symbol: "exclamationmark")
                    }
                }
                Button(t("再確認", "Check again"), action: reload)
                    .buttonStyle(.aside)
                    .disabled(checking)
            }
        }
    }
}

/// Claude のサブスク（Claude Code 経由）の設定
private struct ClaudeCodeSettingsRows: View {
    @Binding var model: String
    @State private var status: SubscriptionStatus?
    @State private var checking = false

    var body: some View {
        SubscriptionStatusRow(status: status, checking: checking) { Task { await reload() } }
            .task { await reload() }
        SettingRow(title: t("モデル", "Model"),
                   subtitle: t("Haiku が最速です（1 回 2〜3 秒）。Sonnet・Opus は遅くなり、利用枠も多く使います", "Haiku is fastest (2–3 s per request). Sonnet and Opus are slower and use more of your limits")) {
            PopupPicker(selection: $model, options: ClaudeModel.allCases.map(\.rawValue),
                        title: { raw in ClaudeModel(rawValue: raw)?.title ?? raw }, minWidth: 180)
        }
    }

    private func reload() async {
        checking = true
        status = await ClaudeCodeEngine.status()
        checking = false
    }
}

/// ChatGPT のサブスク（Codex 経由）の設定。選べるモデルは Codex に聞く
private struct CodexSettingsRows: View {
    @Binding var model: String
    @State private var status: SubscriptionStatus?
    @State private var models: [CodexAppServer.Model] = []
    @State private var checking = false

    var body: some View {
        SubscriptionStatusRow(status: status, checking: checking) { Task { await reload() } }
            .task { await reload() }
        SettingRow(title: t("モデル", "Model"),
                   subtitle: t("小さいモデルほど速く返ります（1 回 3〜6 秒）", "Smaller models respond faster (3–6 s per request)")) {
            PopupPicker(selection: $model, options: options, title: title, minWidth: 180)
        }
    }

    /// 一覧にないモデルを選んでいたら、それも残す（Codex を確かめる前や、モデルが外されたとき）
    private var options: [String] {
        let ids = models.map(\.id)
        return [""] + ids + (model.isEmpty || ids.contains(model) ? [] : [model])
    }

    private func title(_ id: String) -> String {
        if id.isEmpty { return t("Codex の既定", "Codex default") }
        return models.first { $0.id == id }?.name ?? id
    }

    private func reload() async {
        checking = true
        (status, models) = await CodexAppServer.shared.status()
        checking = false
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
                Badge(text: t("保存済み", "Saved"), tone: .neutral, symbol: "checkmark")
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

            SectionLabel(t("画面の文脈", "Screen context"))
            SettingsGroup {
                SettingRow(title: t("入力欄と画面の文章を読む", "Read the text field and window"),
                           subtitle: t("カーソルの前後と、同じウィンドウに表示されている文章を読み、人名の表記（渡辺さん → 渡邉さん）や文のつながりを合わせます。AI に渡すのは拾った人名・用語だけで、文章そのものは渡しません。読んだ内容は保存せず、パスワード欄は読みません。",
                                       "Reads around the cursor and the text in the same window to spell names the way they appear and to continue your sentence. Only the names and terms it finds are given to the AI, never the text itself. Nothing is saved, and password fields are never read.")) {
                    PopupPicker(selection: $settingsStore.settings.contextAwareness, options: ContextAwareness.allCases,
                                title: { $0.title }, minWidth: 210)
                }
                if let note = contextNote {
                    RowContent {
                        Label(note, systemImage: "info.circle")
                            .font(.ui(12))
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
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

    /// いまのエンジンで、読んだ文章がどこまで使われるか
    private var contextNote: String? {
        let s = settingsStore.settings
        guard s.contextAwareness == .localOnly, !s.shareSurroundingWithLLM else { return nil }
        return t("いまの文章整形エンジンはクラウドで処理するため、画面の人名・用語は送りません。人名の表記やつなぎ方の調整など、この Mac の中の処理にだけ使います。",
                 "Your cleanup engine runs in the cloud, so names and terms from the screen are not sent. They are only used on this Mac, for example to fix name spellings and spacing.")
    }
}
