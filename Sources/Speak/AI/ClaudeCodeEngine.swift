import Foundation

/// Claude Code（`claude -p`）を通して、ユーザーの Claude のサブスク（Pro・Max）で整形する。
/// Anthropic は、他社のアプリが Claude.ai のログインを扱うことやトークンを読むことを認めていない。
/// Speak はトークンに触れず、この Mac に入っている Claude Code をそのまま動かして、ログインは Claude Code に任せる。
/// 呼ぶたびに起動するので、API より 1 秒ほど遅い（Haiku で 2〜3 秒）。
struct ClaudeCodeEngine: LLMEngine {
    let model: String

    var name: String { t("Claude（サブスク）", "Claude (subscription)") }
    var supportsWebSearch: Bool { false }

    /// API キーの環境変数があると、Claude Code はサブスクではなく API の料金で動くので渡さない
    static let apiKeyVariables = ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN"]

    static var notInstalled: String {
        t("Claude Code が見つかりません。https://claude.com/claude-code の手順で入れて、ターミナルで claude を開いてログインしてください",
          "Claude Code was not found. Install it from https://claude.com/claude-code, then open claude in Terminal and sign in")
    }

    static var signedOut: String {
        t("Claude Code にログインしていません。ターミナルで claude を開き、/login で Pro・Max のアカウントにログインしてください",
          "Claude Code is not signed in. Open claude in Terminal and run /login with your Pro or Max account")
    }

    func polish(_ request: PolishRequest) async throws -> String {
        let system = request.mode == .translate ? Prompts.translateSystem : Prompts.polishSystem
        return Prompts.cleanOutput(try await complete(system: system, user: Prompts.polishUser(request)))
    }

    func ask(_ request: AskRequest) async throws -> AskOutcome {
        Prompts.outcome(json: try await complete(system: Prompts.askSystemJSON, user: Prompts.askUser(request)), request: request)
    }

    func analyzeStyle(samples: [StyleSample], current: StyleProfile) async throws -> StyleAnalysis {
        let raw = try await complete(system: Prompts.styleSystem, user: Prompts.styleUser(samples: samples, current: current))
        return try JSONDecoder().decode(StyleAnalysis.self, from: Data(Prompts.extractJSON(raw).utf8))
    }

    static func arguments(model: String, system: String) -> [String] {
        [
            "-p", "--model", model, "--output-format", "json", "--effort", "low",
            "--system-prompt", system,
            // ユーザーの設定・フック・プラグイン・MCP サーバーを読まず、会話も残さない（起動が速くなり、Speak の指示だけで動く）
            "--setting-sources", "", "--strict-mcp-config", "--no-session-persistence", "--disable-slash-commands",
            // ツールは使わせない。後ろの引数もツール名として読まれるので最後に置く
            "--tools", "",
        ]
    }

    private func complete(system: String, user: String) async throws -> String {
        guard let claude = CommandLineTool.locate("claude") else { throw LLMError.unavailable(Self.notInstalled) }
        let out = try await CommandLineTool.run(
            claude, arguments: Self.arguments(model: model, system: system), input: user, directory: Self.workspace,
            environment: CommandLineTool.environment(for: claude, removing: Self.apiKeyVariables), timeout: 90
        )
        if out.timedOut { throw LLMError.unavailable(t("Claude Code から応答がありませんでした", "Claude Code did not respond")) }
        return try Self.result(stdout: out.stdout, stderr: out.stderr)
    }

    /// 作業フォルダは空のフォルダにする（どこかのプロジェクトの CLAUDE.md を読まないように）
    private static var workspace: URL {
        let dir = Storage.root.appendingPathComponent("ClaudeCode", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// `claude -p --output-format json` の出力から本文を取り出す。ログインしていないときなども JSON で is_error が返る
    static func result(stdout: Data, stderr: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: stdout) as? [String: Any] else {
            throw failure(String(decoding: stderr.isEmpty ? stdout : stderr, as: UTF8.self))
        }
        let text = (json["result"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if json["is_error"] as? Bool == true { throw failure(text) }
        return text
    }

    static func failure(_ message: String) -> LLMError {
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = message.lowercased()
        if lower.contains("not logged in") || lower.contains("/login") || lower.contains("invalid api key") {
            return .unavailable(signedOut)
        }
        if lower.contains("usage limit") || lower.contains("hit your limit") || lower.contains("rate limit") {
            return .unavailable(t("Claude のサブスクの利用上限に達しました。上限が戻るまで待つか、設定で別の AI エンジンを選んでください",
                                  "You reached your Claude plan's usage limit. Wait for it to reset or choose another AI engine in Settings"))
        }
        if message.isEmpty { return .badResponse }
        return .unavailable("Claude Code: " + message.prefix(300))
    }

    // MARK: - 設定画面に出す状態

    static func status() async -> SubscriptionStatus {
        guard let claude = CommandLineTool.locate("claude") else { return .notInstalled(notInstalled) }
        // ログインしていないときは終了コード 1 で、JSON は返る
        guard let out = try? await CommandLineTool.run(claude, arguments: ["auth", "status", "--json"],
                                                       environment: CommandLineTool.environment(for: claude, removing: apiKeyVariables), timeout: 20),
              let json = try? JSONSerialization.jsonObject(with: out.stdout) as? [String: Any]
        else { return .failed(t("Claude Code のログイン状態を確かめられませんでした", "Could not check Claude Code's sign-in status")) }
        return status(auth: json)
    }

    /// `claude auth status --json` の結果を、設定画面の表示にする
    static func status(auth json: [String: Any]) -> SubscriptionStatus {
        guard json["loggedIn"] as? Bool == true else { return .signedOut(signedOut) }
        guard json["authMethod"] as? String == "claude.ai" else {
            return .signedIn(t("Claude Code に API キーでログインしています。サブスクではなく API の料金がかかります。",
                               "Claude Code is signed in with an API key, so usage is billed at API rates, not to your plan."))
        }
        let plan = (json["subscriptionType"] as? String).map(planName) ?? "Claude"
        return .signedIn(t("\(plan) プランでログインしています。使った分は Claude Code と同じ利用枠から引かれます。",
                           "Signed in with \(plan). Usage counts toward the same limits as Claude Code."))
    }

    private static func planName(_ raw: String) -> String {
        switch raw.lowercased() {
        case "max": return "Max"
        case "pro": return "Pro"
        case "team": return "Team"
        case "enterprise": return "Enterprise"
        default: return raw.prefix(1).uppercased() + raw.dropFirst()
        }
    }
}
