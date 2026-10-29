using System.Globalization;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Koebumi.Core;

/// AI の呼び出しが失敗した理由。Message は画面に出す文（現在の言語で作る）
public sealed class LLMException : Exception
{
    public enum ErrorKind { MissingKey, Http, Refused, ContextTooLong, Unavailable, BadResponse }

    public ErrorKind Kind { get; }
    /// MissingKey: サービスの名前、Http: サーバーのエラーメッセージ、Unavailable: 理由
    public string Detail { get; }
    /// Http のときの状態コード
    public int StatusCode { get; }

    LLMException(ErrorKind kind, string detail = "", int statusCode = 0)
    {
        Kind = kind;
        Detail = detail;
        StatusCode = statusCode;
    }

    public static LLMException MissingKey(string name) => new(ErrorKind.MissingKey, name);
    public static LLMException Http(int code, string message) => new(ErrorKind.Http, message, code);
    public static LLMException Refused() => new(ErrorKind.Refused);
    public static LLMException ContextTooLong() => new(ErrorKind.ContextTooLong);
    public static LLMException Unavailable(string reason) => new(ErrorKind.Unavailable, reason);
    public static LLMException BadResponse() => new(ErrorKind.BadResponse);

    public override string Message => Kind switch
    {
        ErrorKind.MissingKey => T($"{Detail} の API キーが未設定です（設定 > 整形（AI））", $"{Detail} API key is not set (Settings > Polish (AI))"),
        ErrorKind.Http when StatusCode is 401 or 403 => T("API キーが無効です", "The API key was rejected") + $" ({StatusCode})",
        ErrorKind.Http when StatusCode == 429 => T("API の利用上限に達しました。しばらく待ってから再試行してください", "Rate limited by the API. Try again shortly"),
        ErrorKind.Http => T("AI エラー", "AI error") + $" ({StatusCode}): " + LLMText.Prefix(Detail, 200),
        ErrorKind.Refused => T("AI がこの内容の処理を断りました", "The model declined this request"),
        ErrorKind.ContextTooLong => T("内容が長すぎてこのモデルでは処理できません", "The text is too long for this model"),
        ErrorKind.Unavailable => Detail,
        _ => T("AI から予期しない応答がありました", "Unexpected response from the AI"),
    };
}

public interface ILLMEngine
{
    string Name { get; }
    bool SupportsWebSearch { get; }
    Task<string> PolishAsync(PolishRequest request, CancellationToken cancellationToken = default);
    Task<AskOutcome> AskAsync(AskRequest request, CancellationToken cancellationToken = default);
    Task<StyleAnalysis> AnalyzeStyleAsync(IReadOnlyList<StyleSample> samples, StyleProfile current, CancellationToken cancellationToken = default);
}

/// Windows 版で使える整形エンジン（Claude・OpenAI 互換）。Apple のオンデバイスモデルと、Claude Code・Codex 経由は Windows 版にない
public static class LLMFactory
{
    /// 整形しない設定なら null。API キーは secrets（資格情報マネージャー）から読む。http はテスト用
    public static ILLMEngine? Make(AppSettings settings, ISecretStore secrets, HttpClient? http = null)
    {
        switch (settings.LlmProvider)
        {
            case LLMProvider.None:
                return null;
            case LLMProvider.Claude:
                return new ClaudeEngine(secrets.Get(AppSettings.ClaudeKeyAccount) ?? "", settings.ClaudeModel, settings.WebSearch, http);
            default:
                var s = settings.CompatService;
                return new OpenAICompatibleEngine(s, settings.CompatBaseURL(s), settings.CompatModel(s), secrets.Get(s.KeyAccount) ?? "", http);
        }
    }
}

/// HTTP の共通処理（429 / 5xx は少し待って最大 2 回まで再試行）。HttpClient は 1 つを使い回す
public static class LLMHttp
{
    static readonly Lazy<HttpClient> SharedClient = new(() => new HttpClient { Timeout = Timeout.InfiniteTimeSpan });

    /// アプリ全体で使い回す HttpClient（要求ごとの時間切れは PostJsonAsync で測る）
    public static HttpClient Shared => SharedClient.Value;

    static readonly JsonSerializerOptions BodyOptions = new() { Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping };

    /// body を JSON で POST する。状態コードと本文を返す（200 以外でも例外にしない）。
    /// 429・529・5xx は最大 2 回まで再試行する。待つ時間は retry-after（秒）か、なければ 1 回目 1 秒・2 回目 2 秒で、8 秒まで
    public static async Task<(int Status, byte[] Data)> PostJsonAsync(
        HttpClient client, Uri url, IReadOnlyDictionary<string, string> headers, JsonNode body,
        TimeSpan? timeout = null, CancellationToken cancellationToken = default)
    {
        var payload = JsonSerializer.SerializeToUtf8Bytes(body, BodyOptions);
        var limit = timeout ?? TimeSpan.FromSeconds(90);
        int attempt = 0;
        while (true)
        {
            int status;
            byte[] data;
            double? retryAfter = null;
            using (var timer = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken))
            {
                timer.CancelAfter(limit);
                try
                {
                    using var request = new HttpRequestMessage(HttpMethod.Post, url) { Content = new ByteArrayContent(payload) };
                    request.Content.Headers.ContentType = new MediaTypeHeaderValue("application/json");
                    foreach (var (k, v) in headers) request.Headers.TryAddWithoutValidation(k, v);
                    using var response = await client.SendAsync(request, timer.Token);
                    status = (int)response.StatusCode;
                    if (response.Headers.TryGetValues("retry-after", out var values)
                        && double.TryParse(values.FirstOrDefault(), NumberStyles.Float, CultureInfo.InvariantCulture, out var seconds))
                    {
                        retryAfter = seconds;
                    }
                    data = await response.Content.ReadAsByteArrayAsync(timer.Token);
                }
                catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
                {
                    throw LLMException.Unavailable(T("AI の応答がありませんでした（時間切れ）", "The AI did not respond in time"));
                }
            }
            var retryable = status is 429 or 529 or (>= 500 and <= 599);
            if (retryable && attempt < 2)
            {
                attempt++;
                var wait = retryAfter is { } r && double.IsFinite(r) ? r : attempt;
                await Task.Delay(TimeSpan.FromSeconds(Math.Clamp(wait, 0, 8)), cancellationToken);
                continue;
            }
            return (status, data);
        }
    }

    /// エラーの応答から、人が読むメッセージを取り出す
    public static string ErrorMessage(byte[] data)
    {
        try
        {
            if (JsonNode.Parse(data) is JsonObject json)
            {
                if (json["error"] is JsonObject err && err.Str("message") is { } message) return message;
                if (json.Str("error") is { } error) return error;
                if (json.Str("message") is { } text) return text;
            }
        }
        catch (JsonException) { }
        return Encoding.UTF8.GetString(data, 0, Math.Min(data.Length, 300));
    }

    /// 応答の本文を JSON のオブジェクトとして読む。読めなければ BadResponse
    public static JsonObject ParseObject(byte[] data)
    {
        try
        {
            if (JsonNode.Parse(data) is JsonObject json) return json;
        }
        catch (JsonException) { }
        throw LLMException.BadResponse();
    }

    /// 200 以外の応答を LLMException にする
    public static void EnsureOk(int status, byte[] data)
    {
        if (status != 200) throw LLMException.Http(status, ErrorMessage(data));
    }

    /// ベース URL の末尾の「/」を取って path をつなぐ。http(s) の URL でなければ null
    public static Uri? Endpoint(string baseUrl, string path) =>
        Uri.TryCreate(baseUrl.Trim('/') + path, UriKind.Absolute, out var uri) && uri.Scheme is "http" or "https" ? uri : null;
}

/// JsonNode から値を取り出す小さな道具
internal static class JsonNodes
{
    extension(JsonNode? node)
    {
        public JsonNode? Get(string key) => node is JsonObject o && o.TryGetPropertyValue(key, out var v) ? v : null;

        public string? Str(string key) => node.Get(key) is JsonValue v && v.TryGetValue<string>(out var s) ? s : null;

        public JsonArray? Arr(string key) => node.Get(key) as JsonArray;
    }
}

internal static class LLMText
{
    /// 先頭の count 文字（書記素クラスター）。Swift の `prefix(count)`
    public static string Prefix(string s, int count)
    {
        var info = new StringInfo(s);
        return info.LengthInTextElements <= count ? s : info.SubstringByTextElements(0, count);
    }
}
