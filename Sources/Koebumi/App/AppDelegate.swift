import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var controller: DictationController!
    private var voiceBar: VoiceBarController!
    private var answerCard: AnswerCardController!
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private var cancellables: Set<AnyCancellable> = []
    private var permissionTimer: Timer?
    private var pruneTimer: Timer?

    private var settingsStore: SettingsStore { .shared }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Speak という名前だったころのデータと API キーを引き継ぐ。設定を読む前に写す
        if Storage.migrateFromSpeak() { Keychain.migrateLegacy() }
        // Dock に出さない設定なら、起動した直後にも一瞬アイコンが出ないようにする
        updateDockIcon(settingsStore.settings.showInDock)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = DictationController()
        voiceBar = VoiceBarController(controller: controller)
        answerCard = AnswerCardController(controller: controller)

        // 新しい版を確かめ始める（配布用に作ったアプリのときだけ）
        _ = Updater.shared
        setupStatusItem()
        setupMainMenu()

        settingsStore.$settings
            .receive(on: RunLoop.main)
            .sink { [weak self] s in self?.apply(s) }
            .store(in: &cancellables)

        controller.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in self?.updateStatusIcon(phase) }
            .store(in: &cancellables)

        startHotkeys()
        // エージェントが CLI で辞書に足した語を、すぐ使えるようにする
        DictionaryStore.shared.observeOtherProcesses()
        DictionarySkill.refreshIfInstalled(executable: DictionaryCommand.executablePath)
        LoginItem.registerIfNeeded(settingsStore.settings.launchAtLogin)
        HistoryStore.shared.prune(retention: settingsStore.settings.historyRetention)
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            MainActor.assumeIsolated {
                HistoryStore.shared.prune(retention: SettingsStore.shared.settings.historyRetention)
            }
        }

        if !settingsStore.settings.onboardingCompleted || !Permissions.accessibilityGranted || !Permissions.microphoneGranted {
            showMainWindow()
            Navigation.shared.showOnboarding = true
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: - ショートカット

    private func startHotkeys() {
        controller.hotkeys.updateBindings(settingsStore.settings)
        if controller.hotkeys.start() { return }
        // アクセシビリティが許可されるまで待つ
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, Permissions.accessibilityGranted else { return }
                if self.controller.hotkeys.start() {
                    timer.invalidate()
                    self.permissionTimer = nil
                }
            }
        }
    }

    private func apply(_ s: AppSettings) {
        controller.hotkeys.updateBindings(s)
        // この Mac のモデルを選んでいれば起動時から読み込んでおき、最初の録音で待たせない
        LocalSpeechRuntime.shared.keepLoaded(s.sttProvider == .local ? s.localSpeechModel : nil)
        switch s.appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        updateDockIcon(s.showInDock)
        rebuildMenu()
    }

    /// Dock のアイコンを設定に合わせる。ウィンドウを開いている間も設定どおりにする
    private func updateDockIcon(_ show: Bool) {
        let policy: NSApplication.ActivationPolicy = show ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        // 切り替えると Koebumi が前面から外れ、ウィンドウが他のアプリの後ろに回るので、開いていれば前に戻す
        guard let window, window.isVisible else { return }
        DispatchQueue.main.async {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - メインウィンドウ

    @objc func showMainWindow() {
        if window == nil {
            let w = Self.makeMainWindow(controller: controller)
            w.center()
            w.setFrameAutosaveName("KoebumiMainWindow")
            w.isReleasedWhenClosed = false
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// メインウィンドウ。`--snapshot` でも同じ設定のものを使う。
    static func makeMainWindow(controller: DictationController, snapshot: Bool = false) -> NSWindow {
        let root = MainView()
            .environmentObject(SettingsStore.shared)
            .environmentObject(HistoryStore.shared)
            .environmentObject(DictionaryStore.shared)
            .environmentObject(PersonalizationStore.shared)
            .environmentObject(StatsStore.shared)
            .environmentObject(Navigation.shared)
            .environmentObject(controller)
            .environment(\.isSnapshot, snapshot)
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        w.title = "Koebumi"
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.titlebarSeparatorStyle = .none
        // 空のツールバーでタイトルバーを 40pt にし、信号ボタンをサイドバー上端の中央に置く
        w.toolbar = NSToolbar(identifier: "KoebumiMain")
        w.toolbarStyle = .unifiedCompact
        w.contentViewController = NSHostingController(rootView: root)
        // 開いたときにサイドバーの検索欄へフォーカスが入らないようにする（⌘K で入る）
        w.initialFirstResponder = w.contentView
        w.setContentSize(NSSize(width: 1100, height: 740))
        w.minSize = NSSize(width: 900, height: 600)
        return w
    }

    private func show(_ item: SidebarItem) {
        Navigation.shared.selection = item
        showMainWindow()
    }

    // MARK: - メニューバー

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon(.idle)
        rebuildMenu()
    }

    private func updateStatusIcon(_ phase: DictationController.Phase) {
        // 話している間だけくちばしを大きく開け、それ以外（待機中・処理中）は閉じる
        statusItem.button?.image = KoebumiMark.menuBarImage(mouth: phase == .recording ? .wideOpen : .closed)
    }

    private func rebuildMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()
        menu.delegate = self
        let s = settingsStore.settings
        for mode in Mode.allCases {
            let shortcut = s.shortcuts(for: mode).first?.display ?? ""
            let item = NSMenuItem(title: "\(mode.title)  \(shortcut)", action: #selector(menuStart(_:)), keyEquivalent: "")
            item.representedObject = mode.rawValue
            item.target = self
            item.image = NSImage(systemSymbolName: mode.symbol, accessibilityDescription: nil)
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let pasteShortcut = s.pasteLastShortcuts.first.map { "  \($0.display)" } ?? ""
        let paste = NSMenuItem(title: t("最後の結果を貼り付け", "Paste last result") + pasteShortcut, action: #selector(pasteLast), keyEquivalent: "")
        paste.target = self
        menu.addItem(paste)
        let revertShortcut = s.revertLastShortcuts.first.map { "  \($0.display)" } ?? ""
        let revert = NSMenuItem(title: t("AI の整形を元に戻す", "Revert AI cleanup") + revertShortcut, action: #selector(revertLast), keyEquivalent: "")
        revert.target = self
        menu.addItem(revert)
        menu.addItem(.separator())
        for (title, item) in [(t("ホーム", "Home"), SidebarItem.home), (t("履歴", "History"), .history),
                              (t("辞書", "Dictionary"), .dictionary), (t("設定…", "Settings…"), .settings)] {
            let mi = NSMenuItem(title: title, action: #selector(menuShow(_:)), keyEquivalent: item == .settings ? "," : "")
            mi.representedObject = item.rawValue
            mi.target = self
            menu.addItem(mi)
        }
        menu.addItem(.separator())
        if Updater.shared.isAvailable {
            let update = NSMenuItem(title: t("アップデートを確認…", "Check for Updates…"), action: #selector(checkForUpdates), keyEquivalent: "")
            update.target = self
            menu.addItem(update)
        }
        menu.addItem(NSMenuItem(title: t("Koebumi を終了", "Quit Koebumi"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func checkForUpdates() {
        Updater.shared.checkForUpdates()
    }

    @objc private func menuStart(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = Mode(rawValue: raw) else { return }
        if controller.phase == .recording {
            controller.finish()
        } else {
            // メニューを閉じて元のアプリにフォーカスが戻ってから開始する
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.controller.begin(mode) }
        }
    }

    @objc private func pasteLast() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.controller.pasteLastResult() }
    }

    @objc private func revertLast() {
        // メニューを閉じて、入力先のアプリにフォーカスが戻ってから置き換える
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.controller.revertLast() }
    }

    @objc private func menuShow(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let item = SidebarItem(rawValue: raw) else { return }
        show(item)
    }

    /// 標準のアプリメニュー（コピー＆ペーストなどのショートカットを効かせるため）
    private func setupMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: t("Koebumi について", "About Koebumi"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        if Updater.shared.isAvailable {
            let update = NSMenuItem(title: t("アップデートを確認…", "Check for Updates…"), action: #selector(checkForUpdates), keyEquivalent: "")
            update.target = self
            appMenu.addItem(update)
        }
        appMenu.addItem(.separator())
        let settingsItem = NSMenuItem(title: t("設定…", "Settings…"), action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: t("Koebumi を隠す", "Hide Koebumi"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: t("Koebumi を終了", "Quit Koebumi"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: t("編集", "Edit"))
        edit.addItem(NSMenuItem(title: t("取り消す", "Undo"), action: Selector(("undo:")), keyEquivalent: "z"))
        edit.addItem(NSMenuItem(title: t("やり直す", "Redo"), action: Selector(("redo:")), keyEquivalent: "Z"))
        edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: t("カット", "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: t("コピー", "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: t("ペースト", "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: t("すべてを選択", "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: t("ウインドウ", "Window"))
        windowMenu.addItem(NSMenuItem(title: t("閉じる", "Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowMenu.addItem(NSMenuItem(title: t("しまう", "Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.mainMenu = main
    }

    @objc private func openSettingsFromMenu() { show(.settings) }
}
