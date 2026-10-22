import Foundation
import Testing
@testable import Koebumi

@Suite struct AgentInputTests {
    /// Claude Code 2.1.308 の許可の確認。Bash は 4 つ、ファイルの作成は 3 つの選択肢を出す
    private let bash = PermissionPrompt(options: ["Yes", "Yes, and always allow access to ~/workspace/speak from this project",
                                                  "Yes, and switch to auto mode · auto mode handles these prompts for you", "No"], selected: 0)
    private let write = PermissionPrompt(options: ["Yes", "Yes, and switch to accept edits (auto-approve file edits and common file commands) for this session (shift+tab)",
                                                   "No"], selected: 0)

    private func choice(_ spoken: String, _ prompt: PermissionPrompt) -> Int? {
        AgentInput.answer(spoken, to: prompt)?.choice
    }

    @Test func answersPermissionPromptsByTheirChoices() {
        for prompt in [bash, write] {
            #expect(choice("はい", prompt) == 0)
            #expect(choice("お願いします。", prompt) == 0)
            #expect(choice("はい、お願いします", prompt) == 0)
            #expect(choice("OK", prompt) == 0)
            #expect(choice("今後は聞かないで", prompt) == 1)
            #expect(choice("はい、今後は聞かないで。", prompt) == 1)
            #expect(choice("2番", prompt) == 1)
            #expect(choice("ふたつ目", prompt) == 1)
            #expect(choice("5番", prompt) == nil)
        }
        // No の位置は確認の種類で変わる
        #expect(choice("いいえ", bash) == 3)
        #expect(choice("いいえ", write) == 2)
        #expect(choice("やめて。", bash) == 3)
        // auto mode に切り替える選択肢は、番号で言ったときだけ選ぶ
        #expect(choice("3番で", bash) == 2)
        // 2 つ目の Yes がなければ「今後は聞かないで」には答えない
        #expect(choice("今後は聞かないで", PermissionPrompt(options: ["Yes", "No"], selected: 0)) == nil)
    }

    @Test func sendsWhatToDoInsteadAfterNo() {
        #expect(AgentInput.answer("いいえ、先にビルドだけして", to: bash) == .init(choice: 3, rest: "先にビルドだけして"))
        #expect(AgentInput.answer("No, use mkdir -p instead.", to: bash) == .init(choice: 3, rest: "use mkdir -p instead"))
        // 音声認識が読点を付けなかった
        #expect(AgentInput.answer("いいえ先にテストを書いて", to: write) == .init(choice: 2, rest: "先にテストを書いて"))
        #expect(AgentInput.answer("いいえ、やめて", to: bash) == .init(choice: 3, rest: nil))
    }

    /// 実際に話して試したときの書き起こし。短い返事は別の字で書かれる（いいえ → イエ・伊え）
    @Test func acceptsShortAnswersWrittenWithOtherCharacters() {
        #expect(choice("イエ。", bash) == 3)
        #expect(choice("伊え。", bash) == 3)
        #expect(choice("イエ。", write) == 2)
        #expect(choice("Hi.", bash) == 0)
        #expect(choice("ハイ", write) == 0)
        #expect(AgentInput.answer("イエ、代わりに test-dir2 を作って", to: bash) == .init(choice: 3, rest: "代わりに test-dir2 を作って"))
        // 読点も付かなかった
        #expect(AgentInput.answer("いえテストディアツーを作って。", to: bash) == .init(choice: 3, rest: "テストディアツーを作って"))
        #expect(AgentInput.answer("イエ先にビルドして", to: write) == .init(choice: 2, rest: "先にビルドして"))
        #expect(choice("イエス", bash) == 0)
        // 「いや」は読みで比べても、いいえとみなさない
        #expect(choice("イヤ", bash) == nil)
    }

    @Test func ignoresSentencesThatAreNotAnswers() {
        // 「いや」は言い直しにも使う
        #expect(AgentInput.answer("いや、4時にして", to: bash) == nil)
        #expect(AgentInput.answer("テストは何件？", to: bash) == nil)
        #expect(AgentInput.answer("にして", to: bash) == nil)
        #expect(AgentInput.answer("家に帰って", to: bash) == nil)
    }


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

    /// SSH 先で試したときの書き起こし。音声認識が「grill me」を崩して書いた
    @Test func handlesBrokenEnglishNames() {
        let commands = AgentWorkspace.builtInCommands(for: .claudeCode) + ["grill-me", "grilling", "grill-with-docs", "aime-xai"]
        #expect(AgentInput.slashCommand("slash Grealmi.", commands: commands) == "/grill-me")
        #expect(AgentInput.slashCommand("slash Giri me.", commands: commands) == "/grill-me")
        // grilling も子音の違いが同じなので、綴りの近さで決める
        #expect(AgentInput.slashCommand("スラッシュグリルのみ。", commands: commands) == "/grill-me")
        #expect(AgentInput.slashCommand("slash grilling", commands: commands) == "/grilling")
        // 「グ」の濁点が落ちた（k r m と g r m）
        #expect(AgentInput.slashCommand("Slashクリーム。", commands: commands) == "/grill-me")
        #expect(AgentInput.slashCommand("Slash Gling.", commands: commands) == "/grilling")
        #expect(AgentInput.slashCommand("slash fix the failing tests", commands: commands) == nil)
        #expect(AgentInput.slashCommand("slash hogehoge", commands: commands) == nil)
        // 短い名前（子音が k r だけ）で clear と color のどちらとも言えないものは、綴りの近さでは決めない
        #expect(AgentInput.slashCommand("slash声浪。", commands: commands) == nil)
    }

    /// SSH 先にだけあるスキル（seiran）を呼んだときの書き起こし
    @Test func handlesRemoteOnlySkills() {
        let commands = AgentWorkspace.builtInCommands(for: .claudeCode) + ["grilling", "seiran"]
        #expect(AgentInput.slashCommand("/星蘭。", commands: commands) == "/seiran")
        #expect(AgentInput.slashCommand("slashu say lang", commands: commands) == "/seiran")
        #expect(AgentInput.slashCommand("slashu sea lang", commands: commands) == "/seiran")
        #expect(AgentInput.slashCommand("スラッシュセーラン。", commands: commands) == "/seiran")
        // seiran がないマシンで、最初の子音が違う grilling にはしない
        #expect(AgentInput.slashCommand("slashu say lang", commands: AgentWorkspace.builtInCommands(for: .claudeCode) + ["grilling"]) == nil)
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
                == Herdr.Pane(id: "wB:p1", agent: .claudeCode, directory: "/Users/me/workspace/speak/Sources"))
        #expect(Herdr.parse(snapshot(agent: "codex"), windowTitle: "Soyomi: speak", hostName: "soyomi.local")?.agent == .codex)
    }

    @Test func reportsShellPanesWithoutAnAgent() {
        // 左右に分けたシェルの区画を選んでいれば、隣の区画に Claude Code がいてもエージェントとみなさない
        #expect(Herdr.parse(snapshot(pane: "wB:p2"), windowTitle: "Soyomi.local: speak", hostName: "soyomi.local")
                == Herdr.Pane(id: "wB:p2", agent: nil, directory: "/Users/me/workspace/speak"))
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

@Suite struct RemoteCommandTests {
    @Test func findsInteractiveSSHSessions() {
        #expect(SSH.connection(["ssh", "mercury"]) == ["mercury"])
        #expect(SSH.connection(["/usr/bin/ssh", "-p", "2222", "-A", "-L8080:localhost:80", "me@host"]) == ["-p", "2222", "me@host"])
        #expect(SSH.connection(["ssh", "-p2222", "-i", "~/.ssh/key", "-o", "User=me", "host"]) == ["-p", "2222", "-i", "~/.ssh/key", "-o", "User=me", "host"])
        #expect(SSH.connection(["ssh", "-t", "host", "tmux", "attach"]) == ["host"])
        // herdr が裏で使う ssh（コマンド付き）や、転送だけの ssh は除く
        #expect(SSH.connection(["ssh", "-C", "-o", "BatchMode=yes", "-T", "mercury", "exec", "herdr", "remote-client-bridge"]) == nil)
        #expect(SSH.connection(["ssh", "-N", "-L", "8080:localhost:80", "host"]) == nil)
        #expect(SSH.connection(["ssh", "-O", "exit", "host"]) == nil)
        #expect(SSH.connection(["ssh"]) == nil)
        #expect(SSH.connection(["sshd", "host"]) == nil)
    }

    @Test func readsTheSSHInAHerdrPane() {
        let info = Data("""
        {"id":"cli:pane:process_info","result":{"process_info":{"foreground_process_group_id":1,"foreground_processes":[
          {"argv":["ssh","mercury"],"argv0":"ssh","cwd":"/Users/me","name":"ssh","pid":1}],"pane_id":"wB:p2","shell_pid":2},
          "type":"pane_process_info"}}
        """.utf8)
        #expect(Herdr.sshConnection(info) == ["mercury"])
        #expect(Herdr.sshConnection(Data(#"{"result":{"process_info":{"foreground_processes":[{"argv":["claude"]}]}}}"#.utf8)) == nil)
    }

    /// SSH 先で書き出した一覧から、自作のスキル・コマンドとプラグインのスキルを読む
    @Test func readsCommandsFromTheRemoteListing() throws {
        let output = "Last login: Mon\n\u{2}/home/me\n\u{2}/home/me/proj\n\u{1}/home/me/.claude/skills\ngrill-me/\nnotes.txt\n"
            + "\u{1}/home/me/.claude/commands\nship.md\n\u{1}/home/me/.codex/prompts\n\u{1}/home/me/proj/.claude/skills\nlocal-skill/\n"
            + "\u{1}/home/me/p/hud/skills\nsetup/\n\u{1}/home/me/p/hud/commands\n"
            + #"\#u{3}\#n{"plugins": {"hud@market": [{"installPath": "/home/me/p/hud"}]}}"#
        let files = try #require(RemoteFiles.parse(Data(output.utf8)))
        #expect(files.home == "/home/me")
        #expect(files.directory == "/home/me/proj")
        let commands = AgentWorkspace.commands(for: .claudeCode, directory: files.directory, in: files)
        for name in ["grill-me", "ship", "local-skill", "hud:setup", "compact"] { #expect(commands.contains(name), "\(name)") }
        #expect(!commands.contains("notes"))
        // 書き出しが途中で切れたものは使わない
        #expect(RemoteFiles.parse(Data("\u{2}/home/me\n\u{1}/home/me/.claude/skills\ngrill-me/\n".utf8)) == nil)
    }

    /// SSH 先で動かすスクリプトを、この Mac の sh で動かして確かめる
    @Test func runsTheListingScript() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("speak-remote-\(UUID().uuidString)").path
        defer { try? fm.removeItem(atPath: root) }
        let project = root + "/it's a project"
        for dir in ["/.claude/skills/grill-me", "/.claude/commands", "/plugins/hud/skills/setup"] {
            try fm.createDirectory(atPath: root + dir, withIntermediateDirectories: true)
        }
        try fm.createDirectory(atPath: project + "/.claude/skills/local-skill", withIntermediateDirectories: true)
        try Data().write(to: URL(fileURLWithPath: root + "/.claude/commands/ship.md"))
        try fm.createDirectory(atPath: root + "/.claude/plugins", withIntermediateDirectories: true)
        try Data("{\n  \"plugins\": {\n    \"hud@market\": [\n      {\n        \"installPath\": \"\(root)/plugins/hud\"\n      }\n    ]\n  }\n}\n".utf8)
            .write(to: URL(fileURLWithPath: root + "/.claude/plugins/installed_plugins.json"))
        let output = try #require(Subprocess.run("/usr/bin/env", ["HOME=" + root, "/bin/sh", "-s"],
                                                 input: Data(RemoteFiles.script(directory: project).utf8), timeout: 5))
        let files = try #require(RemoteFiles.parse(output))
        #expect(files.home == root)
        #expect(files.directory == project)
        let commands = AgentWorkspace.commands(for: .claudeCode, directory: files.directory, in: files)
        for name in ["grill-me", "ship", "local-skill", "hud:setup"] { #expect(commands.contains(name), "\(name)") }
    }
}
