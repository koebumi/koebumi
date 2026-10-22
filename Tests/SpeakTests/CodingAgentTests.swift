import Foundation
import Testing
@testable import Speak

@Suite struct CodingAgentTests {
    private func pad(_ s: String, _ width: Int) -> String {
        s + String(repeating: " ", count: max(0, width - TerminalView.displayWidth(s)))
    }

    /// herdr と同じ並び: 左に一覧（31 桁）、境目の線、右に画面を並べる。一覧にはエージェントの名前と状態が出る
    private func screen(_ panes: [[String]]) -> String {
        let sidebar = [" machines", " ▾ Local", "   ● speak", "     main", " agents", "   ● claude · working", "   Claude Code",
                       "   ○ codex · idle"]
        let columns = [sidebar] + panes
        let widths = [31] + panes.map { _ in 60 }
        return (0..<16).map { i in
            zip(columns, widths).map { pad($0[safe: i] ?? "", $1) }.joined(separator: "│")
        }.joined(separator: "\n")
    }

    private let rule = String(repeating: "─", count: 60)

    /// Claude Code 2.1 の画面の下のほう: 会話、横線に挟まれた入力欄、その下のモード表示
    private func claude(_ input: [String] = ["❯ "], footer: String = "  ? for shortcuts",
                        transcript: [String] = ["● 直しました。テストも通っています。"]) -> [String] {
        transcript + ["", "✻ Churned for 12s", ""] + [rule] + input + [rule, footer]
    }

    /// Codex 0.163 の画面の下のほう: 入力欄、状態、操作の案内
    private func codex(_ input: String = "› Ask Codex to do anything",
                       status: String = "  ~ · GPT-6.1-Sol · medium · Ready · Context 0% used") -> [String] {
        ["• 変更をまとめました。", "", input, "", status, "  ← for agents · ? for shortcuts"]
    }

    /// シェル。starship のプロンプトも「❯」で始まり、コマンドの出力に横線が出ることもある
    private let shell = ["󰕈 kyano @mercury  ~/workspace/speak", "❯ git log --oneline", "81f9496 fix/mic-selection をマージ",
                         String(repeating: "─", count: 30), "❯ "]

    @Test func findsClaudeCodeNextToShell() {
        #expect(CodingAgent.detect(in: screen([claude(footer: "  ⏵⏵ auto mode on (shift+tab to cycle)"), shell])) == [.claudeCode])
    }

    @Test func findsClaudeCodeByItsInputBox() {
        // 既定のモードでは、下の行に「? for shortcuts」しか出ない
        #expect(CodingAgent.detect(in: screen([claude(), shell])) == [.claudeCode])
        #expect(CodingAgent.detect(in: screen([shell, claude(["❯ README を直して、", "  テストも足して"])])) == [.claudeCode])
    }

    @Test func ignoresShellsAndTheSidebar() {
        // 一覧に「claude · working」「Claude Code」と出ていても、画面にエージェントがいなければ見分けない
        #expect(CodingAgent.detect(in: screen([shell, shell])).isEmpty)
        #expect(!CodingAgent.hasClaudeInputBox([rule, "❯ ls", "README.md  Sources", rule]))
    }

    @Test func ignoresAgentWordsInsideTheConversation() {
        // Claude Code で Codex の話をすると、会話や差分に Codex の画面の文字が出る（字下げされている）
        let talk = ["● Codex は次の表示で見分けます。", "  ⎿  + 「Ask Codex to do anything」で見分けます",
                    "  › Ask Codex to do anything", "  ~ · GPT-6.1-Sol · Context 0% used"]
        #expect(CodingAgent.detect(in: screen([claude(transcript: talk), shell])) == [.claudeCode])
        // シェルで Codex のログを表示しても、入力欄の形になっていなければ見分けない
        #expect(CodingAgent.detect(in: screen([shell + ["Context 12% used", "? for shortcuts"]])).isEmpty)
    }

    @Test func findsCodex() {
        #expect(CodingAgent.detect(in: screen([codex(), shell])) == [.codex])
        // 入力欄に文字があると案内は消えるが、状態の行に文脈の使用量が出る（古い版は残りの量）
        #expect(CodingAgent.detect(in: screen([codex("› README を直して"), shell])) == [.codex])
        #expect(CodingAgent.detect(in: screen([codex("› README を直して", status: "  58% context left · ? for shortcuts")])) == [.codex])
    }

    @Test func findsBothAgentsSideBySide() {
        let agents = CodingAgent.detect(in: screen([claude(), codex()]))
        #expect(agents == [.claudeCode, .codex])
        #expect(CodingAgent.label(agents) == "Claude Code / Codex")
    }

    @Test func readsTerminalsWithoutPaddedRows() {
        // 行の幅がそろっていない端末は、区画に分けずに全体を見る
        #expect(CodingAgent.detect(in: (["% claude"] + claude()).joined(separator: "\n")) == [.claudeCode])
        #expect(CodingAgent.detect(in: shell.joined(separator: "\n")).isEmpty)
    }

    @Test func addressesTheAgent() {
        let ghostty = AppContextInfo(bundleID: "com.mitchellh.ghostty", appName: "Ghostty", windowTitle: nil, category: .code, pid: 1)
        let info = ghostty.addressing([.claudeCode])
        #expect(info.appName == "Claude Code")
        #expect(info.category == .ai)
        #expect(info.bundleID == "com.mitchellh.ghostty")
        #expect(ghostty.addressing([]) == ghostty)
    }

    @Test func recognizesAgentNamesAndTerminals() {
        #expect(CodingAgent.isLabel("Claude Code"))
        #expect(CodingAgent.isLabel("Claude Code / Codex"))
        #expect(!CodingAgent.isLabel("ChatGPT"))
        #expect(!CodingAgent.isLabel("Ghostty"))
        #expect(CodingAgent.isTerminal("com.mitchellh.ghostty"))
        #expect(CodingAgent.isTerminal("dev.warp.Warp-Stable"))
        #expect(!CodingAgent.isTerminal("com.tinyspeck.slackmacgap"))
        #expect(!CodingAgent.isTerminal(nil))
        // ChatGPT のデスクトップアプリ（Codex と同じアプリ）は AI チャット
        #expect(AppContext.classify(bundleID: "com.openai.codex", windowTitle: nil) == .ai)
        #expect(AppContext.classify(bundleID: "net.kovidgoyal.kitty", windowTitle: nil) == .code)
    }

    @Test func promptTellsTheModelAboutTheAgent() {
        var r = PolishRequest(transcript: "えーと、アップデリゲートを直して", mode: .dictate, sourceLanguages: ["ja-JP"], targetLanguage: nil,
                              appName: "Claude Code", category: .ai, styleDescription: AppCategory.ai.defaultStyleDescription,
                              personalStyle: nil, vocabulary: [], corrections: [], codingAgent: true)
        #expect(Prompts.polishUser(r).contains("Claude Code is an AI coding agent in the terminal"))
        r.codingAgent = false
        #expect(!Prompts.polishUser(r).contains("coding agent"))
    }

    @Test func detectionIsOnByDefault() throws {
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"llmProvider": "claude"}"#.utf8))
        #expect(s.detectCodingAgents)
    }
}
