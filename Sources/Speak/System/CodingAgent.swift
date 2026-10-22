import Foundation
import ApplicationServices

/// 端末の中で動くコーディングエージェント。見つかったら、話した内容をエージェントへの指示として整形する。
/// herdr や tmux の中、SSH 先で動いていると端末アプリの子プロセスからは見つからないので、画面に出る入力欄や表示で見分ける。
enum CodingAgent: String, CaseIterable {
    case claudeCode, codex

    var name: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        }
    }

    /// 画面の文字を読んでエージェントを探す端末アプリ（bundle ID の先頭）
    private static let terminalBundleIDs = [
        "com.mitchellh.ghostty", "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp",
        "com.github.wez.wezterm", "net.kovidgoyal.kitty", "org.alacritty",
    ]

    static func isTerminal(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return terminalBundleIDs.contains { bundleID.hasPrefix($0) }
    }

    /// 履歴やプロンプトに出すアプリ名。左右に並べた画面で両方動いていれば「Claude Code / Codex」
    static func label(_ agents: [CodingAgent]) -> String {
        agents.map(\.name).joined(separator: " / ")
    }

    /// アプリ名がエージェントの名前か（履歴から再処理するときも、エージェントへの指示として整形するため）
    static func isLabel(_ appName: String) -> Bool {
        let names = appName.components(separatedBy: " / ")
        return names.allSatisfy { name in allCases.contains { $0.name == name } }
    }

    // MARK: - 画面から見分ける

    /// 端末の画面から、動いているエージェントを探す。左右に並べた画面のどれに入力するかは画面の文字からはわからないので、
    /// 見つかったものをすべて返す
    static func detect(in screen: String) -> [CodingAgent] {
        // 行末の空白を削って渡す端末もあるので、いちばん長い行に幅をそろえてから画面を分ける
        var rows = screen.components(separatedBy: "\n")
        while rows.last?.isEmpty == true { rows.removeLast() }
        let width = rows.map(TerminalView.displayWidth).max() ?? 0
        let grid = rows.map { $0 + String(repeating: " ", count: width - TerminalView.displayWidth($0)) }.joined(separator: "\n")
        let panes = TerminalView.panes(in: grid)?.map { $0.rows(grid) } ?? [rows]
        return allCases.filter { agent in panes.contains { agent.isShown(in: $0) } }
    }

    /// 入力欄の形で見分ける。エージェントの会話に出てくる語（「Ask Codex to do anything」の説明など）は字下げされているので、
    /// 行の先頭から始まる入力欄だけを見る
    private func isShown(in rows: [String]) -> Bool {
        switch self {
        case .claudeCode: return Self.hasClaudeInputBox(rows)
        case .codex: return Self.hasCodexComposer(rows)
        }
    }

    /// Claude Code の入力欄。横線の下に「❯」で始まる行があり、2 桁下げた続きの行の後にまた横線がある。
    /// シェルのプロンプト（starship の「❯」など）は横線に挟まれない
    static func hasClaudeInputBox(_ rows: [String]) -> Bool {
        for (i, row) in rows.enumerated() where isRule(row) {
            guard let prompt = rows[safe: i + 1], prompt.hasPrefix("❯") || prompt.hasPrefix(">") else { continue }
            for next in rows.dropFirst(i + 2).prefix(10) {
                if isRule(next) { return true }
                guard next.isEmpty || next.hasPrefix("  ") else { break }
            }
        }
        return false
    }

    private static func isRule(_ row: String) -> Bool {
        let s = row.trimmingCharacters(in: .whitespaces)
        return s.count >= 20 && s.allSatisfy { $0 == "─" }
    }

    /// Codex の入力欄。「›」で始まる行（空なら「› Ask Codex to do anything」）の少し下に、
    /// 文脈の使用量（古い版は残りの量）か操作の案内の行がある
    static func hasCodexComposer(_ rows: [String]) -> Bool {
        for (i, row) in rows.enumerated() where row.hasPrefix("› ") || row == "›" {
            if row == "› Ask Codex to do anything" { return true }
            if rows.dropFirst(i + 1).prefix(8).contains(where: isCodexFooter) { return true }
        }
        return false
    }

    private static func isCodexFooter(_ row: String) -> Bool {
        row.range(of: #"Context \d+% used|\d+% context left"#, options: .regularExpression) != nil
            || row.contains("? for shortcuts") || row.contains("esc to interrupt")
    }

    // MARK: - 画面を読む

    /// 前面の端末の、表示している範囲の文字列（Terminal.app などはスクロールして見えない行まで渡してくるため）。
    /// 応答の遅いアプリでもメインスレッドを止めないよう、録音と並行して呼ぶ
    static func readScreen(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.15)
        var visible: CFTypeRef?
        var range = CFRange()
        if AXUIElementCopyAttributeValue(element, kAXVisibleCharacterRangeAttribute as CFString, &visible) == .success,
           let visible, CFGetTypeID(visible) == AXValueGetTypeID(), AXValueGetValue(visible as! AXValue, .cfRange, &range),
           let param = AXValueCreate(.cfRange, &range) {
            var text: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, param, &text) == .success,
               let text = text as? String {
                return text
            }
        }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success, let value = value as? String else { return nil }
        // 見えている範囲を取れないときは、最後のほう（今の画面）だけを見る
        return String(value.suffix(40_000))
    }
}
