using System.Net;
using System.Text;
using System.Text.Json.Nodes;
using Koebumi.Core;

namespace Koebumi.Core.Tests;

/// 送った HTTP リクエストの記録
internal sealed record SentRequest(HttpMethod Method, Uri Url, IReadOnlyDictionary<string, string> Headers, byte[] Body)
{
    public string Text => Encoding.UTF8.GetString(Body);
    public JsonNode Json => JsonNode.Parse(Body)!;
    public string? Header(string name) => Headers.TryGetValue(name, out var v) ? v : null;
}

/// 決まった応答を返す偽の HTTP の送り先。n 番目のリクエストには n 番目の応答を返す（足りなければ最後の応答）
internal sealed class FakeHttpHandler(Func<int, SentRequest, HttpResponseMessage> respond) : HttpMessageHandler
{
    public List<SentRequest> Requests { get; } = [];

    public HttpClient Client => new(this);

    public static FakeHttpHandler Replying(params Func<HttpResponseMessage>[] responses) =>
        new((i, _) => responses[Math.Min(i, responses.Length - 1)]());

    public static Func<HttpResponseMessage> Json(string json, HttpStatusCode status = HttpStatusCode.OK, string? retryAfter = null) => () =>
    {
        var response = new HttpResponseMessage(status) { Content = new StringContent(json, Encoding.UTF8, "application/json") };
        if (retryAfter is not null) response.Headers.TryAddWithoutValidation("Retry-After", retryAfter);
        return response;
    };

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var h in request.Headers) headers[h.Key] = string.Join(",", h.Value);
        if (request.Content is not null)
        {
            foreach (var h in request.Content.Headers) headers[h.Key] = string.Join(",", h.Value);
        }
        var body = request.Content is null ? [] : await request.Content.ReadAsByteArrayAsync(cancellationToken);
        var sent = new SentRequest(request.Method, request.RequestUri!, headers, body);
        int index;
        lock (Requests)
        {
            index = Requests.Count;
            Requests.Add(sent);
        }
        return respond(index, sent);
    }
}

/// 応答を返さずに待ち続ける偽の HTTP の送り先（時間切れと取り消しの確認用）
internal sealed class HangingHttpHandler : HttpMessageHandler
{
    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        await Task.Delay(Timeout.Infinite, cancellationToken);
        throw new InvalidOperationException();
    }
}

/// 呼ばれた内容を記録して、決めた文を返す偽の AI
internal sealed class FakeLLMEngine(Func<PolishRequest, string> polish) : ILLMEngine
{
    public List<PolishRequest> Polished { get; } = [];
    public string Name => "Fake";
    public bool SupportsWebSearch => false;

    public Task<string> PolishAsync(PolishRequest request, CancellationToken cancellationToken = default)
    {
        Polished.Add(request);
        return Task.FromResult(polish(request));
    }

    public Task<AskOutcome> AskAsync(AskRequest request, CancellationToken cancellationToken = default) =>
        Task.FromResult<AskOutcome>(new AskOutcome.Answer(""));

    public Task<StyleAnalysis> AnalyzeStyleAsync(IReadOnlyList<StyleSample> samples, StyleProfile current, CancellationToken cancellationToken = default) =>
        Task.FromResult(new StyleAnalysis("", []));
}
