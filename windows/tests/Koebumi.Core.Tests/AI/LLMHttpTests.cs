using System.Net;
using System.Text;
using System.Text.Json.Nodes;
using Koebumi.Core;

namespace Koebumi.Core.Tests;

public class LLMHttpTests
{
    static readonly Uri Url = new("https://api.test/v1/x");
    static readonly Dictionary<string, string> Headers = new() { ["x-custom"] = "yes" };
    static readonly JsonObject Body = new() { ["text"] = "日本語" };

    [Fact]
    public async Task PostsTheJsonBodyWithHeaders()
    {
        var handler = FakeHttpHandler.Replying(FakeHttpHandler.Json("""{"ok":true}"""));
        var (status, data) = await LLMHttp.PostJsonAsync(handler.Client, Url, Headers, Body);
        Assert.Equal(200, status);
        Assert.Equal("""{"ok":true}""", Encoding.UTF8.GetString(data));
        var sent = Assert.Single(handler.Requests);
        Assert.Equal(HttpMethod.Post, sent.Method);
        Assert.Equal("yes", sent.Header("x-custom"));
        Assert.Equal("application/json", sent.Header("Content-Type"));
        // 日本語は \u の形にせず、そのまま送る
        Assert.Equal("""{"text":"日本語"}""", sent.Text);
    }

    [Fact]
    public async Task RetriesOn429ThenSucceeds()
    {
        var handler = FakeHttpHandler.Replying(
            FakeHttpHandler.Json("{}", HttpStatusCode.TooManyRequests, retryAfter: "0"),
            FakeHttpHandler.Json("""{"ok":true}"""));
        var (status, _) = await LLMHttp.PostJsonAsync(handler.Client, Url, Headers, Body);
        Assert.Equal(200, status);
        Assert.Equal(2, handler.Requests.Count);
        // 再試行でも同じ本文を送る
        Assert.Equal(handler.Requests[0].Text, handler.Requests[1].Text);
    }

    [Theory]
    [InlineData(429)]
    [InlineData(500)]
    [InlineData(503)]
    [InlineData(529)]
    public async Task GivesUpAfterTwoRetries(int code)
    {
        var handler = FakeHttpHandler.Replying(FakeHttpHandler.Json("""{"error":"busy"}""", (HttpStatusCode)code, retryAfter: "0"));
        var (status, data) = await LLMHttp.PostJsonAsync(handler.Client, Url, Headers, Body);
        Assert.Equal(code, status);
        Assert.Equal("busy", LLMHttp.ErrorMessage(data));
        Assert.Equal(3, handler.Requests.Count);
    }

    [Theory]
    [InlineData(400)]
    [InlineData(401)]
    [InlineData(404)]
    public async Task DoesNotRetryClientErrors(int code)
    {
        var handler = FakeHttpHandler.Replying(FakeHttpHandler.Json("{}", (HttpStatusCode)code));
        var (status, _) = await LLMHttp.PostJsonAsync(handler.Client, Url, Headers, Body);
        Assert.Equal(code, status);
        Assert.Single(handler.Requests);
    }

    [Fact]
    public async Task WaitingBetweenRetriesCanBeCancelled()
    {
        // retry-after が長くても取り消せる（待つのは最大 8 秒）
        var handler = FakeHttpHandler.Replying(FakeHttpHandler.Json("{}", HttpStatusCode.TooManyRequests, retryAfter: "100"));
        using var cts = new CancellationTokenSource(TimeSpan.FromMilliseconds(100));
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => LLMHttp.PostJsonAsync(handler.Client, Url, Headers, Body, cancellationToken: cts.Token));
        Assert.Single(handler.Requests);
    }

    [Fact]
    public async Task ATimeoutBecomesAnUnavailableError()
    {
        using var client = new HttpClient(new HangingHttpHandler());
        var e = await Assert.ThrowsAsync<LLMException>(() => LLMHttp.PostJsonAsync(client, Url, Headers, Body, TimeSpan.FromMilliseconds(50)));
        Assert.Equal(LLMException.ErrorKind.Unavailable, e.Kind);
    }

    [Fact]
    public async Task CancellationStaysACancellation()
    {
        using var client = new HttpClient(new HangingHttpHandler());
        using var cts = new CancellationTokenSource(TimeSpan.FromMilliseconds(50));
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => LLMHttp.PostJsonAsync(client, Url, Headers, Body, cancellationToken: cts.Token));
    }

    [Fact]
    public void ExtractsErrorMessages()
    {
        static string Message(string json) => LLMHttp.ErrorMessage(Encoding.UTF8.GetBytes(json));
        Assert.Equal("nested", Message("""{"error":{"message":"nested","type":"x"}}"""));
        Assert.Equal("plain error", Message("""{"error":"plain error"}"""));
        Assert.Equal("top level", Message("""{"message":"top level"}"""));
        Assert.Equal("""{"detail":"other"}""", Message("""{"detail":"other"}"""));
        Assert.Equal("<html>bad gateway</html>", Message("<html>bad gateway</html>"));
        Assert.Equal(300, LLMHttp.ErrorMessage(Encoding.UTF8.GetBytes(new string('a', 1000))).Length);
    }

    [Fact]
    public void EndpointJoinsTheBaseUrlAndPath()
    {
        Assert.Equal("https://api.test/v1/chat/completions", LLMHttp.Endpoint("https://api.test/v1/", "/chat/completions")?.ToString());
        Assert.Equal("http://localhost:1234/v1/audio/transcriptions", LLMHttp.Endpoint("http://localhost:1234/v1", "/audio/transcriptions")?.ToString());
        Assert.Null(LLMHttp.Endpoint("", "/x"));
        Assert.Null(LLMHttp.Endpoint("ftp://host/v1", "/x"));
        Assert.Null(LLMHttp.Endpoint("file:///c:/x", "/y"));
    }
}

/// 表示言語（アプリ全体で 1 つ）を切り替えるので、ほかのテストと同時に動かさない
[Collection(DataFilesCollection.Name)]
public class LLMExceptionMessageTests
{
    [Fact]
    public void MessagesAreWrittenInTheCurrentLanguage()
    {
        var original = L10n.Current;
        try
        {
            L10n.Current = UILanguage.En;
            Assert.Equal("Claude API key is not set (Settings > Polish (AI))", LLMException.MissingKey("Claude").Message);
            Assert.Equal("The API key was rejected (401)", LLMException.Http(401, "x").Message);
            Assert.Equal("The API key was rejected (403)", LLMException.Http(403, "x").Message);
            Assert.Equal("Rate limited by the API. Try again shortly", LLMException.Http(429, "x").Message);
            Assert.Equal("AI error (500): " + new string('a', 200), LLMException.Http(500, new string('a', 300)).Message);
            Assert.Equal("The model declined this request", LLMException.Refused().Message);
            Assert.Equal("The text is too long for this model", LLMException.ContextTooLong().Message);
            Assert.Equal("because", LLMException.Unavailable("because").Message);
            Assert.Equal("Unexpected response from the AI", LLMException.BadResponse().Message);
            L10n.Current = UILanguage.Ja;
            Assert.Equal("Claude の API キーが未設定です（設定 > 整形（AI））", LLMException.MissingKey("Claude").Message);
        }
        finally
        {
            L10n.Current = original;
        }
    }
}

public class LLMFactoryTests
{
    static AppSettings Settings(LLMProvider provider) => new() { LlmProvider = provider };

    [Fact]
    public void NoneMeansNoEngine()
    {
        Assert.Null(LLMFactory.Make(Settings(LLMProvider.None), new MemorySecretStore()));
    }

    [Fact]
    public async Task ClaudeReadsTheAnthropicKeyAndSettings()
    {
        var secrets = new MemorySecretStore();
        secrets.Set("sk-ant-1", "anthropic");
        var settings = Settings(LLMProvider.Claude);
        settings.ClaudeModel = ClaudeModels.Sonnet;
        settings.WebSearch = true;
        var handler = FakeHttpHandler.Replying(FakeHttpHandler.Json("""{"content":[{"type":"text","text":"ok"}]}"""));
        var engine = LLMFactory.Make(settings, secrets, handler.Client);
        var claude = Assert.IsType<ClaudeEngine>(engine);
        Assert.True(claude.SupportsWebSearch);
        // ANTHROPIC_BASE_URL が未設定なら公式の接続先
        if (string.IsNullOrEmpty(Environment.GetEnvironmentVariable("ANTHROPIC_BASE_URL")))
        {
            await claude.PolishAsync(new PolishRequest { Transcript = "x" });
            var sent = Assert.Single(handler.Requests);
            Assert.Equal("https://api.anthropic.com/v1/messages", sent.Url.ToString());
            Assert.Equal("sk-ant-1", sent.Header("x-api-key"));
            Assert.Equal(ClaudeModels.Sonnet, (string?)sent.Json["model"]);
        }
    }

    [Fact]
    public async Task OpenAICompatibleReadsTheServiceKeyUrlAndModel()
    {
        var secrets = new MemorySecretStore();
        secrets.Set("gsk-1", "groq");
        var settings = Settings(LLMProvider.OpenAICompatible);
        settings.CompatService = CompatService.Groq;
        settings.CompatModels = new() { ["groq"] = "my-model" };
        var handler = FakeHttpHandler.Replying(FakeHttpHandler.Json("""{"choices":[{"message":{"content":"ok"}}]}"""));
        var engine = Assert.IsType<OpenAICompatibleEngine>(LLMFactory.Make(settings, secrets, handler.Client));
        Assert.Equal("Groq", engine.Name);
        await engine.PolishAsync(new PolishRequest { Transcript = "x", SourceLanguages = ["en-US"] });
        var sent = Assert.Single(handler.Requests);
        Assert.Equal("https://api.groq.com/openai/v1/chat/completions", sent.Url.ToString());
        Assert.Equal("Bearer gsk-1", sent.Header("Authorization"));
        Assert.Equal("my-model", (string?)sent.Json["model"]);
    }

    [Fact]
    public async Task ACustomServerWithoutAKeyWorks()
    {
        var settings = Settings(LLMProvider.OpenAICompatible);
        settings.CompatService = CompatService.Custom;
        settings.CompatBaseURLs = new() { ["custom"] = "http://127.0.0.1:9000/v1" };
        var handler = FakeHttpHandler.Replying(FakeHttpHandler.Json("""{"choices":[{"message":{"content":"ok"}}]}"""));
        var engine = LLMFactory.Make(settings, new MemorySecretStore(), handler.Client)!;
        await engine.PolishAsync(new PolishRequest { Transcript = "x", SourceLanguages = ["en-US"] });
        Assert.Equal("http://127.0.0.1:9000/v1/chat/completions", handler.Requests[0].Url.ToString());
        Assert.Null(handler.Requests[0].Header("Authorization"));
    }
}
