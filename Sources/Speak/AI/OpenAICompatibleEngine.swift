import Foundation

/// OpenAI 互換の Chat Completions API（BYOK）。OpenAI・Groq・OpenRouter・Gemini・Ollama・LM Studio などで動く。
struct OpenAICompatibleEngine: LLMEngine {
    let service: CompatService
    let baseURL: String
    let model: String
    let apiKey: String

    var name: String { service.title }
    var supportsWebSearch: Bool { false }

    func polish(_ request: PolishRequest) async throws -> String {
        let system = request.mode == .translate ? Prompts.translateSystem : Prompts.polishSystem
        return Prompts.cleanOutput(try await chat(system: system, user: Prompts.polishUser(request), json: false))
    }

    func ask(_ request: AskRequest) async throws -> AskOutcome {
        let raw = try await chat(system: Prompts.askSystemJSON, user: Prompts.askUser(request), json: true)
        guard let obj = try? JSONSerialization.jsonObject(with: Data(Prompts.extractJSON(raw).utf8)) as? [String: Any] else {
            return .answer(Prompts.stripThinking(raw))
        }
        return Prompts.outcome(
            action: obj["action"] as? String ?? "answer",
            text: obj["text"] as? String ?? "",
            url: obj["url"] as? String ?? "",
            request: request
        )
    }

    func analyzeStyle(samples: [StyleSample], current: StyleProfile) async throws -> StyleAnalysis {
        let raw = try await chat(system: Prompts.styleSystem, user: Prompts.styleUser(samples: samples, current: current), json: true)
        return try JSONDecoder().decode(StyleAnalysis.self, from: Data(Prompts.extractJSON(raw).utf8))
    }

    private func chat(system: String, user: String, json: Bool) async throws -> String {
        if service.requiresKey && apiKey.isEmpty { throw LLMError.missingKey(service.title) }
        guard let url = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions") else {
            throw LLMError.unavailable(t("ベース URL が正しくありません", "Invalid base URL"))
        }
        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
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
