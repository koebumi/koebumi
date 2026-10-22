import Foundation

enum LLMError: LocalizedError {
    case missingKey(String)
    case http(Int, String)
    case refused
    case contextTooLong
    case unavailable(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .missingKey(let name):
            return t("\(name) の API キーが未設定です（設定 > AI エンジン）", "\(name) API key is not set (Settings > AI engines)")
        case .http(let code, let message):
            if code == 401 || code == 403 { return t("API キーが無効です", "The API key was rejected") + " (\(code))" }
            if code == 429 { return t("API の利用上限に達しました。しばらく待ってから再試行してください", "Rate limited by the API. Try again shortly") }
            return t("AI エラー", "AI error") + " (\(code)): " + message.prefix(200)
        case .refused:
            return t("AI がこの内容の処理を断りました", "The model declined this request")
        case .contextTooLong:
            return t("内容が長すぎてこのモデルでは処理できません", "The text is too long for this model")
        case .unavailable(let reason):
            return reason
        case .badResponse:
            return t("AI から予期しない応答がありました", "Unexpected response from the AI")
        }
    }
}

/// サブスクで動かすエンジン（Claude Code・Codex）の状態。設定画面に出す
enum SubscriptionStatus: Equatable {
    case notInstalled(String)
    case signedOut(String)
    case signedIn(String)
    case failed(String)

    var isReady: Bool {
        if case .signedIn = self { return true }
        return false
    }

    var detail: String {
        switch self {
        case .notInstalled(let s), .signedOut(let s), .signedIn(let s), .failed(let s): return s
        }
    }
}

protocol LLMEngine: Sendable {
    var name: String { get }
    var supportsWebSearch: Bool { get }
    func polish(_ request: PolishRequest) async throws -> String
    func ask(_ request: AskRequest) async throws -> AskOutcome
    func analyzeStyle(samples: [StyleSample], current: StyleProfile) async throws -> StyleAnalysis
}

enum LLMFactory {
    @MainActor
    static func make(settings: AppSettings) -> LLMEngine? {
        switch settings.llmProvider {
        case .none:
            return nil
        case .appleOnDevice:
            return AppleLLMEngine()
        case .claude:
            return ClaudeEngine(apiKey: Keychain.get("anthropic") ?? "", model: settings.claudeModel, webSearch: settings.webSearch)
        case .claudeCode:
            return ClaudeCodeEngine(model: settings.claudeModel)
        case .codex:
            return CodexEngine(model: settings.codexModel)
        case .openAICompatible:
            let s = settings.compatService
            return OpenAICompatibleEngine(
                service: s,
                baseURL: settings.compatBaseURL(s),
                model: settings.compatModel(s),
                apiKey: Keychain.get(s.keyAccount) ?? ""
            )
        }
    }
}

/// HTTP の共通処理（429 / 5xx は少し待って最大 2 回まで再試行）
enum HTTP {
    static func postJSON(url: URL, headers: [String: String], body: [String: Any], timeout: TimeInterval = 90) async throws -> (Int, Data) {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        var attempt = 0
        while true {
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            let retryable = status == 429 || status == 529 || (500...599).contains(status)
            if retryable, attempt < 2 {
                attempt += 1
                let wait = Double(http?.value(forHTTPHeaderField: "retry-after") ?? "") ?? Double(attempt)
                try await Task.sleep(for: .seconds(min(wait, 8)))
                continue
            }
            return (status, data)
        }
    }

    static func errorMessage(_ data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let err = json["error"] as? [String: Any], let msg = err["message"] as? String { return msg }
            if let msg = json["error"] as? String { return msg }
            if let msg = json["message"] as? String { return msg }
        }
        return String(decoding: data.prefix(300), as: UTF8.self)
    }
}
