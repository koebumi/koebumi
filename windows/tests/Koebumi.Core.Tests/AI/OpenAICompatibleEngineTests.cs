using System.Net;
using System.Text.Json.Nodes;
using Koebumi.Core;

namespace Koebumi.Core.Tests;

public class OpenAICompatibleEngineTests
{
    static PolishRequest Request(Mode mode = Mode.Dictate) => new()
    {
        Transcript = "えーと、明日の会議は3時に、いや4時にしてください", Mode = mode, SourceLanguages = ["ja-JP"],
        TargetLanguage = mode == Mode.Translate ? "en-US" : null, AppName = "Notes", Category = AppCategory.Other, StyleDescription = "plain",
    };

    static string Completion(string content, string finishReason = "stop") =>
        new JsonObject
        {
            ["choices"] = new JsonArray(new JsonObject
            {
                ["index"] = 0,
                ["message"] = new JsonObject { ["role"] = "assistant", ["content"] = content },
                ["finish_reason"] = finishReason,
            }),
        }.ToJsonString();

    static OpenAICompatibleEngine Engine(FakeHttpHandler handler, CompatService service = CompatService.OpenAI, string baseUrl = "https://llm.test/v1/", string key = "sk-test") =>
        new(service, baseUrl, "test-model", key, handler.Client);

    [Fact]
    public async Task PolishSendsAChatCompletionWithExamplesAsTurns()
    {
        var handler = FakeHttpHandler.Replying(FakeHttpHandler.Json(Completion("<think>…</think>明日の会議は4時にしてください。")));
        var result = await Engine(handler).PolishAsync(Request());
        Assert.Equal("明日の会議は4時にしてください。", result);

        var sent = Assert.Single(handler.Requests);
        Assert.Equal("https://llm.test/v1/chat/completions", sent.Url.ToString());
        Assert.Equal("Bearer sk-test", sent.Header("Authorization"));
        Assert.Null(sent.Header("X-Title"));
        Assert.StartsWith("application/json", sent.Header("Content-Type"));
        var body = sent.Json;
        Assert.Equal("test-model", (string?)body["model"]);
        Assert.Null(body["response_format"]);

        var messages = body["messages"]!.AsArray();
        var examples = Prompts.Examples(Request());
        Assert.Equal(1 + examples.Count * 2 + 1, messages.Count);
        Assert.Equal("system", (string?)messages[0]!["role"]);
        Assert.Equal(Prompts.PolishRules + "\n\nOutput only the final text, with no preamble, quotes or explanation.", (string?)messages[0]!["content"]);
        Assert.Equal(("user", Prompts.ExampleUser(examples[0])), ((string?)messages[1]!["role"], (string?)messages[1]!["content"]));
        Assert.Equal(("assistant", examples[0].Output), ((string?)messages[2]!["role"], (string?)messages[2]!["content"]));
        var last = messages[^1]!;
        Assert.Equal("user", (string?)last["role"]);
        // 小さいモデルには、言い直しの指摘を足した user メッセージを渡す
        Assert.Equal(Prompts.SmallModelUser(Request()), (string?)last["content"]);
        Assert.Contains("corrected it with", (string?)last["content"]);
    }

    [Fact]
    public async Task TranslationUsesTheTranslateRules()
    {
        var handler = FakeHttpHandler.Replying(FakeHttpHandler.Json(Completion("Make it 4.")));
        await Engine(handler).PolishAsync(Request(Mode.Translate));
        var messages = handler.Requests[0].Json["messages"]!.AsArray();
        Assert.StartsWith(Prompts.TranslateRules, (string?)messages[0]!["content"]);
        Assert.Equal(1 + Prompts.TranslationExamples.Count * 2 + 1, messages.Count);
    }

    [Fact]
    public async Task OpenRouterSendsATitleAndLocalServersNeedNoKey()
    {
        var router = FakeHttpHandler.Replying(FakeHttpHandler.Json(Completion("ok")));
        await Engine(router, CompatService.OpenRouter).PolishAsync(Request());
        Assert.Equal("Koebumi", router.Requests[0].Header("X-Title"));

        var local = FakeHttpHandler.Replying(FakeHttpHandler.Json(Completion("ok")));
        await Engine(local, CompatService.Ollama, "http://localhost:11434/v1", key: "").PolishAsync(Request());
        Assert.Equal("http://localhost:11434/v1/chat/completions", local.Requests[0].Url.ToString());
        Assert.Null(local.Requests[0].Header("Authorization"));
    }

    [Fact]
    public async Task CloudServicesNeedAKey()
    {
        var handler = FakeHttpHandler.Replying(FakeHttpHandler.Json(Completion("ok")));
        var e = await Assert.ThrowsAsync<LLMException>(() => Engine(handler, CompatService.Groq, key: "").PolishAsync(Request()));
        Assert.Equal(LLMException.ErrorKind.MissingKey, e.Kind);
        Assert.Contains("Groq", e.Message);
        Assert.Empty(handler.Requests);
    }

    [Fact]
    public async Task InvalidBaseUrlIsReported()
    {
        var handler = FakeHttpHandler.Replying(FakeHttpHandler.Json(Completion("ok")));
        var e = await Assert.ThrowsAsync<LLMException>(() => Engine(handler, baseUrl: "not a url").PolishAsync(Request()));
        Assert.Equal(LLMException.ErrorKind.Unavailable, e.Kind);
        var scheme = await Assert.ThrowsAsync<LLMException>(() => Engine(handler, baseUrl: "localhost:11434/v1").PolishAsync(Request()));
        Assert.Equal(LLMException.ErrorKind.Unavailable, scheme.Kind);
        Assert.Empty(handler.Requests);
    }

    [Fact]
    public async Task ContentFilterIsRefusedAndOddResponsesAreBad()
    {
        var filtered = FakeHttpHandler.Replying(FakeHttpHandler.Json(Completion("", "content_filter")));
        Assert.Equal(LLMException.ErrorKind.Refused, (await Assert.ThrowsAsync<LLMException>(() => Engine(filtered).PolishAsync(Request()))).Kind);
        foreach (var json in new[] { """{"choices":[]}""", """{"id":"x"}""", "[]", "not json" })
        {
            var odd = FakeHttpHandler.Replying(FakeHttpHandler.Json(json));
            Assert.Equal(LLMException.ErrorKind.BadResponse, (await Assert.ThrowsAsync<LLMException>(() => Engine(odd).PolishAsync(Request()))).Kind);
        }
        var nullContent = FakeHttpHandler.Replying(FakeHttpHandler.Json("""{"choices":[{"message":{"role":"assistant","content":null}}]}"""));
        Assert.Equal("", await Engine(nullContent).PolishAsync(Request()));
    }

    [Fact]
    public async Task ErrorsCarryTheServerMessage()
    {
        var handler = FakeHttpHandler.Replying(FakeHttpHandler.Json("""{"error":{"message":"model not found","type":"invalid_request_error"}}""", HttpStatusCode.NotFound));
        var e = await Assert.ThrowsAsync<LLMException>(() => Engine(handler).PolishAsync(Request()));
        Assert.Equal(404, e.StatusCode);
        Assert.Equal("model not found", e.Detail);
        Assert.Equal(T("AI エラー", "AI error") + " (404): model not found", e.Message);
    }

    [Fact]
    public async Task RetriesOnRateLimit()
    {
        var handler = FakeHttpHandler.Replying(
            FakeHttpHandler.Json("""{"error":{"message":"slow down"}}""", HttpStatusCode.TooManyRequests, retryAfter: "0"),
            FakeHttpHandler.Json(Completion("ok")));
        Assert.Equal("ok", await Engine(handler).PolishAsync(Request()));
        Assert.Equal(2, handler.Requests.Count);
    }

    [Fact]
    public async Task AskAsksForAJsonObjectAndParsesTheAction()
    {
        var answer = """{"action": "open_url", "text": "YouTube を開きます", "url": "https://www.youtube.com/results?search_query=cats"}""";
        var handler = FakeHttpHandler.Replying(FakeHttpHandler.Json(Completion(answer)));
        var request = new AskRequest { Query = "猫の動画を開いて", AppName = "Notes", HasFocusedTextField = true };
        var outcome = await Engine(handler).AskAsync(request);
        Assert.Equal(new AskOutcome.OpenURL(new Uri("https://www.youtube.com/results?search_query=cats"), "YouTube を開きます"), outcome);

        var body = handler.Requests[0].Json;
        Assert.Equal("json_object", (string?)body["response_format"]!["type"]);
        var messages = body["messages"]!.AsArray();
        Assert.Equal(2, messages.Count);
        Assert.Equal(Prompts.AskSystemJSON, (string?)messages[0]!["content"]);
        Assert.Equal(Prompts.AskUser(request), (string?)messages[1]!["content"]);
    }

    [Fact]
    public async Task AskRetriesWithoutResponseFormatWhenTheModelRejectsIt()
    {
        var handler = FakeHttpHandler.Replying(
            FakeHttpHandler.Json("""{"error":{"message":"response_format is not supported"}}""", HttpStatusCode.BadRequest),
            FakeHttpHandler.Json(Completion("ただの回答です")));
        var outcome = await Engine(handler).AskAsync(new AskRequest { Query = "q", AppName = "Notes" });
        Assert.Equal(new AskOutcome.Answer("ただの回答です"), outcome);
        Assert.Equal(2, handler.Requests.Count);
        Assert.NotNull(handler.Requests[0].Json["response_format"]);
        Assert.Null(handler.Requests[1].Json["response_format"]);

        // JSON を求めない整形の 400 は、そのまま失敗にする
        var polish = FakeHttpHandler.Replying(FakeHttpHandler.Json("{}", HttpStatusCode.BadRequest));
        await Assert.ThrowsAsync<LLMException>(() => Engine(polish).PolishAsync(Request()));
        Assert.Single(polish.Requests);
    }

    [Fact]
    public async Task AnalyzeStyleReadsJsonInsideACodeFence()
    {
        var content = "```json\n{\"general\":\"Short and direct.\",\"categories\":[{\"category\":\"email\",\"formality\":80,\"verbosity\":40,\"notes\":\"Polite.\"}]}\n```";
        var handler = FakeHttpHandler.Replying(FakeHttpHandler.Json(Completion(content)));
        var samples = new[] { new StyleSample(AppCategory.Email, "お世話になっております。") };
        var result = await Engine(handler).AnalyzeStyleAsync(samples, new StyleProfile());
        Assert.Equal("Short and direct.", result.General);
        Assert.Equal(new CategoryStyleAnalysis("email", 80, 40, "Polite."), Assert.Single(result.Categories));
        var body = handler.Requests[0].Json;
        Assert.Equal("json_object", (string?)body["response_format"]!["type"]);
        Assert.Equal(Prompts.StyleSystem, (string?)body["messages"]![0]!["content"]);
    }

    [Fact]
    public void NameIsTheServiceTitle()
    {
        var engine = Engine(FakeHttpHandler.Replying(FakeHttpHandler.Json("{}")), CompatService.Gemini);
        Assert.Equal("Google Gemini", engine.Name);
        Assert.False(engine.SupportsWebSearch);
    }
}
