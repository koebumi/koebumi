import Foundation
import ApplicationServices

/// Claude Code の許可の確認（Bash は Yes / Yes, and always allow … / Yes, and switch to auto mode / No の 4 つ、
/// ファイルの作成は Yes / Yes, and switch to accept edits … / No の 3 つ）
struct PermissionPrompt: Equatable {
    /// 選択肢の文（番号を除く。折り返した行はつなぐ）。1 番から順に並ぶ
    var options: [String]
    /// いま「❯」で選んでいる選択肢（0 から数える）
    var selected: Int
}

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
        let panes = panes(of: screen)
        return allCases.filter { agent in panes.contains { agent.isShown(in: $0) } }
    }

    /// 左右に並べた画面を、区画ごとの行に分ける
    private static func panes(of screen: String) -> [[String]] {
        // 行末の空白を削って渡す端末もあるので、いちばん長い行に幅をそろえてから画面を分ける
        var rows = screen.components(separatedBy: "\n")
        while rows.last?.isEmpty == true { rows.removeLast() }
        let width = rows.map(TerminalView.displayWidth).max() ?? 0
        let grid = rows.map { $0 + String(repeating: " ", count: width - TerminalView.displayWidth($0)) }.joined(separator: "\n")
        return TerminalView.panes(in: grid)?.map { $0.rows(grid) } ?? [rows]
    }

    /// 入力欄の形で見分ける。エージェントの会話に出てくる語（「Ask Codex to do anything」の説明など）は字下げされているので、
    /// 行の先頭から始まる入力欄だけを見る。Claude Code は許可の確認を出している間は入力欄を消すので、確認の形でも見分ける
    private func isShown(in rows: [String]) -> Bool {
        switch self {
        case .claudeCode: return Self.hasClaudeInputBox(rows) || Self.permissionPrompt(in: rows) != nil
        case .codex: return Self.hasCodexComposer(rows)
        }
    }

    // MARK: - 許可の確認

    /// 画面に出ている Claude Code の許可の確認。答えるには矢印と Enter を押すので、画面を左右に分けていれば nil
    /// （どの区画に入力するかわからず、シェルの区画で ↑ と Enter を押すと、前のコマンドをもう一度実行してしまう）
    static func permissionPrompt(in screen: String) -> PermissionPrompt? {
        let panes = panes(of: screen)
        return panes.count == 1 ? permissionPrompt(in: panes[0]) : nil
    }

    /// Claude Code 2.1 の許可の確認。1 桁下げた問い（Do you want to proceed?・Do you want to create notes.txt?）の下に、
    /// 「 ❯ 1. Yes」「   2. …」の選択肢が並び（長い選択肢は 6 桁下げて折り返す）、すぐ下に「Esc to cancel」の行がある。
    /// 会話の中に同じ文が出ても、2 桁以上下げてあるので拾わない。atBottom なら、確認は画面のいちばん下に出るので、
    /// その下に 2 行以上続いていれば（上下に分けた画面の別の区画）答えない。1 行までは tmux の状態の行とみなす。
    /// herdr から読んだ区画は、選んでいる区画だけなので atBottom にしない
    private static let optionRow = try! Regex(#" (❯| ) (\d)\. (.+)"#)

    static func permissionPrompt(in rows: [String], atBottom: Bool = true) -> PermissionPrompt? {
        let rows = rows.map(droppingLeftovers)
        for (i, row) in rows.enumerated() where row.hasPrefix(" Do you want ") && row.hasSuffix("?") {
            var prompt = PermissionPrompt(options: [], selected: 0)
            var next = i + 1
            for line in rows.dropFirst(i + 1) {
                if let option = line.wholeMatch(of: optionRow), let number = option[2].substring.flatMap({ Int($0) }),
                   number == prompt.options.count + 1, let label = option[3].substring {
                    if option[1].substring == "❯" { prompt.selected = prompt.options.count }
                    prompt.options.append(String(label))
                } else if !prompt.options.isEmpty, line.prefix(while: { $0 == " " }).count == 6 {
                    prompt.options[prompt.options.count - 1] += " " + line.trimmingCharacters(in: .whitespaces)
                } else {
                    break
                }
                next += 1
            }
            guard prompt.options.count >= 2, prompt.options[0].hasPrefix("Yes"),
                  let footer = rows.dropFirst(next).prefix(3).firstIndex(where: { $0.contains("Esc to cancel") }),
                  !atBottom || rows.dropFirst(footer + 1).filter({ !$0.isEmpty }).count <= 1
            else { continue }
            return prompt
        }
        return nil
    }

    /// 行の右に残った、前に表示していた文字を除く。herdr から読んだ区画では、日本語の多い会話のあとに短くなった行の右に
    /// 前の文字が残る（「 Do you want to proceed?      」だけを話すと…」）。確認の文と選択肢には空白が 2 つ続かないので、そこで切る
    private static func droppingLeftovers(_ row: String) -> String {
        let indent = row.prefix(while: { $0 == " " })
        let body = row.dropFirst(indent.count)
        guard let gap = body.range(of: "  ") else { return String(row.reversed().drop(while: \.isWhitespace).reversed()) }
        return String(indent + body[..<gap.lowerBound])
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
