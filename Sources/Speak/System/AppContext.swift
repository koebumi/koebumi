import AppKit
import ApplicationServices

/// 入力先アプリの情報。トーン調整（アプリ別スタイル）に使う。
struct AppContextInfo: Equatable {
    var bundleID: String?
    var appName: String
    var windowTitle: String?
    var category: AppCategory
    var pid: pid_t?

    static let unknown = AppContextInfo(bundleID: nil, appName: "Unknown", windowTitle: nil, category: .other, pid: nil)
}

enum AppContext {
    @MainActor
    static func current(overrides: [String: AppCategory]) -> AppContextInfo {
        guard let app = NSWorkspace.shared.frontmostApplication else { return .unknown }
        let title = focusedWindowTitle(pid: app.processIdentifier)
        let bundleID = app.bundleIdentifier
        let category = bundleID.flatMap { overrides[$0] } ?? classify(bundleID: bundleID, windowTitle: title)
        return AppContextInfo(
            bundleID: bundleID,
            appName: app.localizedName ?? bundleID ?? "App",
            windowTitle: title,
            category: category,
            pid: app.processIdentifier
        )
    }

    private static let bundleCategories: [(String, AppCategory)] = [
        ("com.apple.mail", .email), ("com.microsoft.Outlook", .email), ("com.readdle.smartemail", .email),
        ("com.superhuman", .email), ("it.bloop.airmail", .email), ("com.mimestream", .email), ("com.edisonmail", .email),
        ("com.tinyspeck.slackmacgap", .chat), ("com.hnc.Discord", .chat), ("jp.naver.line", .chat),
        ("com.apple.MobileSMS", .chat), ("net.whatsapp", .chat), ("com.microsoft.teams", .chat),
        ("ru.keepcoder.Telegram", .chat), ("org.telegram", .chat), ("com.facebook.archon", .chat), ("us.zoom", .chat),
        ("com.chatwork", .chat), ("com.kakao", .chat), ("com.apple.FaceTime", .chat),
        ("com.apple.Notes", .document), ("com.apple.iWork.Pages", .document), ("com.microsoft.Word", .document),
        ("notion.id", .document), ("md.obsidian", .document), ("com.apple.TextEdit", .document),
        ("com.microsoft.onenote", .document), ("net.shinyfrog.bear", .document), ("com.lukilabs.lukiapp", .document),
        ("com.apple.iWork.Keynote", .document), ("com.microsoft.Powerpoint", .document), ("com.figma", .document),
        ("com.apple.dt.Xcode", .code), ("com.microsoft.VSCode", .code), ("com.todesktop.230313mzl4w4u92", .code),
        ("dev.zed", .code), ("com.jetbrains", .code), ("com.apple.Terminal", .code), ("com.googlecode.iterm2", .code),
        ("dev.warp", .code), ("com.mitchellh.ghostty", .code), ("com.sublimetext", .code), ("com.exafunction.windsurf", .code),
        ("com.openai.chat", .ai), ("com.anthropic.claudefordesktop", .ai), ("com.google.Gemini", .ai), ("ai.perplexity", .ai),
    ]

    /// ブラウザのウィンドウタイトルで判定する Web アプリ
    private static let titleCategories: [(String, AppCategory)] = [
        ("Gmail", .email), ("Outlook", .email), ("Yahoo!メール", .email), ("Proton Mail", .email),
        ("Slack", .chat), ("Discord", .chat), ("Chatwork", .chat), ("Messenger", .chat), ("WhatsApp", .chat),
        ("Microsoft Teams", .chat), ("LINE", .chat), ("Google Chat", .chat),
        ("Google ドキュメント", .document), ("Google Docs", .document), ("Notion", .document), ("Confluence", .document),
        ("Google スライド", .document), ("Google Slides", .document), ("Dropbox Paper", .document), ("note", .document),
        ("GitHub", .code), ("GitLab", .code), ("Stack Overflow", .code), ("CodeSandbox", .code),
        ("ChatGPT", .ai), ("Claude", .ai), ("Gemini", .ai), ("Perplexity", .ai), ("Copilot", .ai),
    ]

    static func classify(bundleID: String?, windowTitle: String?) -> AppCategory {
        if let bundleID {
            for (prefix, category) in bundleCategories where bundleID.hasPrefix(prefix) {
                return category
            }
        }
        if let title = windowTitle {
            for (keyword, category) in titleCategories where title.contains(keyword) {
                return category
            }
        }
        return .other
    }

    private static func focusedWindowTitle(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success, let window else { return nil }
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success else { return nil }
        return title as? String
    }
}
