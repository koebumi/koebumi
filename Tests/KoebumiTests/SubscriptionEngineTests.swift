import Foundation
import Testing
@testable import Koebumi

@Suite struct ClaudeCodeEngineTests {
    private func json(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    @Test func readsTheResultText() throws {
        let out = json(["type": "result", "subtype": "success", "is_error": false, "result": "  明日は4時にしましょう。\n"])
        #expect(try ClaudeCodeEngine.result(stdout: out, stderr: Data()) == "明日は4時にしましょう。")
    }

    @Test func reportsSignedOutWithTheLoginSteps() {
        // ログインしていないときも subtype は success で、is_error と本文で分かる
        let out = json(["type": "result", "subtype": "success", "is_error": true, "result": "Not logged in · Please run /login"])
        #expect(throws: LLMError.self) { try ClaudeCodeEngine.result(stdout: out, stderr: Data()) }
        #expect(ClaudeCodeEngine.failure("Not logged in · Please run /login").errorDescription == ClaudeCodeEngine.signedOut)
    }

    @Test func showsStderrWhenTheOutputIsNotJSON() {
        let error = ClaudeCodeEngine.failure("error: unknown option '--foo'")
        #expect(error.errorDescription?.contains("unknown option") == true)
        #expect(throws: LLMError.self) { try ClaudeCodeEngine.result(stdout: Data(), stderr: Data("boom".utf8)) }
    }

    @Test func runsWithoutUserSettingsOrTools() {
        let args = ClaudeCodeEngine.arguments(model: "claude-haiku-5-5", system: "SYSTEM")
        #expect(args.starts(with: ["-p", "--model", "claude-haiku-5-5"]))
        #expect(args.contains("--no-session-persistence"))
        // --tools は後ろの引数もツール名として読むので、最後に置く
        #expect(args.suffix(2) == ["--tools", ""])
        let i = args.firstIndex(of: "--setting-sources")!
        #expect(args[i + 1] == "")
        #expect(args[args.firstIndex(of: "--system-prompt")! + 1] == "SYSTEM")
    }

    @Test func describesTheSignInStatus() {
        let max = ClaudeCodeEngine.status(auth: ["loggedIn": true, "authMethod": "claude.ai", "subscriptionType": "max"])
        #expect(max.isReady)
        #expect(max.detail.contains("Max"))

        let apiKey = ClaudeCodeEngine.status(auth: ["loggedIn": true, "authMethod": "api_key"])
        #expect(apiKey.isReady)
        #expect(apiKey.detail.contains("API"))

        #expect(ClaudeCodeEngine.status(auth: ["loggedIn": false, "authMethod": "none"]) == .signedOut(ClaudeCodeEngine.signedOut))
    }
}

@Suite struct CodexAppServerTests {
    @Test func describesTheChatGPTAccount() {
        let team = CodexAppServer.access(from: ["account": ["type": "chatgpt", "email": "a@example.com", "planType": "team"], "requiresOpenaiAuth": true])
        #expect(team?.contains("ChatGPT Team") == true)
        #expect(team?.contains("a@example.com") == true)

        let apiKey = CodexAppServer.access(from: ["account": ["type": "apiKey"], "requiresOpenaiAuth": true])
        #expect(apiKey?.contains("API") == true)
    }

    @Test func treatsAMissingAccountAsSignedOut() {
        #expect(CodexAppServer.access(from: ["account": NSNull(), "requiresOpenaiAuth": true]) == nil)
        // 自分のプロバイダーを設定した Codex はログインが要らない
        #expect(CodexAppServer.access(from: ["account": NSNull(), "requiresOpenaiAuth": false]) != nil)
    }

    @Test func disablesOnlyRunningServersWithAddressableNames() {
        let list: [[String: Any]] = [
            ["name": "blender", "enabled": true],
            ["name": "computer-use", "enabled": false],
            ["name": "node_repl", "enabled": true],
            ["name": "my.server", "enabled": true],
        ]
        let data = try! JSONSerialization.data(withJSONObject: list)
        #expect(CodexAppServer.mcpServerNames(data) == ["blender", "node_repl"])
        #expect(CodexAppServer.mcpServerNames(Data("not json".utf8)).isEmpty)
    }

    @Test func turnsOffCodingFeatures() {
        let settings = CodexAppServer.configuration
        #expect(settings.contains("features.shell_tool=false"))
        #expect(settings.contains("features.hooks=false"))
        #expect(settings.contains("memories.use_memories=false"))
    }

    @Test func explainsUsageLimitsAndSignIn() {
        #expect(CodexAppServer.failure("You've hit your usage limit").errorDescription?.contains("上限") == true
            || CodexAppServer.failure("You've hit your usage limit").errorDescription?.contains("limit") == true)
        #expect(CodexAppServer.failure("401 Unauthorized").errorDescription == CodexAppServer.signedOut)
        #expect(CodexAppServer.failure("stream disconnected").errorDescription?.hasPrefix("Codex: ") == true)
    }
}

@Suite struct JSONAskOutcomeTests {
    private let request = AskRequest(query: "q", selection: "x", selectionEditable: true, hasFocusedTextField: true, appName: "A", vocabulary: [])

    @Test func readsTheActionFromJSON() {
        #expect(Prompts.outcome(json: #"{"action": "replace", "text": "丁寧な文", "url": ""}"#, request: request) == .replace("丁寧な文"))
        #expect(Prompts.outcome(json: "```json\n{\"action\": \"answer\", \"text\": \"333m\", \"url\": \"\"}\n```", request: request) == .answer("333m"))
    }

    @Test func answersWithTheTextWhenItIsNotJSON() {
        #expect(Prompts.outcome(json: "東京タワーは333mです", request: request) == .answer("東京タワーは333mです"))
    }
}

@Suite struct CommandLineToolTests {
    @Test func putsTheToolsFolderFirstInPATH() {
        let env = CommandLineTool.environment(for: URL(fileURLWithPath: "/opt/example/bin/claude"), removing: ["ANTHROPIC_API_KEY"])
        #expect(env["PATH"]?.hasPrefix("/opt/example/bin:") == true)
        #expect(env["ANTHROPIC_API_KEY"] == nil)
        let dirs = env["PATH"]!.split(separator: ":")
        #expect(dirs.count == Set(dirs).count)
    }

    @Test func passesInputAndReadsOutput() async throws {
        let out = try await CommandLineTool.run(URL(fileURLWithPath: "/bin/cat"), arguments: [], input: "こんにちは")
        #expect(out.status == 0)
        #expect(String(decoding: out.stdout, as: UTF8.self) == "こんにちは")
    }

    @Test func stopsACommandThatTakesTooLong() async throws {
        let start = Date()
        let out = try await CommandLineTool.run(URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"], timeout: 0.3)
        #expect(out.timedOut)
        #expect(Date().timeIntervalSince(start) < 3)
    }
}
