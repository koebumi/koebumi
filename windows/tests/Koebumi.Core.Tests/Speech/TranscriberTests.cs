using System.Net;
using System.Text;
using Koebumi.Core;

namespace Koebumi.Core.Tests;

public class TranscriberTests
{
    /// multipart/form-data の 1 つの部分
    sealed record Part(string Headers, byte[] Content)
    {
        public string Text => Encoding.UTF8.GetString(Content);
        public string? Name => Between("name=\"");
        public string? FileName => Between("filename=\"");

        string? Between(string prefix)
        {
            // "filename=" の中の "name=" を拾わないよう、直前が空白か先頭のものだけを見る
            int i = Headers.IndexOf(prefix, StringComparison.Ordinal);
            while (i > 0 && Headers[i - 1] != ' ') i = Headers.IndexOf(prefix, i + 1, StringComparison.Ordinal);
            if (i < 0) return null;
            i += prefix.Length;
            return Headers[i..Headers.IndexOf('"', i)];
        }
    }

    static List<Part> Parts(SentRequest sent)
    {
        var contentType = sent.Header("Content-Type")!;
        Assert.StartsWith("multipart/form-data; boundary=", contentType);
        var boundary = contentType["multipart/form-data; boundary=".Length..].Trim('"');
        // バイト列を 1 バイトずつ文字にして（Latin-1）区切りを探し、中身は元のバイトに戻す
        var raw = Encoding.Latin1.GetString(sent.Body);
        var delimiter = "--" + boundary;
        Assert.StartsWith(delimiter + "\r\n", raw);
        Assert.EndsWith(delimiter + "--\r\n", raw);
        var parts = new List<Part>();
        foreach (var chunk in raw.Split(delimiter, StringSplitOptions.RemoveEmptyEntries))
        {
            if (chunk == "--\r\n") continue;
            Assert.StartsWith("\r\n", chunk);
            Assert.EndsWith("\r\n", chunk);
            var inner = chunk[2..^2];
            int split = inner.IndexOf("\r\n\r\n", StringComparison.Ordinal);
            parts.Add(new Part(inner[..split], Encoding.Latin1.GetBytes(inner[(split + 4)..])));
        }
        return parts;
    }

    static RecordedAudio Audio() => new([0.1f, -0.2f, 0.3f, 0f, 0.05f]);

    static OpenAICompatibleTranscriber Transcriber(FakeHttpHandler handler, string? key = "sk-test", bool requiresKey = true, string baseUrl = "https://stt.test/v1/") =>
        new("OpenAI", baseUrl, "whisper-test", key, requiresKey, handler.Client);

    [Fact]
    public async Task SendsTheWavAsMultipartWithTheFields()
    {
        var handler = FakeHttpHandler.Replying(FakeHttpHandler.Json("""{"text":"  こんにちは。\n"}"""));
        var request = new TranscriptionRequest { Languages = ["ja-JP"], Vocabulary = ["Claude Code", "田中"] };
        var audio = Audio();
        var text = await Transcriber(handler).TranscribeAsync(audio, request);
        Assert.Equal("こんにちは。", text);

        var sent = Assert.Single(handler.Requests);
        Assert.Equal(HttpMethod.Post, sent.Method);
        Assert.Equal("https://stt.test/v1/audio/transcriptions", sent.Url.ToString());
        Assert.Equal("Bearer sk-test", sent.Header("Authorization"));
        var parts = Parts(sent);
        Assert.Equal(["model", "response_format", "temperature", "language", "prompt", "file"], parts.Select(p => p.Name));
        string Field(string name) => parts.Single(p => p.Name == name).Text;
        Assert.Equal("whisper-test", Field("model"));
        Assert.Equal("json", Field("response_format"));
        Assert.Equal("0", Field("temperature"));
        Assert.Equal("ja", Field("language"));
        Assert.Equal("Claude Code, 田中", Field("prompt"));
        var file = parts.Single(p => p.Name == "file");
        Assert.Equal("audio.wav", file.FileName);
        Assert.Contains("Content-Type: audio/wav", file.Headers);
        // 送るのは、音量をそろえた WAV
        Assert.Equal(WAV.Encode(audio.Normalized()), file.Content);
        Assert.Equal("RIFF", Encoding.ASCII.GetString(file.Content, 0, 4));
    }

    [Fact]
    public async Task LeavesTheLanguageToTheServerWhenSeveralAreSpokenAndOmitsAnEmptyPrompt()
    {
        var handler = FakeHttpHandler.Replying(FakeHttpHandler.Json("""{"text":"hello"}"""));
        await Transcriber(handler).TranscribeAsync(Audio(), new TranscriptionRequest { Languages = ["ja-JP", "en-US"] });
        Assert.Equal(["model", "response_format", "temperature", "file"], Parts(handler.Requests[0]).Select(p => p.Name));

        var none = FakeHttpHandler.Replying(FakeHttpHandler.Json("""{"text":"hello"}"""));
        await Transcriber(none).TranscribeAsync(Audio(), new TranscriptionRequest());
        Assert.DoesNotContain("language", Parts(none.Requests[0]).Select(p => p.Name));
    }

    [Fact]
    public async Task SendsAtMost60VocabularyTerms()
    {
        var handler = FakeHttpHandler.Replying(FakeHttpHandler.Json("""{"text":"x"}"""));
        var vocabulary = Enumerable.Range(0, 100).Select(i => "w" + i).ToList();
        await Transcriber(handler).TranscribeAsync(Audio(), new TranscriptionRequest { Languages = ["en-US"], Vocabulary = vocabulary });
        var prompt = Parts(handler.Requests[0]).Single(p => p.Name == "prompt").Text;
        Assert.Equal(string.Join(", ", vocabulary.Take(60)), prompt);
    }

    [Fact]
    public async Task ACustomServerNeedsNoKey()
    {
        var handler = FakeHttpHandler.Replying(FakeHttpHandler.Json("""{"text":"ok"}"""));
        Assert.Equal("ok", await Transcriber(handler, key: null, requiresKey: false, baseUrl: "http://localhost:8000/v1").TranscribeAsync(Audio(), new TranscriptionRequest()));
        Assert.Null(handler.Requests[0].Header("Authorization"));
        Assert.Equal("http://localhost:8000/v1/audio/transcriptions", handler.Requests[0].Url.ToString());
    }

    [Fact]
    public async Task ACloudServiceWithoutAKeyFailsBeforeSending()
    {
        var handler = FakeHttpHandler.Replying(FakeHttpHandler.Json("""{"text":"ok"}"""));
        var e = await Assert.ThrowsAsync<TranscriptionException>(() => Transcriber(handler, key: "").TranscribeAsync(Audio(), new TranscriptionRequest()));
        Assert.Equal(TranscriptionException.ErrorKind.MissingKey, e.Kind);
        Assert.Contains("OpenAI", e.Message);
        Assert.Empty(handler.Requests);
    }

    [Fact]
    public async Task ErrorsCarryTheStatusAndTheBody()
    {
        var handler = FakeHttpHandler.Replying(FakeHttpHandler.Json("""{"error":{"message":"bad audio"}}""", HttpStatusCode.BadRequest));
        var e = await Assert.ThrowsAsync<TranscriptionException>(() => Transcriber(handler).TranscribeAsync(Audio(), new TranscriptionRequest()));
        Assert.Equal(TranscriptionException.ErrorKind.Http, e.Kind);
        Assert.Equal(400, e.StatusCode);
        Assert.Equal(T("音声認識エラー (400): ", "Transcription error (400): ") + """{"error":{"message":"bad audio"}}""", e.Message);
        // 認識は再試行しない
        Assert.Single(handler.Requests);
    }

    [Fact]
    public async Task AnInvalidUrlIsAnError()
    {
        var handler = FakeHttpHandler.Replying(FakeHttpHandler.Json("""{"text":"ok"}"""));
        var e = await Assert.ThrowsAsync<TranscriptionException>(() => Transcriber(handler, baseUrl: "stt.test/v1").TranscribeAsync(Audio(), new TranscriptionRequest()));
        Assert.Equal(0, e.StatusCode);
        Assert.Empty(handler.Requests);
    }

    [Fact]
    public async Task ATimeoutIsAnErrorAndCancellationStaysACancellation()
    {
        using var cts = new CancellationTokenSource(TimeSpan.FromMilliseconds(50));
        var hanging = new OpenAICompatibleTranscriber("Custom", "http://localhost:8000/v1", "m", null, false, new HttpClient(new HangingHttpHandler()));
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => hanging.TranscribeAsync(Audio(), new TranscriptionRequest(), cts.Token));
    }

    [Fact]
    public async Task AMissingTextIsEmpty()
    {
        var handler = FakeHttpHandler.Replying(FakeHttpHandler.Json("{}"));
        Assert.Equal("", await Transcriber(handler).TranscribeAsync(Audio(), new TranscriptionRequest()));
    }

    [Fact]
    public async Task TheFactoryUsesTheProviderSettingsAndKey()
    {
        var secrets = new MemorySecretStore();
        secrets.Set("gsk-1", "groq");
        var settings = new AppSettings { SttProvider = STTProvider.Groq, SttModels = new() { ["groq"] = "whisper-large-v3" } };
        var handler = FakeHttpHandler.Replying(FakeHttpHandler.Json("""{"text":"ok"}"""));
        var transcriber = TranscriberFactory.Make(settings, secrets, handler.Client);
        Assert.Equal("ok", await transcriber.TranscribeAsync(Audio(), new TranscriptionRequest { Languages = ["en-US"] }));
        var sent = handler.Requests[0];
        Assert.Equal("https://api.groq.com/openai/v1/audio/transcriptions", sent.Url.ToString());
        Assert.Equal("Bearer gsk-1", sent.Header("Authorization"));
        Assert.Equal("whisper-large-v3", Parts(sent).Single(p => p.Name == "model").Text);

        // カスタムはキーなしで動く。キーが保存されていれば付ける
        var custom = new AppSettings { SttProvider = STTProvider.Custom };
        var local = FakeHttpHandler.Replying(FakeHttpHandler.Json("""{"text":"ok"}"""));
        await TranscriberFactory.Make(custom, new MemorySecretStore(), local.Client).TranscribeAsync(Audio(), new TranscriptionRequest());
        Assert.Equal("http://localhost:8000/v1/audio/transcriptions", local.Requests[0].Url.ToString());
        Assert.Null(local.Requests[0].Header("Authorization"));
        var noKey = await Assert.ThrowsAsync<TranscriptionException>(() =>
            TranscriberFactory.Make(new AppSettings { SttProvider = STTProvider.OpenAI }, new MemorySecretStore(), local.Client).TranscribeAsync(Audio(), new TranscriptionRequest()));
        Assert.Equal(TranscriptionException.ErrorKind.MissingKey, noKey.Kind);
    }
}
