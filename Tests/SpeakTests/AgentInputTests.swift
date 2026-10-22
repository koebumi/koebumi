import Foundation
import Testing
@testable import Speak

@Suite struct AgentInputTests {
    @Test func splitsSubmitAtTheEnd() {
        #expect(AgentInput.splitSubmit("README を直して。送信。") == ("README を直して。", true))
        #expect(AgentInput.splitSubmit("直して 送信") == ("直して", true))
        #expect(AgentInput.splitSubmit("main にマージして、送信") == ("main にマージして", true))
        // カタカナ語の最後の「ト」を、音声認識が助詞の「と」にした（実際に返したもの）
        #expect(AgentInput.splitSubmit("スラッシュコンテクスと送信。") == ("スラッシュコンテクスト", true))
        #expect(AgentInput.splitSubmit("送信") == ("", true))
        #expect(AgentInput.splitSubmit("fix the tests. Submit") == ("fix the tests.", true))
        #expect(AgentInput.splitSubmit("フォームのデータを送信") == ("フォームのデータを送信", false))
        #expect(AgentInput.splitSubmit("送信ボタンを直して") == ("送信ボタンを直して", false))
    }

    @Test func turnsSpokenSlashCommandsIntoCommands() {
        let commands = AgentWorkspace.builtInCommands(for: .claudeCode) + ["code-review", "grill-me"]
        #expect(AgentInput.slashCommand("スラッシュ コンパクト", commands: commands) == "/compact")
        #expect(AgentInput.slashCommand("スラッシュコンパクト。", commands: commands) == "/compact")
        #expect(AgentInput.slashCommand("スラッシュ、クリア", commands: commands) == "/clear")
        #expect(AgentInput.slashCommand("スラッシュ モデル", commands: commands) == "/model")
        #expect(AgentInput.slashCommand("スラッシュ コードレビュー", commands: commands) == "/code-review")
        #expect(AgentInput.slashCommand("slash code review", commands: commands) == "/code-review")
        #expect(AgentInput.slashCommand("/compact", commands: commands) == "/compact")
        #expect(AgentInput.slashCommand("スラッシュ グリルミー", commands: commands) == "/grill-me")
    }

    /// 実際に話して試したときの書き起こし（Qwen3-ASR 0.6B）
    @Test func handlesRealTranscripts() {
        let commands = AgentWorkspace.builtInCommands(for: .claudeCode) + ["code-review", "yomiyasu"]
        #expect(AgentInput.slashCommand("Slash Context.", commands: commands) == "/context")
        #expect(AgentInput.slashCommand("Slash Contextと。", commands: commands) == "/context")  // コンテクストの「ト」
        #expect(AgentInput.slashCommand("スラッシュコピー。", commands: commands) == "/copy")
        #expect(AgentInput.slashCommand("Slash copy.", commands: commands) == "/copy")
        #expect(AgentInput.slashCommand("スラッシュフォク。", commands: commands) == "/fork")
        #expect(AgentInput.slashCommand("Slash読みやす。", commands: commands) == "/yomiyasu")  // 日本語の名前のスキルは読みで比べる
        #expect(AgentInput.slashCommand("スラッシュ よみやす", commands: commands) == "/yomiyasu")
        #expect(AgentInput.slashCommand("スラッシュワークフロー", commands: commands) == "/workflows")  // 単数で呼んだ
        #expect(AgentInput.slashCommand("Slash workflow", commands: commands) == "/workflows")
        #expect(AgentInput.slashCommand("スラスドクター。", commands: commands) == "/doctor")  // 「スラッシュ」を縮めて書いた
        #expect(AgentInput.slashCommand("Slash Doctor.", commands: commands) == "/doctor")
        // 子音が同じ clear と color は、母音の並びで決める
        #expect(AgentInput.slashCommand("スラッシュ クリア", commands: commands) == "/clear")
    }

    @Test func leavesOtherSpeechForPolishing() {
        let commands = AgentWorkspace.builtInCommands(for: .claudeCode)
        #expect(AgentInput.slashCommand("README を直して", commands: commands) == nil)
        #expect(AgentInput.slashCommand("スラッシュ コンパクトして要約も残して", commands: commands) == nil)
        #expect(AgentInput.slashCommand("スラッシュ ホゲホゲ", commands: commands) == nil)
        #expect(AgentInput.slashCommand("スラストを上げて", commands: commands) == nil)
        #expect(AgentInput.slashCommand("スラスト", commands: commands) == nil)
    }

    @Test func comparesKatakanaAndEnglishBySound() {
        for (katakana, english) in [("コンパクト", "compact"), ("コードレビュー", "code review"), ("セキュリティレビュー", "security review"),
                                     ("ステータスライン", "statusline"), ("エージェント", "agent"), ("グリルミー", "grill me")] {
            #expect(Phonetic.key(katakana: katakana) == Phonetic.key(english: english), "\(katakana) / \(english)")
        }
    }
}

@Suite struct HerdrTests {
    /// herdr api snapshot の出力（使うところだけ）
    private func snapshot(pane: String = "wB:p1", agent: String? = "claude") -> Data {
        let agentField = agent.map { #""agent": "\#($0)", "# } ?? ""
        return Data("""
        {"id": "cli:api:snapshot", "result": {"type": "session_snapshot", "snapshot": {
          "focused_workspace_id": "wB", "focused_pane_id": "\(pane)", "version": "0.9.5",
          "workspaces": [{"workspace_id": "w9", "label": "herdr"}, {"workspace_id": "wB", "label": "speak"}],
          "panes": [{"pane_id": "wB:p1", \(agentField)"cwd": "/Users/me/workspace/speak", "foreground_cwd": "/Users/me/workspace/speak/Sources"},
                    {"pane_id": "wB:p2", "cwd": "/Users/me/workspace/speak"}]}}}
        """.utf8)
    }

    @Test func readsTheFocusedPaneOnThisMac() {
        #expect(Herdr.parse(snapshot(), windowTitle: "Soyomi.local: speak", hostName: "soyomi.local")
                == Herdr.Pane(agent: .claudeCode, directory: "/Users/me/workspace/speak/Sources"))
        #expect(Herdr.parse(snapshot(agent: "codex"), windowTitle: "Soyomi: speak", hostName: "soyomi.local")?.agent == .codex)
    }

    @Test func reportsShellPanesWithoutAnAgent() {
        // 左右に分けたシェルの区画を選んでいれば、隣の区画に Claude Code がいてもエージェントとみなさない
        #expect(Herdr.parse(snapshot(pane: "wB:p2"), windowTitle: "Soyomi.local: speak", hostName: "soyomi.local")
                == Herdr.Pane(agent: nil, directory: "/Users/me/workspace/speak"))
    }

    @Test func ignoresWindowsShowingAnotherMachine() {
        // SSH 先のマシン（mercury）を開いているときは、この Mac の herdr が選んでいる区画は画面に出ていない
        #expect(Herdr.parse(snapshot(), windowTitle: "mercury: transolver_aime", hostName: "soyomi.local") == nil)
        #expect(Herdr.parse(snapshot(), windowTitle: "Soyomi.local: herdr", hostName: "soyomi.local") == nil)
        #expect(Herdr.parse(Data("not json".utf8), windowTitle: "Soyomi.local: speak", hostName: "soyomi.local") == nil)
    }

    @Test func recognizesInteractiveAgentProcesses() {
        #expect(AgentWorkspace.isInteractive(.claudeCode, arguments: ["claude"]))
        #expect(AgentWorkspace.isInteractive(.claudeCode, arguments: ["/Users/me/.local/bin/claude", "--resume"]))
        #expect(!AgentWorkspace.isInteractive(.claudeCode, arguments: ["claude", "mcp", "serve"]))
        #expect(!AgentWorkspace.isInteractive(.claudeCode, arguments: ["/Applications/Claude.app/Contents/MacOS/Claude"]))
        #expect(AgentWorkspace.isInteractive(.codex, arguments: ["/opt/homebrew/lib/node_modules/@openai/codex/bin/codex"]))
        // Codex が裏で動かすサーバーは除く
        #expect(!AgentWorkspace.isInteractive(.codex, arguments: ["/Users/me/.codex/bin/codex", "app-server", "--listen", "unix://"]))
        #expect(!AgentWorkspace.isInteractive(.codex, arguments: []))
    }

    @Test func listsBuiltInAndCustomCommandsOnce() {
        let commands = AgentWorkspace.commands(for: .codex, directory: nil)
        #expect(commands.contains("compact"))
        #expect(Set(commands).count == commands.count)
    }
}

@Suite struct HerdrMachineTests {
    @Test func readsHerdrMachinesAndTitles() {
        let list = "2f60f55e\tmercury\tmercury\tdefault\tenabled\n2d52067c\tvega-kyano\tkyano@vega\tdefault\tenabled\nabc\told\told\tdefault\tdisabled\n"
        #expect(Herdr.parseMachines(list) == ["mercury": "mercury", "vega-kyano": "kyano@vega"])
        #expect(Herdr.splitTitle("mercury: transolver_aime")! == ("mercury", "transolver_aime"))
        #expect(Herdr.splitTitle("✳ Claude Code") == nil)
    }
}
