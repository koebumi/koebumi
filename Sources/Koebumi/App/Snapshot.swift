import AppKit
import SwiftUI

/// 開発用: `Koebumi --snapshot <出力フォルダ>` で各画面を PNG に書き出す（画面収録の許可なしで UI を確認できる）
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
                await render(VoiceBarView(controller: controller, settings: SettingsStore.shared).padding(24 - VoiceBarView.margin).frame(width: 560, height: 96).background(SnapshotWallpaper()), name, size: NSSize(width: 560, height: 96))
            }
            // この Mac のモデルで、録音中に書き起こした内容をバーの上に出す。札の光は、決まった時点で止めて描く
            let short = t("明日の会議は3時から", "Let's move tomorrow's meeting")
            let longer = t("明日の会議は3時からでお願いします", "Let's move tomorrow's meeting to three")
            let long = t("えーと、明日の会議なんですけど、資料はまだできていないので、先に議題だけ共有しておきます。それと、来週の打ち合わせの日程も決めたいので、候補を3つくらい出してもらえますか",
                         "So about tomorrow's meeting, the slides aren't ready yet, so I'll share the agenda first. Also, could you send me three possible times for next week's sync")
            let start = Date(timeIntervalSinceReferenceDate: 0)
            // 1 秒おきに届いたことにする
            func live(_ events: [LiveTranscriptEvent]) -> LiveTranscript {
                var live = LiveTranscript()
                for (i, event) in events.enumerated() { live.receive(event, at: start + Double(i)) }
                return live
            }
            // 名前、録音中か処理中か、届いたもの、最後に届いてから何秒後を描くか
            let partials: [(String, DictationController.Phase, LiveTranscript, TimeInterval)] = [
                ("voicebar-partial", .recording, live([.partial(short)]), 2),
                ("voicebar-partial-long", .recording, live([.partial(long)]), 2),
                // 書き起こしを始めて、末尾を虹が通っているところと、2 回通って薄いまま待っているところ
                ("voicebar-live-transcribing", .recording, live([.partial(short), .transcribing]), 0.2),
                ("voicebar-live-waiting", .recording, live([.partial(long), .transcribing]), 1.5),
                // 届いた字を虹がなでているところ
                ("voicebar-live-arrived", .recording, live([.partial(short), .transcribing, .partial(longer)]), 0.3),
                // 話し終えて、AI で整えている間に全文に虹を流しているところ
                ("voicebar-live-polishing", .processing, live([.partial(short), .transcribing, .final(longer)]), 1.5),
            ]
            for (name, phase, live, after) in partials {
                controller.setPreviewState(phase, mode: .dictate, live: live)
                let last = [live.arrivedAt, live.transcribingSince, live.finalAt].compactMap { $0 }.max() ?? start
                let now = last + after
                await render(VoiceBarView(controller: controller, settings: SettingsStore.shared).environment(\.liveTextNow, now).padding(24 - VoiceBarView.margin).frame(width: 560, height: 150).background(SnapshotWallpaper()), name, size: NSSize(width: 560, height: 150))
            }
            controller.setPreviewState(.idle, mode: .dictate)
        }

        /// 定型文のシートと、履歴の AI の変更の表示
        func renderMail() async {
            let snippet = SnippetSheet(snippet: Snippet(trigger: "書き出し", text: "{宛名}\n\n{挨拶}\n株式会社ABCの矢野です。"))
                .environmentObject(SettingsStore.shared)
            await render(snippet, "sheet-snippet", size: NSSize(width: 520, height: 480))
            let changes = Text(HistoryRow.changes(from: "お客様が言ってた資料、見ました。明日持っていきます。",
                                                  to: "お客様がおっしゃっていた資料を拝見しました。明日お持ちします。"))
                .font(.ui(12.5)).padding(16).frame(width: 520, alignment: .leading).background(Palette.panel)
            await render(changes, "history-changes", size: NSSize(width: 520, height: 90))
        }

        let only = args.firstIndex(of: "--only").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        if only == "voicebar" {
            await renderVoiceBar()
            return 0
        }
        if only == "mail" {
            await renderMail()
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
        await renderMail()
        await renderVoiceBar()
        controller.answer = AnswerCardContent(question: "富士山の高さはどれくらい", answer: "富士山の標高は **3,776 m** です。日本で最も高い山で、山梨県と静岡県にまたがっています。")
        let card = FirstMouseHostingView(rootView: AnswerCardView(controller: controller))
        card.layoutSubtreeIfNeeded()
        await render(AnswerCardView(controller: controller).padding(30).background(SnapshotWallpaper()), "answer-card", size: NSSize(width: 520, height: max(200, card.fittingSize.height + 60)))
        print("snapshots written to \(dir.path)")
        return 0
    }
}
