import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private var controller: DictationController!
    private var voiceBar: VoiceBarController!
    private var answerCard: AnswerCardController!
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private var cancellables: Set<AnyCancellable> = []
    private var permissionTimer: Timer?
    private var pruneTimer: Timer?

    private var settingsStore: SettingsStore { .shared }

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = DictationController()
        voiceBar = VoiceBarController(controller: controller)
        answerCard = AnswerCardController(controller: controller)

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
        switch s.appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        let policy: NSApplication.ActivationPolicy = s.showInDock || window?.isVisible == true ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
        rebuildMenu()
    }

    // MARK: - メインウィンドウ

    @objc func showMainWindow() {
        if window == nil {
            let w = Self.makeMainWindow(controller: controller)
            w.center()
            w.setFrameAutosaveName("SpeakMainWindow")
            w.isReleasedWhenClosed = false
            w.delegate = self
            window = w
        }
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
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
        w.title = "Speak"
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.titlebarSeparatorStyle = .none
        // 空のツールバーでタイトルバーを 40pt にし、信号ボタンをサイドバー上端の中央に置く
        w.toolbar = NSToolbar(identifier: "SpeakMain")
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

    func windowWillClose(_ notification: Notification) {
        if !settingsStore.settings.showInDock {
            DispatchQueue.main.async { NSApp.setActivationPolicy(.accessory) }
        }
    }

    // MARK: - メニューバー

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon(.idle)
        rebuildMenu()
    }

    private func updateStatusIcon(_ phase: DictationController.Phase) {
        let symbol: String
        switch phase {
        case .recording: symbol = "waveform.circle.fill"
        case .processing: symbol = "ellipsis.circle"
        default: symbol = "waveform"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Speak")
        image?.isTemplate = true
        statusItem.button?.image = image
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
        let paste = NSMenuItem(title: t("最後の結果を貼り付け", "Paste last result"), action: #selector(pasteLast), keyEquivalent: "")
        paste.target = self
        menu.addItem(paste)
        menu.addItem(.separator())
        for (title, item) in [(t("ホーム", "Home"), SidebarItem.home), (t("履歴", "History"), .history),
                              (t("辞書", "Dictionary"), .dictionary), (t("設定…", "Settings…"), .settings)] {
            let mi = NSMenuItem(title: title, action: #selector(menuShow(_:)), keyEquivalent: item == .settings ? "," : "")
            mi.representedObject = item.rawValue
            mi.target = self
            menu.addItem(mi)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: t("Speak を終了", "Quit Speak"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
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

    @objc private func menuShow(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let item = SidebarItem(rawValue: raw) else { return }
        show(item)
    }

    /// 標準のアプリメニュー（コピー＆ペーストなどのショートカットを効かせるため）
    private func setupMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: t("Speak について", "About Speak"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        let settingsItem = NSMenuItem(title: t("設定…", "Settings…"), action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: t("Speak を隠す", "Hide Speak"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: t("Speak を終了", "Quit Speak"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
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
