using System.Text.Json;
using Koebumi.Core;

namespace Koebumi.Core.Tests;

// Mac 版の PersonalizationTests.swift の PersonalizationStoreTests。
// StylePromptTests.appleStyleInstructionsDoNotShowTheJSONFormat は Apple のモデルだけの話なので移していない
public class PersonalizationStoreTests
{
    static StyleSample Sample(int i) => new(AppCategory.Chat, $"明日の会議の件です {i}");

    static async Task WaitUntilIdle(PersonalizationStore store)
    {
        for (int i = 0; i < 500 && store.IsAnalyzing; i++) await Task.Delay(10);
        Assert.False(store.IsAnalyzing);
    }

    [Fact]
    public async Task FailedAnalysisWaitsForAnotherBatchBeforeRetrying()
    {
        var engine = new FakeStyleEngine(FakeStyleEngine.Behavior.Fail);
        var store = new PersonalizationStore(inMemory: true);
        for (int i = 0; i < PersonalizationStore.BatchSize; i++) store.AddSample(Sample(i), engine);
        // 6 件目で自動の学習が始まる。Mac 版は analyze で終わりを待つが、ここでは終わるのを待つだけにする
        // （失敗はすぐ終わるので、待つ前に終わっていると analyze はもう一度学習を始めてしまう）
        await WaitUntilIdle(store);
        Assert.Equal(1, engine.Calls);
        Assert.NotNull(store.LastError);

        // 失敗した直後は、話すたびに学習し直さない
        for (int i = 0; i < PersonalizationStore.BatchSize - 1; i++) store.AddSample(Sample(10 + i), engine);
        await WaitUntilIdle(store);
        Assert.Equal(1, engine.Calls);
        store.AddSample(Sample(20), engine);
        await WaitUntilIdle(store);
        Assert.Equal(2, engine.Calls);
    }

    [Fact]
    public async Task AnalysisThatNeverFinishesTimesOut()
    {
        var engine = new FakeStyleEngine(FakeStyleEngine.Behavior.Hang);
        var store = new PersonalizationStore(inMemory: true, timeout: TimeSpan.FromMilliseconds(100));
        for (int i = 0; i < PersonalizationStore.BatchSize; i++) store.AddSample(Sample(i), engine);
        await store.AnalyzeAsync(engine);
        Assert.NotNull(store.LastError);
        Assert.Equal(PersonalizationStore.BatchSize, store.PendingCount);
    }

    [Fact]
    public async Task CancelledAnalysisIsRetriedOnTheNextSample()
    {
        var engine = new FakeStyleEngine(FakeStyleEngine.Behavior.Hang);
        var store = new PersonalizationStore(inMemory: true);
        for (int i = 0; i < PersonalizationStore.BatchSize; i++) store.AddSample(Sample(i), engine);
        await engine.WaitForCall();
        store.CancelAnalysis();
        // Mac 版は analyze で終わりを待つが、ここでは取り消した学習がすぐ終わって、待つ前に新しい学習が始まらないよう、終わるのを待つだけにする
        await WaitUntilIdle(store);
        // 取り消しは失敗ではない
        Assert.Null(store.LastError);

        store.AddSample(Sample(10), engine);
        Assert.True(store.IsAnalyzing);
        store.CancelAnalysis();
        await WaitUntilIdle(store);
        Assert.Null(store.LastError);
        Assert.Equal(PersonalizationStore.BatchSize + 1, store.PendingCount);
    }

    // 以下は Windows 版で足したテスト

    [Fact]
    public async Task SuccessfulAnalysisUpdatesTheProfileAndConsumesTheBatch()
    {
        var engine = new FakeStyleEngine(FakeStyleEngine.Behavior.Succeed);
        var store = new PersonalizationStore(inMemory: true);
        int changes = 0;
        store.Changed += (_, _) => Interlocked.Increment(ref changes);
        for (int i = 0; i < PersonalizationStore.BatchSize; i++) store.AddSample(Sample(i), engine);
        await store.AnalyzeAsync(engine);
        Assert.Null(store.LastError);
        Assert.False(store.IsAnalyzing);
        Assert.Equal(0, store.PendingCount);
        Assert.Equal("Direct.", store.Profile.General);
        Assert.Equal(new CategoryProfile(100, 0, "Casual."), store.Profile.Categories["chat"]);
        Assert.Equal(PersonalizationStore.BatchSize, store.Profile.SamplesAnalyzed);
        Assert.NotNull(store.Profile.UpdatedAt);
        Assert.Equal(PersonalizationStore.BatchSize, engine.LastSamples.Count);
        Assert.Equal(PersonalizationStore.BatchSize / (double)PersonalizationStore.FullProgressSamples, store.Progress, 6);
        Assert.True(changes >= PersonalizationStore.BatchSize + 2);
    }

    [Fact]
    public void ShortSamplesAreIgnoredAndNothingIsAnalyzedWithoutAnEngine()
    {
        var store = new PersonalizationStore(inMemory: true);
        store.AddSample(new StyleSample(AppCategory.Chat, "短い"), null);
        Assert.Equal(0, store.PendingCount);
        for (int i = 0; i < PersonalizationStore.BatchSize + 2; i++) store.AddSample(Sample(i), null);
        Assert.Equal(PersonalizationStore.BatchSize + 2, store.PendingCount);
        Assert.False(store.IsAnalyzing);
    }

    [Fact]
    public async Task AnalyzeWithoutSamplesDoesNothing()
    {
        var engine = new FakeStyleEngine(FakeStyleEngine.Behavior.Succeed);
        var store = new PersonalizationStore(inMemory: true);
        await store.AnalyzeAsync(engine);
        Assert.Equal(0, engine.Calls);
    }

    [Fact]
    public void ApplyClampsScoresIgnoresUnknownCategoriesAndKeepsEarlierNotes()
    {
        var store = new PersonalizationStore(inMemory: true);
        store.Apply(new StyleAnalysis("First.", [
            new CategoryStyleAnalysis("email", 150, -5, "Polite."),
            new CategoryStyleAnalysis("Email", 10, 10, "wrong case"),
            new CategoryStyleAnalysis("unknown", 10, 10, "ignored"),
        ]), 3);
        Assert.Equal(["email"], store.Profile.Categories.Keys);
        Assert.Equal(new CategoryProfile(100, 0, "Polite."), store.Profile.Categories["email"]);
        // 空の general は前の内容を残す
        store.Apply(new StyleAnalysis("", [new CategoryStyleAnalysis("chat", 20, 30, "Short.")]), 2);
        Assert.Equal("First.", store.Profile.General);
        Assert.Equal(["chat", "email"], store.Profile.Categories.Keys.Order());
        Assert.Equal(5, store.Profile.SamplesAnalyzed);
    }

    [Fact]
    public void CorrectionsKeepTheLatest30AndSkipNoOps()
    {
        var store = new PersonalizationStore(inMemory: true);
        store.AddCorrection(new Correction("same", "same"));
        Assert.Empty(store.Corrections);
        for (int i = 0; i < 35; i++) store.AddCorrection(new Correction("a" + i, "b" + i));
        Assert.Equal(30, store.Corrections.Count);
        Assert.Equal("a5", store.Corrections[0].Original);
        Assert.Equal("a34", store.Corrections[^1].Original);
    }

    [Fact]
    public void SavesToAFileInTheMacFormatAndReloads()
    {
        using var folder = new DataTestFolder();
        var store = new PersonalizationStore(folder.Path);
        store.AddSample(Sample(1), null);
        store.AddCorrection(new Correction("原文", "修正"));
        store.Apply(new StyleAnalysis("Direct.", [new CategoryStyleAnalysis("code", 40, 20, "Terse.")]), 4);

        var json = JsonDocument.Parse(File.ReadAllText(Path.Combine(folder.Path, PersonalizationStore.FileName))).RootElement;
        Assert.Equal("Direct.", json.GetProperty("profile").GetProperty("general").GetString());
        Assert.Equal(4, json.GetProperty("profile").GetProperty("samplesAnalyzed").GetInt32());
        Assert.Equal(40, json.GetProperty("profile").GetProperty("categories").GetProperty("code").GetProperty("formality").GetInt32());
        // 日時は秒までの ISO 8601
        Assert.Matches(@"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$", json.GetProperty("profile").GetProperty("updatedAt").GetString());
        Assert.Equal("chat", json.GetProperty("pending")[0].GetProperty("category").GetString());
        Assert.Equal("原文", json.GetProperty("corrections")[0].GetProperty("original").GetString());

        var reloaded = new PersonalizationStore(folder.Path);
        Assert.Equal(store.Profile.General, reloaded.Profile.General);
        Assert.Equal(store.Profile.Categories["code"], reloaded.Profile.Categories["code"]);
        Assert.Equal(store.Profile.UpdatedAt?.ToUnixTimeSeconds(), reloaded.Profile.UpdatedAt?.ToUnixTimeSeconds());
        Assert.Equal(1, reloaded.PendingCount);
        Assert.Equal([new Correction("原文", "修正")], reloaded.Corrections);

        reloaded.Reset();
        Assert.Equal(0, reloaded.PendingCount);
        Assert.Empty(reloaded.Corrections);
        Assert.Equal("", reloaded.Profile.General);
        Assert.Equal(0, new PersonalizationStore(folder.Path).PendingCount);
    }

    [Fact]
    public void ReadsAFileWrittenByTheMacVersion()
    {
        using var folder = new DataTestFolder();
        File.WriteAllText(Path.Combine(folder.Path, PersonalizationStore.FileName), """
            {"profile":{"general":"Concise.","categories":{"email":{"formality":80,"verbosity":40,"notes":"Polite."}},"samplesAnalyzed":12,"updatedAt":"2026-10-20T01:02:03Z"},
             "pending":[{"category":"ai","text":"この関数を直して"}],
             "corrections":[{"original":"a","preferred":"b"}]}
            """);
        var store = new PersonalizationStore(folder.Path);
        Assert.Equal("Concise.", store.Profile.General);
        Assert.Equal(12, store.Profile.SamplesAnalyzed);
        Assert.Equal(new DateTimeOffset(2026, 10, 20, 1, 2, 3, TimeSpan.Zero), store.Profile.UpdatedAt);
        Assert.Equal("formality 80/100, verbosity 40/100. Polite. Concise.", store.Profile.PromptDescription(AppCategory.Email));
        Assert.Equal("Concise.", store.Profile.PromptDescription(AppCategory.Code));
        Assert.Null(new StyleProfile().PromptDescription(AppCategory.Code));
        Assert.Equal(1, store.PendingCount);
        Assert.Equal([new Correction("a", "b")], store.Corrections);
    }

    [Fact]
    public void AnUnreadableFileStartsEmpty()
    {
        using var folder = new DataTestFolder();
        File.WriteAllText(Path.Combine(folder.Path, PersonalizationStore.FileName), "not json");
        var store = new PersonalizationStore(folder.Path);
        Assert.Equal(0, store.PendingCount);
        Assert.Equal("", store.Profile.General);
    }

    [Fact]
    public void StyleUserListsTheProfileAndSamples()
    {
        var current = new StyleProfile
        {
            General = "Concise.",
            Categories = new Dictionary<string, CategoryProfile> { ["email"] = new(80, 40, "Polite."), ["chat"] = new(20, 10, "Short.") },
        };
        var text = Prompts.StyleUser([new StyleSample(AppCategory.Code, new string('あ', 700))], current);
        Assert.Equal(
            "Current profile:\ngeneral: Concise.\nchat: formality 20, verbosity 10, notes: Short.\nemail: formality 80, verbosity 40, notes: Polite.\n\nNew samples:\n[code] "
            + new string('あ', 600) + "\n",
            text);
        Assert.StartsWith("Current profile:\n(none)\n", Prompts.StyleUser([], new StyleProfile()));
    }

    /// 文体の分析だけをする偽の AI。Hang は取り消されるまで終わらない
    sealed class FakeStyleEngine(FakeStyleEngine.Behavior behavior) : ILLMEngine
    {
        public enum Behavior { Fail, Hang, Succeed }

        int _calls;
        readonly TaskCompletionSource _started = new(TaskCreationOptions.RunContinuationsAsynchronously);

        public string Name => "Fake";
        public bool SupportsWebSearch => false;
        public int Calls => Volatile.Read(ref _calls);
        public IReadOnlyList<StyleSample> LastSamples { get; private set; } = [];

        public Task<string> PolishAsync(PolishRequest request, CancellationToken cancellationToken = default) => Task.FromResult(request.Transcript);
        public Task<AskOutcome> AskAsync(AskRequest request, CancellationToken cancellationToken = default) => Task.FromResult<AskOutcome>(new AskOutcome.Answer(""));

        public async Task<StyleAnalysis> AnalyzeStyleAsync(IReadOnlyList<StyleSample> samples, StyleProfile current, CancellationToken cancellationToken = default)
        {
            Interlocked.Increment(ref _calls);
            LastSamples = samples;
            _started.TrySetResult();
            switch (behavior)
            {
                case Behavior.Fail:
                    throw LLMException.BadResponse();
                case Behavior.Hang:
                    await Task.Delay(TimeSpan.FromHours(1), cancellationToken);
                    return new StyleAnalysis("", []);
                default:
                    return new StyleAnalysis("Direct.", [new CategoryStyleAnalysis("chat", 100, 0, "Casual.")]);
            }
        }

        public Task WaitForCall() => _started.Task;
    }
}
