using Koebumi.Core;

namespace Koebumi.Core.Tests;

// Mac 版の JapaneseContextTests.swift の PolisherFinishTests と、Windows 版で足した Polisher.Run の確認
public class PolisherTests
{
    static PolishRequest Request(string transcript, AppCategory category = AppCategory.Other) => new()
    {
        Transcript = transcript, SourceLanguages = ["ja-JP"], AppName = "Notes", Category = category,
        StyleDescription = category.DefaultStyleDescription,
    };

    [Fact]
    public async Task BasicCleanupAlsoFollowsNotationAndContext()
    {
        var r = new PolishRequest
        {
            Transcript = "えーと、確認して下さい", Mode = Mode.Dictate, SourceLanguages = ["ja-JP"],
            AppName = "Slack", Category = AppCategory.Chat, StyleDescription = "",
            Notation = new JapaneseNotation(), ChatPunctuation = ChatPunctuation.NoFinalPeriod,
            Surrounding = new SurroundingText { Before = "資料です。" },
        };
        var output = await Polisher.Run(r, null);
        Assert.Equal("確認してください", output.Text);
    }

    // 以下は Windows 版で足したテスト

    [Fact]
    public async Task OnlyFillersProduceNothingAndSkipTheEngine()
    {
        var engine = new FakeLLMEngine(r => r.Transcript);
        var output = await Polisher.Run(Request("えーと、あのー"), engine);
        Assert.Equal("", output.Text);
        Assert.Empty(engine.Polished);
    }

    [Fact]
    public async Task UsesAnAcceptedAIOutputAndKeepsThePlainText()
    {
        var engine = new FakeLLMEngine(_ => "明日の会議は4時にしてください。");
        var output = await Polisher.Run(Request("えーと、明日の会議は3時に、いや4時にしてください"), engine);
        Assert.Equal("明日の会議は4時にしてください。", output.Text);
        Assert.Null(output.Warning);
        Assert.Equal("明日の会議は3時に、いや4時にしてください", output.Plain);
        // AI に渡す書き起こしは、辞書とコマンドの下処理だけを通したもの（フィラーはモデルに任せる）
        Assert.Equal("えーと、明日の会議は3時に、いや4時にしてください", Assert.Single(engine.Polished).Transcript);
    }

    [Fact]
    public async Task RejectsUnnaturalOutputTwiceAndFallsBackToThePlainText()
    {
        var engine = new FakeLLMEngine(_ => "東京です。");
        var output = await Polisher.Run(Request("日本の首都はどこですか"), engine);
        Assert.Equal("日本の首都はどこですか", output.Text);
        Assert.Equal(output.Text, output.Plain);
        Assert.Null(output.Warning);
        Assert.Equal(2, engine.Polished.Count);
    }

    [Fact]
    public async Task RetriesOnceAndUsesTheSecondAnswer()
    {
        int calls = 0;
        var engine = new FakeLLMEngine(_ => ++calls == 1 ? "東京です。" : "明日は晴れです。");
        var output = await Polisher.Run(Request("明日は晴れです"), engine);
        Assert.Equal("明日は晴れです。", output.Text);
        Assert.Equal(2, calls);
    }

    [Fact]
    public async Task CasualSpeechStaysCasualUnlessTheToneAllowsPoliteness()
    {
        var engine = new FakeLLMEngine(_ => "明日の会議室はどこですか？");
        Assert.Equal("明日の会議室はどこ？", (await Polisher.Run(Request("明日の会議室はどこ"), engine)).Text);
        // メールでは、です・ます調にしてよい
        Assert.Equal("明日の会議室はどこですか？", (await Polisher.Run(Request("明日の会議室はどこ", AppCategory.Email), engine)).Text);
    }

    [Fact]
    public async Task EngineFailureStillInsertsTheTranscriptWithAWarning()
    {
        var engine = new ThrowingEngine(LLMException.Http(500, "boom"));
        var output = await Polisher.Run(Request("明日は晴れです"), engine);
        Assert.Equal("明日は晴れです", output.Text);
        Assert.StartsWith(T("AI 整形に失敗したため認識結果を入力しました: ", "AI cleanup failed, inserted the transcript: "), output.Warning);
        Assert.Contains("500", output.Warning);
    }

    [Fact]
    public async Task CancellationIsNotAFailure()
    {
        using var cts = new CancellationTokenSource();
        var engine = new ThrowingEngine(new OperationCanceledException(cts.Token));
        cts.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => Polisher.Run(Request("明日は晴れです"), engine, cts.Token));
    }

    [Fact]
    public async Task ATimeoutFromTheHttpClientIsAFailureNotACancellation()
    {
        var engine = new ThrowingEngine(new TaskCanceledException("timeout"));
        var output = await Polisher.Run(Request("明日は晴れです"), engine);
        Assert.Equal("明日は晴れです", output.Text);
        Assert.NotNull(output.Warning);
    }

    [Fact]
    public async Task TranslationNeedsAnEngine()
    {
        var r = Request("こんにちは") with { Mode = Mode.Translate, TargetLanguage = "en-US" };
        var e = await Assert.ThrowsAsync<LLMException>(() => Polisher.Run(r, null));
        Assert.Equal(LLMException.ErrorKind.Unavailable, e.Kind);
    }

    [Fact]
    public async Task TranslationRetriesOnceWhenTheModelDoesNotTranslate()
    {
        var calls = new List<string>();
        var engine = new FakeLLMEngine(r =>
        {
            calls.Add(r.Transcript);
            return calls.Count == 1 ? "こんにちは" : "Hello.";
        });
        var r = Request("えーと、こんにちは") with { Mode = Mode.Translate, TargetLanguage = "en-US" };
        var output = await Polisher.Run(r, engine);
        Assert.Equal("Hello.", output.Text);
        // 訳す前にフィラーを取り除く
        Assert.Equal(["こんにちは", "こんにちは"], calls);
    }

    [Fact]
    public async Task TranslationFailsWhenTheModelNeverTranslates()
    {
        var engine = new FakeLLMEngine(_ => "こんにちは");
        var r = Request("こんにちは") with { Mode = Mode.Translate, TargetLanguage = "en-US" };
        var e = await Assert.ThrowsAsync<LLMException>(() => Polisher.Run(r, engine));
        Assert.Equal(LLMException.ErrorKind.Unavailable, e.Kind);
        Assert.Equal(2, engine.Polished.Count);
    }

    [Fact]
    public void FitRestoresVocabularyThatStartsWithALowercaseLetter()
    {
        var r = Request("x") with { Vocabulary = ["build-app", "iPhone"] };
        Assert.Equal("build-app を開いて、iPhone も", Polisher.Fit("Build-app を開いて、IPhone も", r));
        // 別の語の一部は直さない
        Assert.Equal("Build-apps", Polisher.Fit("Build-apps", r));
    }

    [Fact]
    public void FitAppliesTheAddresseeAndGreetingOfTheReply()
    {
        var reply = new MailReplyContext { Name = "東海林", Honorific = "様", External = true };
        var r = Request("x", AppCategory.Email) with { MailReply = reply };
        Assert.Equal("東海林様、お世話になっております。", Polisher.Fit("東海林さん、お疲れ様です。", r));
    }

    [Fact]
    public void PrepareAppliesSpokenCommandsNormalizationAndAliases()
    {
        Assert.Equal("Claude Codeを開いて。\n次の件", Polisher.Prepare("クロードコードを開いて。改行。次の件", new Dictionary<string, string> { ["クロードコード"] = "Claude Code" }));
    }

    sealed class ThrowingEngine(Exception error) : ILLMEngine
    {
        public string Name => "Throwing";
        public bool SupportsWebSearch => false;
        public Task<string> PolishAsync(PolishRequest request, CancellationToken cancellationToken = default) => Task.FromException<string>(error);
        public Task<AskOutcome> AskAsync(AskRequest request, CancellationToken cancellationToken = default) => Task.FromException<AskOutcome>(error);
        public Task<StyleAnalysis> AnalyzeStyleAsync(IReadOnlyList<StyleSample> samples, StyleProfile current, CancellationToken cancellationToken = default) =>
            Task.FromException<StyleAnalysis>(error);
    }
}
