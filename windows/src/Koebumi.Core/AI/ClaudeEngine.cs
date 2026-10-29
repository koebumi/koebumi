using System.Text.Json.Nodes;

namespace Koebumi.Core;

/// Claude（Anthropic Messages API）。HTTP で直接呼ぶ。
/// baseUrl を省くと環境変数 ANTHROPIC_BASE_URL（公式 SDK と同じ。テストやプロキシ用）、それもなければ https://api.anthropic.com
public sealed class ClaudeEngine(string apiKey, string model, bool webSearch, HttpClient? http = null, string? baseUrl = null) : ILLMEngine
{
    const string FallbackBeta = "server-side-fallback-2026-07-01";

    readonly HttpClient _http = http ?? LLMHttp.Shared;

    public string Name => "Claude";
    public bool SupportsWebSearch => webSearch;

    Uri Endpoint
    {
        get
        {
            var env = Environment.GetEnvironmentVariable("ANTHROPIC_BASE_URL");
            var b = baseUrl ?? (string.IsNullOrEmpty(env) ? "https://api.anthropic.com" : env);
            return LLMHttp.Endpoint(b, "/v1/messages")
                ?? throw LLMException.Unavailable(T("ベース URL が正しくありません", "Invalid base URL"));
        }
    }

    bool IsHaiku => model.Contains("haiku", StringComparison.Ordinal);

    public async Task<string> PolishAsync(PolishRequest request, CancellationToken cancellationToken = default)
    {
        var system = request.Mode == Mode.Translate ? Prompts.TranslateSystem : Prompts.PolishSystem;
        var response = await SendAsync(
            system,
            [new JsonObject { ["role"] = "user", ["content"] = Prompts.PolishUser(request) }],
            new JsonObject { ["effort"] = "low" },
            null,
            cancellationToken);
        return Prompts.CleanOutput(TextOf(response));
    }

    public async Task<AskOutcome> AskAsync(AskRequest request, CancellationToken cancellationToken = default)
    {
        var tools = new JsonArray();
        if (webSearch)
        {
            tools.Add(new JsonObject
            {
                ["type"] = IsHaiku ? "web_search_20250305" : "web_search_20260209",
                ["name"] = "web_search",
                ["max_uses"] = 3,
            });
        }
        var hasSelection = !string.IsNullOrEmpty(request.Selection);
        if (hasSelection && request.SelectionEditable)
        {
            tools.Add(ClientTool("replace_selection", "Replace the user's selected text with new text.", ("text", "The full replacement text for the selection.")));
        }
        if (!hasSelection && request.HasFocusedTextField)
        {
            tools.Add(ClientTool("insert_text", "Insert newly written text at the user's cursor.", ("text", "The text to insert.")));
        }
        tools.Add(ClientTool("open_url", "Open a web page in the user's browser.",
            ("url", "Direct http(s) URL to open, such as a search URL."),
            ("description", "Short description of what is being opened, in the user's language.")));

        var messages = new List<JsonObject> { new() { ["role"] = "user", ["content"] = Prompts.AskUser(request) } };
        for (int i = 0; i < 4; i++)
        {
            var response = await SendAsync(Prompts.AskSystemTools, messages, new JsonObject { ["effort"] = "medium" }, tools, cancellationToken);
            var content = response.Arr("content") ?? [];
            if (response.Str("stop_reason") == "pause_turn")
            {
                // サーバー側のツール実行が途中で止まった。応答をそのまま返すと続きから再開する。
                messages.Add(new JsonObject { ["role"] = "assistant", ["content"] = content.DeepClone() });
                continue;
            }
            foreach (var block in content)
            {
                if (block.Str("type") != "tool_use") continue;
                var input = block.Get("input");
                switch (block.Str("name"))
                {
                    case "replace_selection":
                        if (input.Str("text") is { } replacement) return new AskOutcome.Replace(replacement);
                        break;
                    case "insert_text":
                        if (input.Str("text") is { } text) return new AskOutcome.Insert(text);
                        break;
                    case "open_url":
                        // 開くのは http(s) だけ（Mac 版は JSON 経由のときだけ確かめる）
                        if (input.Str("url") is { } s && Prompts.WebUrl(s) is { } url)
                            return new AskOutcome.OpenURL(url, input.Str("description") ?? s);
                        break;
                }
            }
            return new AskOutcome.Answer(TextOf(response));
        }
        throw LLMException.BadResponse();
    }

    public async Task<StyleAnalysis> AnalyzeStyleAsync(IReadOnlyList<StyleSample> samples, StyleProfile current, CancellationToken cancellationToken = default)
    {
        var categories = new JsonArray();
        foreach (var category in Enum.GetValues<AppCategory>()) categories.Add(Storage.Raw(category));
        var schema = new JsonObject
        {
            ["type"] = "object",
            ["properties"] = new JsonObject
            {
                ["general"] = new JsonObject { ["type"] = "string" },
                ["categories"] = new JsonObject
                {
                    ["type"] = "array",
                    ["items"] = new JsonObject
                    {
                        ["type"] = "object",
                        ["properties"] = new JsonObject
                        {
                            ["category"] = new JsonObject { ["type"] = "string", ["enum"] = categories },
                            ["formality"] = new JsonObject { ["type"] = "integer" },
                            ["verbosity"] = new JsonObject { ["type"] = "integer" },
                            ["notes"] = new JsonObject { ["type"] = "string" },
                        },
                        ["required"] = new JsonArray("category", "formality", "verbosity", "notes"),
                        ["additionalProperties"] = false,
                    },
                },
            },
            ["required"] = new JsonArray("general", "categories"),
            ["additionalProperties"] = false,
        };
        var response = await SendAsync(
            Prompts.StyleSystem,
            [new JsonObject { ["role"] = "user", ["content"] = Prompts.StyleUser(samples, current) }],
            new JsonObject { ["effort"] = "low", ["format"] = new JsonObject { ["type"] = "json_schema", ["schema"] = schema } },
            null,
            cancellationToken);
        return StyleAnalysis.Decode(TextOf(response));
    }

    // MARK: - HTTP

    /// 文字列を 1 つずつ受け取るツールの定義（引数の名前の順に required に並べる）
    static JsonObject ClientTool(string name, string description, params (string Name, string Description)[] props)
    {
        var properties = new JsonObject();
        foreach (var (propName, propDescription) in props)
        {
            properties[propName] = new JsonObject { ["type"] = "string", ["description"] = propDescription };
        }
        return new JsonObject
        {
            ["name"] = name,
            ["description"] = description,
            ["strict"] = true,
            ["input_schema"] = new JsonObject
            {
                ["type"] = "object",
                ["properties"] = properties,
                ["required"] = new JsonArray([.. props.Select(p => p.Name).Order(StringComparer.Ordinal).Select(n => (JsonNode)JsonValue.Create(n)!)]),
                ["additionalProperties"] = false,
            },
        };
    }

    async Task<JsonObject> SendAsync(string system, IReadOnlyList<JsonObject> messages, JsonObject outputConfig, JsonArray? tools, CancellationToken cancellationToken)
    {
        if (apiKey.Length == 0) throw LLMException.MissingKey("Anthropic");
        var body = new JsonObject
        {
            ["model"] = model,
            ["max_tokens"] = 16000,
            ["system"] = new JsonArray(new JsonObject
            {
                ["type"] = "text",
                ["text"] = system,
                ["cache_control"] = new JsonObject { ["type"] = "ephemeral" },
            }),
            ["messages"] = new JsonArray([.. messages.Select(m => (JsonNode)m.DeepClone())]),
            ["output_config"] = outputConfig.DeepClone(),
        };
        if (tools is { Count: > 0 }) body["tools"] = tools.DeepClone();
        var headers = new Dictionary<string, string> { ["x-api-key"] = apiKey, ["anthropic-version"] = "2023-06-01" };
        // 安全性フィルタで断られたとき、サーバー側で推奨モデルに自動で切り替える（Haiku には代替モデルがない）
        if (!IsHaiku)
        {
            body["fallbacks"] = "default";
            headers["anthropic-beta"] = FallbackBeta;
        }

        var (status, data) = await LLMHttp.PostJsonAsync(_http, Endpoint, headers, body, TimeSpan.FromSeconds(120), cancellationToken);
        LLMHttp.EnsureOk(status, data);
        var json = LLMHttp.ParseObject(data);
        if (json.Str("stop_reason") == "refusal") throw LLMException.Refused();
        return json;
    }

    static string TextOf(JsonObject response)
    {
        var texts = (response.Arr("content") ?? []).Where(b => b.Str("type") == "text").Select(b => b.Str("text")).OfType<string>();
        return ContextText.TrimWhitespacesAndNewlines(string.Concat(texts));
    }
}
