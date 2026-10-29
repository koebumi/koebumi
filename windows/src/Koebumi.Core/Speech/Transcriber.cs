using System.Net.Http.Headers;
using System.Text;
using System.Text.Json.Nodes;

namespace Koebumi.Core;

public sealed record TranscriptionRequest
{
    /// 話す言語（BCP-47）。先頭が主言語。
    public IReadOnlyList<string> Languages { get; init; } = [];
    /// 辞書の単語（固有名詞・専門用語）
    public IReadOnlyList<string> Vocabulary { get; init; } = [];
}

/// 音声認識の失敗の理由。Message は画面に出す文（現在の言語で作る）。
/// Apple の音声認識とこの PC で動かすモデルの分は、Windows 版にない
public sealed class TranscriptionException : Exception
{
    public enum ErrorKind { MissingKey, Http, Empty }

    public ErrorKind Kind { get; }
    /// MissingKey: サービスの名前、Http: 応答の本文
    public string Detail { get; }
    public int StatusCode { get; }

    TranscriptionException(ErrorKind kind, string detail = "", int statusCode = 0)
    {
        Kind = kind;
        Detail = detail;
        StatusCode = statusCode;
    }

    public static TranscriptionException MissingKey(string name) => new(ErrorKind.MissingKey, name);
    public static TranscriptionException Http(int code, string body) => new(ErrorKind.Http, body, code);
    public static TranscriptionException Empty() => new(ErrorKind.Empty);

    public override string Message => Kind switch
    {
        ErrorKind.MissingKey => T($"{Detail} の API キーが未設定です（設定 > 音声認識）", $"{Detail} API key is not set (Settings > Speech recognition)"),
        ErrorKind.Http => T($"音声認識エラー ({StatusCode}): ", $"Transcription error ({StatusCode}): ") + LLMText.Prefix(Detail, 200),
        _ => T("音声を認識できませんでした", "No speech was recognized"),
    };
}

/// 録音をまとめて文字にする（録音しながら逐次認識するエンジンは Windows 版にない）
public interface ITranscriber
{
    Task<string> TranscribeAsync(RecordedAudio audio, TranscriptionRequest request, CancellationToken cancellationToken = default);
}

public static class TranscriberFactory
{
    /// OpenAI・Groq・カスタム（OpenAI 互換）。API キーは secrets（資格情報マネージャー）から読む。http はテスト用
    public static ITranscriber Make(AppSettings settings, ISecretStore secrets, HttpClient? http = null)
    {
        var p = settings.SttProvider;
        return new OpenAICompatibleTranscriber(p.Title, settings.SttBaseURL(p), settings.SttModel(p), secrets.Get(p.KeyAccount), p.RequiresKey, http);
    }
}

// MARK: - OpenAI 互換の音声認識 API（OpenAI / Groq / ローカルの Whisper サーバー）

public sealed class OpenAICompatibleTranscriber(string name, string baseURL, string model, string? apiKey, bool requiresKey, HttpClient? http = null) : ITranscriber
{
    readonly HttpClient _http = http ?? LLMHttp.Shared;

    public async Task<string> TranscribeAsync(RecordedAudio audio, TranscriptionRequest request, CancellationToken cancellationToken = default)
    {
        if (requiresKey && string.IsNullOrEmpty(apiKey)) throw TranscriptionException.MissingKey(name);
        var url = LLMHttp.Endpoint(baseURL, "/audio/transcriptions") ?? throw TranscriptionException.Http(0, "invalid URL");
        var boundary = "koebumi-" + Guid.NewGuid().ToString().ToUpperInvariant();
        using var body = new MemoryStream();
        void Write(string text) => body.Write(Encoding.UTF8.GetBytes(text));
        void Field(string fieldName, string value) =>
            Write($"--{boundary}\r\nContent-Disposition: form-data; name=\"{fieldName}\"\r\n\r\n{value}\r\n");
        Field("model", model);
        Field("response_format", "json");
        Field("temperature", "0");
        // 話す言語が 1 つだけなら指定する。複数なら自動判定に任せる（混在した発話にも対応）。
        if (request.Languages.Count == 1) Field("language", Languages.IsoCode(request.Languages[0]));
        if (request.Vocabulary.Count > 0) Field("prompt", string.Join(", ", request.Vocabulary.Take(60)));
        Write($"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n");
        body.Write(WAV.Encode(audio.Normalized()));
        Write($"\r\n--{boundary}--\r\n");

        using var timer = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timer.CancelAfter(TimeSpan.FromSeconds(120));
        int status;
        byte[] data;
        try
        {
            using var req = new HttpRequestMessage(HttpMethod.Post, url) { Content = new ByteArrayContent(body.ToArray()) };
            req.Content.Headers.ContentType = MediaTypeHeaderValue.Parse($"multipart/form-data; boundary={boundary}");
            if (!string.IsNullOrEmpty(apiKey)) req.Headers.TryAddWithoutValidation("Authorization", "Bearer " + apiKey);
            using var response = await _http.SendAsync(req, timer.Token);
            status = (int)response.StatusCode;
            data = await response.Content.ReadAsByteArrayAsync(timer.Token);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw TranscriptionException.Http(0, "timed out");
        }
        if (status != 200) throw TranscriptionException.Http(status, Encoding.UTF8.GetString(data));
        var json = JsonNode.Parse(data) as JsonObject;
        return ContextText.TrimWhitespacesAndNewlines(json.Str("text") ?? "");
    }
}
