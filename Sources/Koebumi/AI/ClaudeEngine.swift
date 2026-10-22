import Foundation

/// Claude（Anthropic Messages API）。Swift には公式 SDK がないため HTTP で直接呼ぶ。
struct ClaudeEngine: LLMEngine {
    let apiKey: String
    let model: String
    let webSearch: Bool

    var name: String { "Claude" }
    var supportsWebSearch: Bool { webSearch }

    /// ANTHROPIC_BASE_URL で接続先を変えられる（公式 SDK と同じ環境変数。テストやプロキシ用）
    private static var endpoint: URL {
        let base = ProcessInfo.processInfo.environment["ANTHROPIC_BASE_URL"] ?? "https://api.anthropic.com"
        return URL(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/v1/messages")!
    }
    private static let fallbackBeta = "server-side-fallback-2026-07-01"

    private var isHaiku: Bool { model.contains("haiku") }

    func polish(_ request: PolishRequest) async throws -> String {
        let system = request.mode == .translate ? Prompts.translateSystem : Prompts.polishSystem
        let response = try await send(
            system: system,
            messages: [["role": "user", "content": Prompts.polishUser(request)]],
            outputConfig: ["effort": "low"]
        )
        return Prompts.cleanOutput(Self.text(of: response))
    }

    func ask(_ request: AskRequest) async throws -> AskOutcome {
        var tools: [[String: Any]] = []
        if webSearch {
            tools.append(["type": isHaiku ? "web_search_20250305" : "web_search_20260209", "name": "web_search", "max_uses": 3])
        }
        let hasSelection = request.selection?.isEmpty == false
        if hasSelection && request.selectionEditable {
            tools.append(Self.clientTool("replace_selection", "Replace the user's selected text with new text.", ["text": "The full replacement text for the selection."]))
        }
        if !hasSelection && request.hasFocusedTextField {
            tools.append(Self.clientTool("insert_text", "Insert newly written text at the user's cursor.", ["text": "The text to insert."]))
        }
        tools.append(Self.clientTool("open_url", "Open a web page in the user's browser.", [
            "url": "Direct http(s) URL to open, such as a search URL.",
            "description": "Short description of what is being opened, in the user's language.",
        ]))

        var messages: [[String: Any]] = [["role": "user", "content": Prompts.askUser(request)]]
        for _ in 0..<4 {
            let response = try await send(system: Prompts.askSystemTools, messages: messages, outputConfig: ["effort": "medium"], tools: tools)
            let content = response["content"] as? [[String: Any]] ?? []
            if response["stop_reason"] as? String == "pause_turn" {
                // サーバー側のツール実行が途中で止まった。応答をそのまま返すと続きから再開する。
                messages.append(["role": "assistant", "content": content])
                continue
            }
            for block in content where block["type"] as? String == "tool_use" {
                let input = block["input"] as? [String: Any] ?? [:]
                switch block["name"] as? String {
                case "replace_selection":
                    if let text = input["text"] as? String { return .replace(text) }
                case "insert_text":
                    if let text = input["text"] as? String { return .insert(text) }
                case "open_url":
                    if let s = input["url"] as? String, let url = URL(string: s) {
                        return .openURL(url, input["description"] as? String ?? s)
                    }
                default:
                    break
                }
            }
            return .answer(Self.text(of: response))
        }
        throw LLMError.badResponse
    }

    func analyzeStyle(samples: [StyleSample], current: StyleProfile) async throws -> StyleAnalysis {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "general": ["type": "string"],
                "categories": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "category": ["type": "string", "enum": AppCategory.allCases.map(\.rawValue)],
                            "formality": ["type": "integer"],
                            "verbosity": ["type": "integer"],
                            "notes": ["type": "string"],
                        ],
                        "required": ["category", "formality", "verbosity", "notes"],
                        "additionalProperties": false,
                    ],
                ],
            ],
            "required": ["general", "categories"],
            "additionalProperties": false,
        ]
        let response = try await send(
            system: Prompts.styleSystem,
            messages: [["role": "user", "content": Prompts.styleUser(samples: samples, current: current)]],
            outputConfig: ["effort": "low", "format": ["type": "json_schema", "schema": schema]]
        )
        let json = Self.text(of: response)
        return try JSONDecoder().decode(StyleAnalysis.self, from: Data(json.utf8))
    }

    // MARK: - HTTP

    private static func clientTool(_ name: String, _ description: String, _ props: [String: String]) -> [String: Any] {
        [
            "name": name,
            "description": description,
            "strict": true,
            "input_schema": [
                "type": "object",
                "properties": props.mapValues { ["type": "string", "description": $0] },
                "required": Array(props.keys).sorted(),
                "additionalProperties": false,
            ],
        ]
    }

    private func send(system: String, messages: [[String: Any]], outputConfig: [String: Any], tools: [[String: Any]] = []) async throws -> [String: Any] {
        guard !apiKey.isEmpty else { throw LLMError.missingKey("Anthropic") }
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "system": [["type": "text", "text": system, "cache_control": ["type": "ephemeral"]]],
            "messages": messages,
            "output_config": outputConfig,
        ]
        if !tools.isEmpty { body["tools"] = tools }
        var headers = ["x-api-key": apiKey, "anthropic-version": "2023-06-01"]
        // 安全性フィルタで断られたとき、サーバー側で推奨モデルに自動で切り替える（Haiku には代替モデルがない）
        if !isHaiku {
            body["fallbacks"] = "default"
            headers["anthropic-beta"] = Self.fallbackBeta
        }

        let (status, data) = try await HTTP.postJSON(url: Self.endpoint, headers: headers, body: body, timeout: 120)
        guard status == 200 else { throw LLMError.http(status, HTTP.errorMessage(data)) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw LLMError.badResponse }
        if json["stop_reason"] as? String == "refusal" { throw LLMError.refused }
        return json
    }

    private static func text(of response: [String: Any]) -> String {
        let content = response["content"] as? [[String: Any]] ?? []
        return content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
