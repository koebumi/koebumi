using System.Text.Json.Nodes;

namespace Koebumi.Core;

/// OpenAI 互換の Chat Completions API（BYOK）。OpenAI・Groq・OpenRouter・Gemini・Ollama・LM Studio などで動く。
public sealed class OpenAICompatibleEngine(CompatService service, string baseURL, string model, string apiKey, HttpClient? http = null) : ILLMEngine
{
    readonly HttpClient _http = http ?? LLMHttp.Shared;

    public string Name => service.Title;
    public bool SupportsWebSearch => false;

    /// 例は会話の往復として渡す（Ollama などの小さいモデルでも従いやすい）
    public async Task<string> PolishAsync(PolishRequest request, CancellationToken cancellationToken = default)
    {
        var system = (request.Mode == Mode.Translate ? Prompts.TranslateRules : Prompts.PolishRules)
            + "\n\nOutput only the final text, with no preamble, quotes or explanation.";
        var history = new List<(string Role, string Content)>();
        foreach (var e in Prompts.Examples(request))
        {
            history.Add(("user", Prompts.ExampleUser(e)));
            history.Add(("assistant", e.Output));
        }
        return Prompts.CleanOutput(await ChatAsync(system, history, Prompts.SmallModelUser(request), json: false, cancellationToken));
    }

    public async Task<AskOutcome> AskAsync(AskRequest request, CancellationToken cancellationToken = default) =>
        Prompts.Outcome(await ChatAsync(Prompts.AskSystemJSON, [], Prompts.AskUser(request), json: true, cancellationToken), request);

    public async Task<StyleAnalysis> AnalyzeStyleAsync(IReadOnlyList<StyleSample> samples, StyleProfile current, CancellationToken cancellationToken = default)
    {
        var raw = await ChatAsync(Prompts.StyleSystem, [], Prompts.StyleUser(samples, current), json: true, cancellationToken);
        return StyleAnalysis.Decode(Prompts.ExtractJSON(raw));
    }

    async Task<string> ChatAsync(string system, IReadOnlyList<(string Role, string Content)> history, string user, bool json, CancellationToken cancellationToken)
    {
        if (service.RequiresKey && apiKey.Length == 0) throw LLMException.MissingKey(service.Title);
        var url = LLMHttp.Endpoint(baseURL, "/chat/completions")
            ?? throw LLMException.Unavailable(T("ベース URL が正しくありません", "Invalid base URL"));
        var messages = new JsonArray(new JsonObject { ["role"] = "system", ["content"] = system });
        foreach (var (role, content) in history) messages.Add(new JsonObject { ["role"] = role, ["content"] = content });
        messages.Add(new JsonObject { ["role"] = "user", ["content"] = user });
        var body = new JsonObject { ["model"] = model, ["messages"] = messages };
        if (json) body["response_format"] = new JsonObject { ["type"] = "json_object" };
        var headers = new Dictionary<string, string>();
        if (apiKey.Length > 0) headers["Authorization"] = "Bearer " + apiKey;
        if (service == CompatService.OpenRouter) headers["X-Title"] = "Koebumi";

        var (status, data) = await LLMHttp.PostJsonAsync(_http, url, headers, body, cancellationToken: cancellationToken);
        if (status == 400 && json)
        {
            // response_format に対応しないモデル向けに、指定なしで再試行する
            body.Remove("response_format");
            (status, data) = await LLMHttp.PostJsonAsync(_http, url, headers, body, cancellationToken: cancellationToken);
        }
        LLMHttp.EnsureOk(status, data);
        var obj = LLMHttp.ParseObject(data);
        if (obj.Arr("choices") is not { Count: > 0 } choices || choices[0].Get("message") is not JsonObject message) throw LLMException.BadResponse();
        if (choices[0].Str("finish_reason") == "content_filter") throw LLMException.Refused();
        return message.Str("content") ?? "";
    }
}
