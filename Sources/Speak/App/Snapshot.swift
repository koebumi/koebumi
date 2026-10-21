import AppKit
import SwiftUI

/// 開発用: `Speak --snapshot <出力フォルダ>` で各画面を PNG に書き出す（画面収録の許可なしで UI を確認できる）
@MainActor
enum Snapshot {
    static func run(_ args: [String]) async -> Int32 {
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return 2 }
        let dir = URL(fileURLWithPath: args[i + 1])
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let controller = DictationController()
        if args.contains("--en") { L10n.current = .en }
        let width = args.firstIndex(of: "--width").flatMap { $0 + 1 < args.count ? Double(args[$0 + 1]) : nil } ?? 1100

        func render<V: View>(_ view: V, _ name: String, size: NSSize, titled: Bool = false) async {
            let hosting = NSHostingView(rootView: view.environment(\.isSnapshot, true))
            hosting.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: hosting.frame, styleMask: titled ? [.titled, .fullSizeContentView] : [.borderless], backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.contentView = hosting
            window.appearance = NSAppearance(named: args.contains("--dark") ? .darkAqua : .aqua)
            window.orderBack(nil)
            try? await Task.sleep(for: .milliseconds(900))
            hosting.layoutSubtreeIfNeeded()
            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
            window.orderOut(nil)
        }

        func renderVoiceBar() async {
            let states: [(String, DictationController.Phase, Mode)] = [
                ("voicebar-dictate", .recording, .dictate),
                ("voicebar-translate", .recording, .translate),
                ("voicebar-ask", .recording, .ask),
                ("voicebar-processing", .processing, .ask),
                ("voicebar-error", .message(t("API キーが無効です (401)", "The API key was rejected (401)"), isError: true), .dictate),
            ]
            for (name, phase, mode) in states {
                controller.setPreviewState(phase, mode: mode)
                await render(VoiceBarView(controller: controller, settings: SettingsStore.shared).padding(24).frame(width: 560, height: 96).background(SnapshotWallpaper()), name, size: NSSize(width: 560, height: 96))
            }
        }

        let only = args.firstIndex(of: "--only").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        if only == "voicebar" {
            await renderVoiceBar()
            return 0
        }
        for item in SidebarItem.allCases where only == nil || only == item.rawValue {
            Navigation.shared.selection = item
            Navigation.shared.showOnboarding = false
            let view = MainView()
                .environmentObject(SettingsStore.shared)
                .environmentObject(HistoryStore.shared)
                .environmentObject(DictionaryStore.shared)
                .environmentObject(PersonalizationStore.shared)
                .environmentObject(StatsStore.shared)
                .environmentObject(Navigation.shared)
                .environmentObject(controller)
            await render(view, item.rawValue, size: NSSize(width: width, height: args.contains("--tall") ? 1500 : 760), titled: true)
        }
        // 本物と同じウィンドウを枠ごと描く（信号ボタンとタイトルバーの位置を確かめる）
        Navigation.shared.selection = .general
        let window = AppDelegate.makeMainWindow(controller: controller, snapshot: true)
        window.appearance = NSAppearance(named: args.contains("--dark") ? .darkAqua : .aqua)
        window.orderBack(nil)
        try? await Task.sleep(for: .milliseconds(900))
        if let frameView = window.contentView?.superview,
           let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) {
            frameView.cacheDisplay(in: frameView.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("window.png"))
        }
        window.orderOut(nil)
        if only != nil { return 0 }
        let onboarding = OnboardingView()
            .environmentObject(SettingsStore.shared)
            .environmentObject(controller)
        await render(onboarding, "onboarding", size: NSSize(width: 600, height: 760))
        let sample = HistoryItem(mode: .dictate, rawTranscript: "えーと明日の会議は3時にいや4時に", output: "明日の会議は4時にしてください。", appName: "Slack")
        let feedback = FeedbackSheet(item: sample)
            .environmentObject(HistoryStore.shared)
            .environmentObject(DictionaryStore.shared)
            .environmentObject(PersonalizationStore.shared)
        await render(feedback, "sheet-feedback", size: NSSize(width: 540, height: 420))
        let report = PersonalizationReportView().environmentObject(PersonalizationStore.shared)
        await render(report, "sheet-report", size: NSSize(width: 540, height: 520))
        await renderVoiceBar()
        controller.answer = AnswerCardContent(question: "富士山の高さはどれくらい", answer: "富士山の標高は **3,776 m** です。日本で最も高い山で、山梨県と静岡県にまたがっています。")
        let card = FirstMouseHostingView(rootView: AnswerCardView(controller: controller))
        card.layoutSubtreeIfNeeded()
        await render(AnswerCardView(controller: controller).padding(30).background(SnapshotWallpaper()), "answer-card", size: NSSize(width: 520, height: max(200, card.fittingSize.height + 60)))
        print("snapshots written to \(dir.path)")
        return 0
    }
}
