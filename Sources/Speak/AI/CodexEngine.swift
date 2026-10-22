import Foundation

/// Codex（`codex app-server`）を通して、ユーザーの ChatGPT のサブスク（Plus・Pro など）で整形する。
/// ログインは Codex に任せ、Speak はトークンに触れない。
struct CodexEngine: LLMEngine {
    /// 空なら Codex の既定のモデル
    let model: String

    var name: String { t("ChatGPT（サブスク）", "ChatGPT (subscription)") }
    var supportsWebSearch: Bool { false }

    func polish(_ request: PolishRequest) async throws -> String {
        let system = request.mode == .translate ? Prompts.translateSystem : Prompts.polishSystem
        return Prompts.cleanOutput(try await CodexAppServer.shared.complete(system: system, user: Prompts.polishUser(request), model: model))
    }

    func ask(_ request: AskRequest) async throws -> AskOutcome {
        let raw = try await CodexAppServer.shared.complete(system: Prompts.askSystemJSON, user: Prompts.askUser(request), model: model)
        return Prompts.outcome(json: raw, request: request)
    }

    func analyzeStyle(samples: [StyleSample], current: StyleProfile) async throws -> StyleAnalysis {
        let raw = try await CodexAppServer.shared.complete(
            system: Prompts.styleSystem, user: Prompts.styleUser(samples: samples, current: current), model: model)
        return try JSONDecoder().decode(StyleAnalysis.self, from: Data(Prompts.extractJSON(raw).utf8))
    }
}

/// Codex の app-server（JSON-RPC のメッセージを 1 行ずつやり取りする常駐プロセス）。
/// 起動に 1 秒ほどかかるので、使っている間は動かしたままにし、10 分使わなければ終了する。
/// 応答は 1 回ごとに保存しない会話（ephemeral）を作って受け取る。
actor CodexAppServer {
    static let shared = CodexAppServer()

    struct Model: Equatable, Identifiable, Sendable {
        let id: String
        let name: String
        let efforts: [String]
        let isDefault: Bool
    }

    private struct Turn {
        var continuation: CheckedContinuation<String, Error>
        var deltas = ""
        var message: String?
        var turnID: String?
        var timeout: Task<Void, Never>?
    }

    private static let idleShutdown: Duration = .seconds(600)
    private static let turnTimeout: Duration = .seconds(60)
    private static let requestTimeout: Duration = .seconds(30)

    /// 文章の整形に要らない Codex の機能（コマンド実行・プラグイン・メモリ・フックなど）と、コーディング用の指示を止める。
    /// ユーザーの ~/.codex/config.toml は書き換えず、起動時の上書きだけで止める。~/.codex/AGENTS.md は止められないので、そのまま渡る
    static let configuration = [
        "check_for_update_on_startup=false",
        "features.apps=false", "features.plugins=false", "features.shell_tool=false", "features.unified_exec=false",
        "features.multi_agent=false", "features.image_generation=false", "features.computer_use=false",
        "features.browser_use=false", "features.hooks=false", "memories.use_memories=false",
        "include_permissions_instructions=false", "include_environment_context=false",
        "include_apps_instructions=false", "include_collaboration_mode_instructions=false",
    ]

    static var notInstalled: String {
        t("Codex が見つかりません。ターミナルで npm i -g @openai/codex（または brew install codex）を実行して入れ、codex login で ChatGPT のアカウントにログインしてください",
          "Codex was not found. Install it with npm i -g @openai/codex (or brew install codex), then run codex login with your ChatGPT account")
    }

    static var signedOut: String {
        t("Codex にログインしていません。ターミナルで codex login を実行し、ChatGPT のアカウントでログインしてください",
          "Codex is not signed in. Run codex login in Terminal and sign in with your ChatGPT account")
    }

    private var process: Process?
    private var input: FileHandle?
    private var ready = false
    private var launching: Task<Void, Error>?
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    /// 会話（thread）の ID → 返答を待っている応答
    private var turns: [String: Turn] = [:]
    /// ログインしているアカウントの説明。ログインしていなければ nil
    private var access: String?
    private var models: [Model] = []
    private var idleTask: Task<Void, Never>?

    // MARK: - 呼び出し

    /// 録音を始めたときに呼ぶ。話している間に起動を済ませておく
    func prewarm() async {
        try? await start()
        scheduleIdleShutdown()
    }

    /// 設定画面に出すログイン状態と、選べるモデル
    func status() async -> (status: SubscriptionStatus, models: [Model]) {
        do {
            try await start()
            defer { scheduleIdleShutdown() }
            // 設定画面を開いている間に codex login した場合に備えて、毎回読み直す
            try await readAccount()
            guard let access else { return (.signedOut(Self.signedOut), []) }
            return (.signedIn(access), models)
        } catch {
            if CommandLineTool.locate("codex") == nil { return (.notInstalled(Self.notInstalled), []) }
            return (.failed(error.localizedDescription), [])
        }
    }

    func complete(system: String, user: String, model: String) async throws -> String {
        try await start()
        idleTask?.cancel()
        defer { scheduleIdleShutdown() }
        if access == nil { try await readAccount() }
        guard access != nil else { throw LLMError.unavailable(Self.signedOut) }
        let model = model.isEmpty ? nil : model
        if let model, !models.isEmpty, !models.contains(where: { $0.id == model }) {
            throw LLMError.unavailable(t("Codex で \(model) を使えません。設定で別のモデルを選んでください",
                                         "\(model) is not available in Codex. Choose another model in Settings"))
        }

        var threadParams: [String: Any] = [
            "cwd": Self.workspace.path, "approvalPolicy": "never", "sandbox": "read-only", "ephemeral": true,
            // Codex のコーディング用の指示の代わりに、Speak の指示を渡す
            "baseInstructions": system,
            "config": ["web_search": "disabled"],
        ]
        if let model { threadParams["model"] = model }
        let thread = try await request("thread/start", threadParams)
        guard let threadID = (thread["thread"] as? [String: Any])?["id"] as? String else { throw LLMError.badResponse }
        var turnParams: [String: Any] = ["threadId": threadID, "input": [["type": "text", "text": user]]]
        if let effort = effort(for: model) { turnParams["effort"] = effort }

        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let timeout = Task {
                    try? await Task.sleep(for: Self.turnTimeout)
                    guard !Task.isCancelled else { return }
                    self.finish(threadID, .failure(LLMError.unavailable(t("Codex から応答がありませんでした", "Codex did not respond"))))
                }
                turns[threadID] = Turn(continuation: continuation, timeout: timeout)
                Task {
                    do { _ = try await self.request("turn/start", turnParams) } catch { self.finish(threadID, .failure(error)) }
                }
            }
        } onCancel: {
            Task { await self.finish(threadID, .failure(CancellationError())) }
        }
    }

    /// 速さを優先して、モデルが受け付けるうちで軽い推論の深さを使う
    private func effort(for model: String?) -> String? {
        let info = model.flatMap { id in models.first { $0.id == id } } ?? models.first { $0.isDefault }
        return ["low", "minimal", "none"].first { info?.efforts.contains($0) == true }
    }

    // MARK: - 起動と終了

    private func start() async throws {
        if ready, process?.isRunning == true { return }
        if let launching { return try await launching.value }
        let task = Task { try await self.launch() }
        launching = task
        defer { launching = nil }
        try await task.value
    }

    private func launch() async throws {
        stop()
        guard let codex = CommandLineTool.locate("codex") else { throw LLMError.unavailable(Self.notInstalled) }
        let environment = CommandLineTool.environment(for: codex)
        // ユーザーが Codex に設定した MCP サーバーは、会話を作るたびに起動しないよう止める
        let servers = await Self.userMCPServers(codex, environment: environment)
        var arguments: [String] = []
        for setting in Self.configuration + servers.map({ "mcp_servers.\($0).enabled=false" }) {
            arguments += ["-c", setting]
        }

        let process = Process()
        process.executableURL = codex
        process.arguments = arguments + ["app-server"]
        process.currentDirectoryURL = Self.workspace
        process.environment = environment
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { p in
            let id = ObjectIdentifier(p)
            Task { await CodexAppServer.shared.didExit(id) }
        }
        try process.run()
        // Codex が先に終わっても、書き込みで SIGPIPE を受けて Speak ごと落ちないようにする
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        self.process = process
        input = stdin.fileHandleForWriting
        let output = stdout.fileHandleForReading
        Task {
            do {
                for try await line in output.bytes.lines { self.receive(line) }
            } catch {}
        }

        do {
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
            _ = try await request("initialize", ["clientInfo": ["name": "speak", "title": "Speak", "version": version]])
            try write(["method": "initialized", "params": [String: Any]()])
            try await readAccount()
            models = (try? await listModels()) ?? []
            ready = true
        } catch {
            stop()
            throw error
        }
    }

    /// プロセスを止め、待っている呼び出しをすべて失敗させる
    private func stop() {
        idleTask?.cancel()
        if let process {
            process.terminationHandler = nil
            if process.isRunning { process.terminate() }
        }
        process = nil
        input = nil
        ready = false
        failAll(LLMError.unavailable(t("Codex が終了しました。もう一度試してください", "Codex stopped. Try again")))
    }

    private func didExit(_ id: ObjectIdentifier) {
        guard let process, ObjectIdentifier(process) == id else { return }
        self.process = nil
        stop()
    }

    private func failAll(_ error: Error) {
        let waiting = pending.values
        pending.removeAll()
        for continuation in waiting { continuation.resume(throwing: error) }
        for threadID in Array(turns.keys) { finish(threadID, .failure(error)) }
    }

    private func scheduleIdleShutdown() {
        idleTask?.cancel()
        idleTask = Task {
            try? await Task.sleep(for: Self.idleShutdown)
            guard !Task.isCancelled, turns.isEmpty, pending.isEmpty else { return }
            stop()
        }
    }

    // MARK: - アカウントとモデル

    private func readAccount() async throws {
        access = Self.access(from: try await request("account/read", ["refreshToken": false]))
    }

    private func listModels() async throws -> [Model] {
        let response = try await request("model/list", ["includeHidden": false, "limit": 100])
        return (response["data"] as? [[String: Any]] ?? []).compactMap { raw in
            guard let id = raw["model"] as? String ?? raw["id"] as? String else { return nil }
            let efforts = (raw["supportedReasoningEfforts"] as? [[String: Any]] ?? []).compactMap { $0["reasoningEffort"] as? String }
            return Model(id: id, name: raw["displayName"] as? String ?? id, efforts: efforts, isDefault: raw["isDefault"] as? Bool ?? false)
        }
    }

    /// account/read の結果を、設定画面に出す説明にする。ログインしていなければ nil
    static func access(from response: [String: Any]) -> String? {
        if let account = response["account"] as? [String: Any] {
            if account["type"] as? String == "apiKey" {
                return t("Codex に API キーでログインしています。サブスクではなく API の料金がかかります。",
                         "Codex is signed in with an API key, so usage is billed at API rates, not to your plan.")
            }
            var plan = "ChatGPT " + planName(account["planType"] as? String ?? "")
            if let email = account["email"] as? String, !email.isEmpty { plan += t("（\(email)）", " (\(email))") }
            return t("\(plan) でログインしています。使った分は Codex と同じ利用枠から引かれます。",
                     "Signed in with \(plan). Usage counts toward the same limits as Codex.")
        }
        // Codex に自分のプロバイダーを設定していると、ログインは要らない
        if response["requiresOpenaiAuth"] as? Bool == false {
            return t("Codex に設定したプロバイダーを使います。", "Uses the provider configured in Codex.")
        }
        return nil
    }

    private static func planName(_ raw: String) -> String {
        switch raw.lowercased() {
        case "free": return "Free"
        case "go": return "Go"
        case "plus": return "Plus"
        case "pro", "prolite": return "Pro"
        case "team": return "Team"
        case "business": return "Business"
        case "enterprise": return "Enterprise"
        case "edu": return "Edu"
        default: return raw.prefix(1).uppercased() + raw.dropFirst()
        }
    }

    /// ユーザーが Codex に設定した、動いている MCP サーバーの名前。
    /// プラグインを止めた状態で一覧を取る（プラグインのサーバーは止める必要がなく、名前を指定すると Codex が起動しなくなる）
    private static func userMCPServers(_ codex: URL, environment: [String: String]) async -> [String] {
        var arguments: [String] = []
        for setting in configuration { arguments += ["-c", setting] }
        guard let out = try? await CommandLineTool.run(codex, arguments: arguments + ["mcp", "list", "--json"],
                                                       directory: workspace, environment: environment, timeout: 15),
              out.status == 0
        else { return [] }
        return mcpServerNames(out.stdout)
    }

    /// `codex mcp list --json` から、止める必要のあるサーバーの名前を取り出す。
    /// 設定の上書きでは「.」などを含む名前を指定できないので、英数字・「-」・「_」だけの名前に限る
    static func mcpServerNames(_ data: Data) -> [String] {
        let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
        return list.filter { $0["enabled"] as? Bool != false }
            .compactMap { $0["name"] as? String }
            .filter { $0.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil }
    }

    /// 作業フォルダは空のフォルダにする（どこかのプロジェクトの AGENTS.md を読まないように）
    private static var workspace: URL {
        let dir = Storage.root.appendingPathComponent("Codex", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - JSON-RPC

    private func request(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
        nextID += 1
        let id = nextID
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do {
                try write(["id": id, "method": method, "params": params])
            } catch {
                pending.removeValue(forKey: id)
                continuation.resume(throwing: error)
                return
            }
            // Codex が止まっても待ち続けない（応答そのものは turn/completed で受け取るので、ここは短くてよい）
            Task {
                try? await Task.sleep(for: Self.requestTimeout)
                pending.removeValue(forKey: id)?.resume(throwing: LLMError.unavailable(t("Codex から応答がありませんでした", "Codex did not respond")))
            }
        }
    }

    private func write(_ message: [String: Any]) throws {
        guard let input else { throw LLMError.unavailable(t("Codex が起動していません", "Codex is not running")) }
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(0x0A)
        try input.write(contentsOf: data)
    }

    private func receive(_ line: String) {
        guard let message = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { return }
        if let method = message["method"] as? String {
            let params = message["params"] as? [String: Any] ?? [:]
            if let id = message["id"] {
                // Codex からの依頼（コマンド実行の承認など）は受けない。ツールを止めてあるので通常は来ない
                try? write(["id": id, "error": ["code": -32601, "message": "Speak does not handle \(method)"]])
            } else {
                handle(method, params)
            }
            return
        }
        guard let id = (message["id"] as? NSNumber)?.intValue, let continuation = pending.removeValue(forKey: id) else { return }
        if let error = message["error"] as? [String: Any] {
            continuation.resume(throwing: Self.failure(error["message"] as? String ?? ""))
        } else {
            continuation.resume(returning: message["result"] as? [String: Any] ?? [:])
        }
    }

    private func handle(_ method: String, _ params: [String: Any]) {
        let threadID = params["threadId"] as? String ?? ""
        switch method {
        case "item/agentMessage/delta":
            if let delta = params["delta"] as? String { turns[threadID]?.deltas += delta }
        case "item/completed":
            // 返答の区切りごとの全文。差分をつないだものより確か
            if let item = params["item"] as? [String: Any], item["type"] as? String == "agentMessage", let text = item["text"] as? String {
                turns[threadID]?.message = text
            }
        case "turn/started":
            turns[threadID]?.turnID = (params["turn"] as? [String: Any])?["id"] as? String
        case "turn/completed":
            guard let turn = turns[threadID] else { return }
            let result = params["turn"] as? [String: Any] ?? [:]
            if result["status"] as? String == "completed" {
                finish(threadID, .success(turn.message ?? turn.deltas))
            } else {
                finish(threadID, .failure(Self.failure((result["error"] as? [String: Any])?["message"] as? String ?? "")))
            }
        case "error":
            guard params["willRetry"] as? Bool != true else { return }
            finish(threadID, .failure(Self.failure((params["error"] as? [String: Any])?["message"] as? String ?? "")))
        case "account/updated":
            Task { try? await self.readAccount() }
        default:
            break
        }
    }

    private func finish(_ threadID: String, _ result: Result<String, Error>) {
        guard let turn = turns.removeValue(forKey: threadID) else { return }
        turn.timeout?.cancel()
        // 取り消し・時間切れのときは、Codex 側の生成も止める（応答は待たない）
        if case .failure = result, let turnID = turn.turnID {
            nextID += 1
            try? write(["id": nextID, "method": "turn/interrupt", "params": ["threadId": threadID, "turnId": turnID]])
        }
        turn.continuation.resume(with: result)
    }

    static func failure(_ message: String) -> LLMError {
        let lower = message.lowercased()
        if lower.contains("usage limit") || lower.contains("rate limit") || lower.contains("hit your limit") {
            return .unavailable(t("ChatGPT のサブスクの利用上限に達しました。上限が戻るまで待つか、設定で別の AI エンジンを選んでください",
                                  "You reached your ChatGPT plan's usage limit. Wait for it to reset or choose another AI engine in Settings"))
        }
        if lower.contains("unauthorized") || lower.contains("log in") || lower.contains("login") || lower.contains("401") {
            return .unavailable(signedOut)
        }
        if message.isEmpty { return .unavailable(t("Codex が応答を返せませんでした", "Codex could not finish the response")) }
        return .unavailable("Codex: " + message.prefix(300))
    }
}
