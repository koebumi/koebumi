using System.Net;
using System.Text.Json.Nodes;
using Koebumi.Core;

namespace Koebumi.Core.Tests;

public class ClaudeEngineTests
{
    const string Base = "https://claude.test/";

    static PolishRequest Request(Mode mode = Mode.Dictate) => new()
    {
        Transcript = "えーと、明日は晴れです", Mode = mode, SourceLanguages = ["ja-JP"], TargetLanguage = mode == Mode.Translate ? "en-US" : null,
        AppName = "Notes", Category = AppCategory.Other, StyleDescription = "plain",
    };

    static string TextResponse(string text, string stopReason = "end_turn") =>
        new JsonObject { ["stop_reason"] = stopReason, ["content"] = new JsonArray(new JsonObject { ["type"] = "text", ["text"] = text }) }.ToJsonString();

    static ClaudeEngine Engine(FakeHttpHandler handler, string model = ClaudeModels.Sonnet, bool webSearch = false, string key = "sk-test") =>
        new(key, model, webSearch, handler.Client, Base);

    [Fact]
    public async Task PolishSendsTheMessagesRequestAndParsesText()
    {
        var handler = FakeHttpHandler.Replying(FakeHttpHandler.Json(TextResponse("  明日は晴れです。\n")));
        var result = await Engine(handler).PolishAsync(Request());
        Assert.Equal("明日は晴れです。", result);

        var sent = Assert.Single(handler.Requests);
        Assert.Equal(HttpMethod.Post, sent.Method);
        Assert.Equal("https://claude.test/v1/messages", sent.Url.ToString());
        Assert.Equal("sk-test", sent.Header("x-api-key"));
        Assert.Equal("2023-06-01", sent.Header("anthropic-version"));
        Assert.Equal("server-side-fallback-2026-07-01", sent.Header("anthropic-beta"));
        Assert.StartsWith("application/json", sent.Header("Content-Type"));

        var body = sent.Json;
        Assert.Equal(ClaudeModels.Sonnet, (string?)body["model"]);
        Assert.Equal(16000, (int?)body["max_tokens"]);
        Assert.Equal("default", (string?)body["fallbacks"]);
        var system = Assert.Single(body["system"]!.AsArray());
        Assert.Equal("text", (string?)system!["type"]);
        Assert.Equal(Prompts.PolishSystem, (string?)system["text"]);
        Assert.Equal("ephemeral", (string?)system["cache_control"]!["type"]);
        var message = Assert.Single(body["messages"]!.AsArray());
        Assert.Equal("user", (string?)message!["role"]);
        Assert.Equal(Prompts.PolishUser(Request()), (string?)message["content"]);
        Assert.Equal("low", (string?)body["output_config"]!["effort"]);
        Assert.Null(body["tools"]);
    }

    [Fact]
    public async Task TranslationUsesTheTranslateSystemPrompt()
    {
        var handler = FakeHttpHandler.Replying(FakeHttpHandler.Json(TextResponse("<think>x</think>It is sunny.")));
        Assert.Equal("It is sunny.", await Engine(handler).PolishAsync(Request(Mode.Translate)));
        Assert.Equal(Prompts.TranslateSystem, (string?)handler.Requests[0].Json["system"]![0]!["text"]);
    }

    [Fact]
    public async Task HaikuHasNoFallbackModel()
    {
        var handler = FakeHttpHandler.Replying(FakeHttpHandler.Json(TextResponse("ok")));
        await Engine(handler, ClaudeModels.Haiku).PolishAsync(Request());
        var sent = handler.Requests[0];
        Assert.Null(sent.Header("anthropic-beta"));
        Assert.Null(sent.Json["fallbacks"]);
        Assert.Equal(ClaudeModels.Haiku, (string?)sent.Json["model"]);
    }

    [Fact]
    public async Task MissingKeyFailsWithoutSendingAnything()
    {
        var handler = FakeHttpHandler.Replying(FakeHttpHandler.Json(TextResponse("ok")));
        var e = await Assert.ThrowsAsync<LLMException>(() => Engine(handler, key: "").PolishAsync(Request()));
        Assert.Equal(LLMException.ErrorKind.MissingKey, e.Kind);
        Assert.Empty(handler.Requests);
    }

    [Fact]
    public async Task HttpErrorsCarryTheServerMessage()
    {
        var handler = FakeHttpHandler.Replying(FakeHttpHandler.Json("""{"type":"error","error":{"type":"invalid_request_error","message":"max_tokens too large"}}""", HttpStatusCode.BadRequest));
        var e = await Assert.ThrowsAsync<LLMException>(() => Engine(handler).PolishAsync(Request()));
        Assert.Equal(LLMException.ErrorKind.Http, e.Kind);
        Assert.Equal(400, e.StatusCode);
        Assert.Equal("max_tokens too large", e.Detail);
        Assert.Contains("max_tokens too large", e.Message);

        var unauthorized = FakeHttpHandler.Replying(FakeHttpHandler.Json("{}", HttpStatusCode.Unauthorized));
        var rejected = await Assert.ThrowsAsync<LLMException>(() => Engine(unauthorized).PolishAsync(Request()));
        Assert.Contains("401", rejected.Message);
    }

    [Fact]
    public async Task RefusalIsReported()
    {
        var handler = FakeHttpHandler.Replying(FakeHttpHandler.Json(TextResponse("", "refusal")));
        var e = await Assert.ThrowsAsync<LLMException>(() => Engine(handler).PolishAsync(Request()));
        Assert.Equal(LLMException.ErrorKind.Refused, e.Kind);
    }

    [Fact]
    public async Task RetriesOnOverloadAndRateLimit()
    {
        var handler = FakeHttpHandler.Replying(
            FakeHttpHandler.Json("""{"error":{"message":"overloaded"}}""", (HttpStatusCode)529, retryAfter: "0"),
            FakeHttpHandler.Json("{}", (HttpStatusCode)429, retryAfter: "0"),
            FakeHttpHandler.Json(TextResponse("ok")));
        Assert.Equal("ok", await Engine(handler).PolishAsync(Request()));
        Assert.Equal(3, handler.Requests.Count);
    }

    [Fact]
    public async Task AskOffersToolsAndReturnsTheToolCall()
    {
        var toolUse = new JsonObject
        {
            ["stop_reason"] = "tool_use",
            ["content"] = new JsonArray(
                new JsonObject { ["type"] = "text", ["text"] = "書き換えます" },
                new JsonObject { ["type"] = "tool_use", ["name"] = "replace_selection", ["input"] = new JsonObject { ["text"] = "明日は伺えません。" } }),
        };
        var handler = FakeHttpHandler.Replying(FakeHttpHandler.Json(toolUse.ToJsonString()));
        var request = new AskRequest { Query = "丁寧にして", Selection = "明日行けないわ", SelectionEditable = true, HasFocusedTextField = true, AppName = "Notes" };
        var outcome = await Engine(handler, webSearch: true).AskAsync(request);
        Assert.Equal(new AskOutcome.Replace("明日は伺えません。"), outcome);

        var body = handler.Requests[0].Json;
        Assert.Equal(Prompts.AskSystemTools, (string?)body["system"]![0]!["text"]);
        Assert.Equal("medium", (string?)body["output_config"]!["effort"]);
        Assert.Equal(Prompts.AskUser(request), (string?)body["messages"]![0]!["content"]);
        var tools = body["tools"]!.AsArray();
        Assert.Equal(["web_search", "replace_selection", "open_url"], tools.Select(t => (string?)t!["name"]));
        Assert.Equal("web_search_20260209", (string?)tools[0]!["type"]);
        Assert.Equal(3, (int?)tools[0]!["max_uses"]);
        var replace = tools[1]!;
        Assert.True((bool?)replace["strict"]);
        Assert.Equal(["text"], replace["input_schema"]!["required"]!.AsArray().Select(n => (string?)n));
        Assert.False((bool?)replace["input_schema"]!["additionalProperties"]);
        Assert.Equal(["description", "url"], tools[2]!["input_schema"]!["required"]!.AsArray().Select(n => (string?)n));
    }

    [Fact]
    public async Task AskWithoutSelectionOffersInsertAndHaikuUsesTheOlderSearchTool()
    {
        var handler = FakeHttpHandler.Replying(FakeHttpHandler.Json(TextResponse("東京は晴れです")));
        var request = new AskRequest { Query = "天気は", HasFocusedTextField = true, AppName = "Notes" };
        var outcome = await Engine(handler, ClaudeModels.Haiku, webSearch: true).AskAsync(request);
        Assert.Equal(new AskOutcome.Answer("東京は晴れです"), outcome);
        var tools = handler.Requests[0].Json["tools"]!.AsArray();
        Assert.Equal(["web_search", "insert_text", "open_url"], tools.Select(t => (string?)t!["name"]));
        Assert.Equal("web_search_20250305", (string?)tools[0]!["type"]);

        var noField = FakeHttpHandler.Replying(FakeHttpHandler.Json(TextResponse("x")));
        await Engine(noField).AskAsync(new AskRequest { Query = "q", AppName = "Notes" });
        Assert.Equal(["open_url"], noField.Requests[0].Json["tools"]!.AsArray().Select(t => (string?)t!["name"]));
    }

    [Fact]
    public async Task AskOnlyOpensWebUrls()
    {
        static string OpenUrl(string url) => new JsonObject
        {
            ["stop_reason"] = "tool_use",
            ["content"] = new JsonArray(new JsonObject { ["type"] = "tool_use", ["name"] = "open_url", ["input"] = new JsonObject { ["url"] = url, ["description"] = "検索" } }),
        }.ToJsonString();
        var request = new AskRequest { Query = "q", AppName = "Notes" };
        var good = await Engine(FakeHttpHandler.Replying(FakeHttpHandler.Json(OpenUrl("https://www.google.com/search?q=a")))).AskAsync(request);
        Assert.Equal(new AskOutcome.OpenURL(new Uri("https://www.google.com/search?q=a"), "検索"), good);
        var bad = await Engine(FakeHttpHandler.Replying(FakeHttpHandler.Json(OpenUrl("file:///c:/windows/system32/calc.exe")))).AskAsync(request);
        Assert.IsType<AskOutcome.Answer>(bad);
    }

    [Fact]
    public async Task AskResumesAPausedTurn()
    {
        var paused = new JsonObject
        {
            ["stop_reason"] = "pause_turn",
            ["content"] = new JsonArray(new JsonObject { ["type"] = "server_tool_use", ["id"] = "srv_1", ["name"] = "web_search" }),
        };
        var handler = FakeHttpHandler.Replying(FakeHttpHandler.Json(paused.ToJsonString()), FakeHttpHandler.Json(TextResponse("結果です")));
        var outcome = await Engine(handler, webSearch: true).AskAsync(new AskRequest { Query = "q", AppName = "Notes" });
        Assert.Equal(new AskOutcome.Answer("結果です"), outcome);
        Assert.Equal(2, handler.Requests.Count);
        var messages = handler.Requests[1].Json["messages"]!.AsArray();
        Assert.Equal(["user", "assistant"], messages.Select(m => (string?)m!["role"]));
        Assert.Equal("srv_1", (string?)messages[1]!["content"]![0]!["id"]);
    }

    [Fact]
    public async Task AskGivesUpWhenTheTurnKeepsPausing()
    {
        var paused = new JsonObject { ["stop_reason"] = "pause_turn", ["content"] = new JsonArray() }.ToJsonString();
        var handler = FakeHttpHandler.Replying(FakeHttpHandler.Json(paused));
        var e = await Assert.ThrowsAsync<LLMException>(() => Engine(handler).AskAsync(new AskRequest { Query = "q", AppName = "Notes" }));
        Assert.Equal(LLMException.ErrorKind.BadResponse, e.Kind);
        Assert.Equal(4, handler.Requests.Count);
    }

    [Fact]
    public async Task AnalyzeStyleAsksForAJsonSchemaAndDecodesIt()
    {
        var analysis = """{"general":"Concise.","categories":[{"category":"chat","formality":30,"verbosity":20.0,"notes":"Short."}]}""";
        var handler = FakeHttpHandler.Replying(FakeHttpHandler.Json(TextResponse(analysis)));
        var samples = new[] { new StyleSample(AppCategory.Chat, "明日の会議の件です") };
        var result = await Engine(handler).AnalyzeStyleAsync(samples, new StyleProfile());
        Assert.Equal("Concise.", result.General);
        Assert.Equal(new CategoryStyleAnalysis("chat", 30, 20, "Short."), Assert.Single(result.Categories));

        var body = handler.Requests[0].Json;
        Assert.Equal(Prompts.StyleSystem, (string?)body["system"]![0]!["text"]);
        Assert.Equal(Prompts.StyleUser(samples, new StyleProfile()), (string?)body["messages"]![0]!["content"]);
        var config = body["output_config"]!;
        Assert.Equal("low", (string?)config["effort"]);
        Assert.Equal("json_schema", (string?)config["format"]!["type"]);
        var categories = config["format"]!["schema"]!["properties"]!["categories"]!["items"]!["properties"]!["category"]!["enum"]!.AsArray();
        Assert.Equal(["email", "chat", "document", "code", "ai", "other"], categories.Select(n => (string?)n));
    }

    [Fact]
    public async Task AnalyzeStyleRejectsAMalformedAnswer()
    {
        var handler = FakeHttpHandler.Replying(FakeHttpHandler.Json(TextResponse("""{"general":"x"}""")));
        var e = await Assert.ThrowsAsync<LLMException>(() => Engine(handler).AnalyzeStyleAsync([], new StyleProfile()));
        Assert.Equal(LLMException.ErrorKind.BadResponse, e.Kind);
    }

    [Fact]
    public void NamesAndSearchSupport()
    {
        var engine = Engine(FakeHttpHandler.Replying(FakeHttpHandler.Json("{}")), webSearch: true);
        Assert.Equal("Claude", engine.Name);
        Assert.True(engine.SupportsWebSearch);
        Assert.False(Engine(FakeHttpHandler.Replying(FakeHttpHandler.Json("{}"))).SupportsWebSearch);
    }
}
