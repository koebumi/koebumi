import Foundation

/// OpenAI 互換の Chat Completions API（BYOK）。OpenAI・Groq・OpenRouter・Gemini・Ollama・LM Studio などで動く。
struct OpenAICompatibleEngine: LLMEngine {
    let service: CompatService
    let baseURL: String
    let model: String
    let apiKey: String

    var name: String { service.title }
    var supportsWebSearch: Bool { false }

    /// 例は会話の往復として渡す（Ollama などの小さいモデルでも従いやすい）
    func polish(_ request: PolishRequest) async throws -> String {
        let system = (request.mode == .translate ? Prompts.translateRules : Prompts.polishRules) + "\n\nOutput only the final text, with no preamble, quotes or explanation."
        var history: [[String: String]] = []
        for e in Prompts.examples(for: request) {
            history.append(["role": "user", "content": Prompts.exampleUser(e)])
            history.append(["role": "assistant", "content": e.output])
        }
        return Prompts.cleanOutput(try await chat(system: system, history: history, user: Prompts.smallModelUser(request), json: false))
    }

    func ask(_ request: AskRequest) async throws -> AskOutcome {
        Prompts.outcome(json: try await chat(system: Prompts.askSystemJSON, user: Prompts.askUser(request), json: true), request: request)
    }

    func analyzeStyle(samples: [StyleSample], current: StyleProfile) async throws -> StyleAnalysis {
        let raw = try await chat(system: Prompts.styleSystem, user: Prompts.styleUser(samples: samples, current: current), json: true)
        return try JSONDecoder().decode(StyleAnalysis.self, from: Data(Prompts.extractJSON(raw).utf8))
    }

    private func chat(system: String, history: [[String: String]] = [], user: String, json: Bool) async throws -> String {
        if service.requiresKey && apiKey.isEmpty { throw LLMError.missingKey(service.title) }
        guard let url = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions") else {
            throw LLMError.unavailable(t("ベース URL が正しくありません", "Invalid base URL"))
        }
        var body: [String: Any] = [
            "model": model,
            "messages": [["role": "system", "content": system]] + history + [["role": "user", "content": user]],
        ]
        if json { body["response_format"] = ["type": "json_object"] }
        var headers: [String: String] = [:]
        if !apiKey.isEmpty { headers["Authorization"] = "Bearer \(apiKey)" }
        if service == .openrouter { headers["X-Title"] = "Speak" }

        var (status, data) = try await HTTP.postJSON(url: url, headers: headers, body: body)
        if status == 400, json {
            // response_format に対応しないモデル向けに、指定なしで再試行する
            body.removeValue(forKey: "response_format")
            (status, data) = try await HTTP.postJSON(url: url, headers: headers, body: body)
        }
        guard status == 200 else { throw LLMError.http(status, HTTP.errorMessage(data)) }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any]
        else { throw LLMError.badResponse }
        if choices.first?["finish_reason"] as? String == "content_filter" { throw LLMError.refused }
        return message["content"] as? String ?? ""
    }
}
