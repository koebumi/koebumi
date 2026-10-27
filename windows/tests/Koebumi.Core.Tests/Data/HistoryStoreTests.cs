using System.Text.Json;
using Koebumi.Core;

namespace Koebumi.Core.Tests;

[Collection(DataFilesCollection.Name)]
public class HistoryStoreTests
{
    static HistoryItem Item(string output, DateTimeOffset? date = null, Mode mode = Mode.Dictate, string? audioFile = null) =>
        new() { Mode = mode, Output = output, RawTranscript = output, Date = date ?? DateTimeOffset.FromUnixTimeSeconds(DateTimeOffset.UtcNow.ToUnixTimeSeconds()), AudioFile = audioFile };

    [Fact]
    public void AddsNewestFirstAndPersists()
    {
        using var folder = new DataTestFolder();
        var store = new HistoryStore(folder.Path);
        int changed = 0;
        store.Changed += (_, _) => changed++;
        var first = Item("first");
        var second = Item("second");
        store.Add(first, Retention.Forever);
        store.Add(second, Retention.Month);
        Assert.Equal(["second", "first"], store.Items.Select(i => i.Output));
        Assert.Equal(2, changed);
        Assert.Equal(["second", "first"], new HistoryStore(folder.Path).Items.Select(i => i.Output));
        Assert.Equal(second, new HistoryStore(folder.Path).Items[0]);
    }

    [Fact]
    public void NeverRetentionKeepsNothingAndRemovesTheAudio()
    {
        using var folder = new DataTestFolder();
        var store = new HistoryStore(folder.Path);
        var name = store.SaveAudio(new RecordedAudio([0.1f, 0.2f]), Guid.NewGuid());
        Assert.NotNull(name);
        var path = Path.Combine(store.AudioDir, name!);
        Assert.True(File.Exists(path));
        int changed = 0;
        store.Changed += (_, _) => changed++;
        store.Add(Item("x", audioFile: name), Retention.Never);
        Assert.Empty(store.Items);
        Assert.False(File.Exists(path));
        Assert.Equal(0, changed);
    }

    // Mac 版の retentionPrunesOldItems が確かめる保存期間（Retention.Interval）を使った、実際の削除
    [Fact]
    public void PruneRemovesExpiredItemsWithTheirAudio()
    {
        using var folder = new DataTestFolder();
        var store = new HistoryStore(folder.Path);
        var now = new DateTimeOffset(2026, 10, 27, 12, 0, 0, TimeSpan.Zero);
        var oldName = store.SaveAudio(new RecordedAudio([0.1f]), Guid.NewGuid());
        var newName = store.SaveAudio(new RecordedAudio([0.1f]), Guid.NewGuid());
        store.Add(Item("old", now.AddDays(-8), audioFile: oldName), Retention.Forever);
        store.Add(Item("recent", now.AddDays(-6), audioFile: newName), Retention.Forever);
        store.Add(Item("today", now), Retention.Forever);

        store.Prune(Retention.Forever, now);
        Assert.Equal(3, store.Items.Count);

        store.Prune(Retention.Week, now);
        Assert.Equal(["today", "recent"], store.Items.Select(i => i.Output));
        Assert.False(File.Exists(Path.Combine(store.AudioDir, oldName!)));
        Assert.True(File.Exists(Path.Combine(store.AudioDir, newName!)));
        Assert.Equal(2, new HistoryStore(folder.Path).Items.Count);

        // 「保存しない」は、いま時点より前のものをすべて消す
        store.Prune(Retention.Never, now.AddSeconds(1));
        Assert.Empty(store.Items);
        Assert.False(File.Exists(Path.Combine(store.AudioDir, newName!)));
    }

    [Fact]
    public void UpdatesDeletesAndClears()
    {
        using var folder = new DataTestFolder();
        var store = new HistoryStore(folder.Path);
        var name = store.SaveAudio(new RecordedAudio([0.1f]), Guid.NewGuid());
        var a = Item("a", audioFile: name);
        var b = Item("b");
        var c = Item("c");
        store.Add(a, Retention.Forever);
        store.Add(b, Retention.Forever);
        store.Add(c, Retention.Forever);

        store.Update(b with { Feedback = "good", Output = "B" });
        Assert.Equal("good", store.Items[1].Feedback);
        Assert.Equal(["c", "B", "a"], store.Items.Select(i => i.Output));
        store.Update(Item("not stored"));
        Assert.Equal(3, store.Items.Count);

        store.Delete(a);
        Assert.Equal(["c", "B"], store.Items.Select(i => i.Output));
        Assert.False(File.Exists(Path.Combine(store.AudioDir, name!)));

        var name2 = store.SaveAudio(new RecordedAudio([0.1f]), Guid.NewGuid());
        store.Add(Item("d", audioFile: name2), Retention.Forever);
        store.DeleteAll();
        Assert.Empty(store.Items);
        Assert.False(File.Exists(Path.Combine(store.AudioDir, name2!)));
        Assert.Empty(new HistoryStore(folder.Path).Items);
    }

    [Fact]
    public void LastOutputSkipsFailuresAndEmptyOutput()
    {
        using var folder = new DataTestFolder();
        var store = new HistoryStore(folder.Path);
        Assert.Null(store.LastOutput);
        store.Add(Item("good"), Retention.Forever);
        store.Add(Item("failed") with { Status = HistoryStatus.Failed }, Retention.Forever);
        store.Add(Item(""), Retention.Forever);
        Assert.Equal("good", store.LastOutput);
    }

    [Fact]
    public void SavesAudioUnderTheItemId()
    {
        using var folder = new DataTestFolder();
        var store = new HistoryStore(folder.Path);
        var id = Guid.NewGuid();
        var audio = new RecordedAudio(Enumerable.Range(0, 800).Select(i => MathF.Sin(i / 10f) * 0.5f).ToArray());
        var name = store.SaveAudio(audio, id);
        Assert.Equal(id.ToString("D").ToUpperInvariant() + ".wav", name);
        Assert.Equal(folder.File("Audio"), store.AudioDir);
        var item = Item("x", audioFile: name);
        var path = store.AudioPathOf(item)!;
        Assert.Equal(Path.Combine(folder.Path, "Audio", name!), path);
        Assert.Equal(800, WAV.Decode(File.ReadAllBytes(path))!.Samples.Length);
        Assert.Null(store.AudioPathOf(Item("no audio")));
    }

    [Fact]
    public void UsesTheStorageRootWhenNoFolderIsGiven()
    {
        using var folder = new DataTestFolder();
        Storage.RootOverride = folder.Path;
        try
        {
            var store = new HistoryStore();
            var name = store.SaveAudio(new RecordedAudio([0.1f]), Guid.NewGuid());
            var item = Item("x", audioFile: name);
            store.Add(item, Retention.Forever);
            Assert.True(File.Exists(folder.File("history.json")));
            Assert.Equal(folder.File(Path.Combine("Audio", name!)), item.AudioPath);
            Assert.True(File.Exists(item.AudioPath));
        }
        finally
        {
            Storage.RootOverride = null;
        }
    }

    [Fact]
    public void PersistsInTheSameJsonShapeAsTheMacApp()
    {
        using var folder = new DataTestFolder();
        var store = new HistoryStore(folder.Path);
        store.Add(new HistoryItem
        {
            Mode = Mode.Ask, Output = "answer", AppName = "Slack", AppBundleID = "slack.exe", Category = AppCategory.Chat,
            Duration = 2.5, WordCount = 1, AskAction = "answer",
            Date = new DateTimeOffset(2026, 10, 27, 1, 2, 3, 456, TimeSpan.FromHours(9)),
        }, Retention.Forever);
        using var doc = JsonDocument.Parse(File.ReadAllText(folder.File("history.json")));
        var item = doc.RootElement[0];
        Assert.Equal("ask", item.GetProperty("mode").GetString());
        Assert.Equal("success", item.GetProperty("status").GetString());
        Assert.Equal("chat", item.GetProperty("category").GetString());
        Assert.Equal("slack.exe", item.GetProperty("appBundleID").GetString());
        Assert.Equal("2026-10-26T16:02:03Z", item.GetProperty("date").GetString());
        Assert.Equal(2.5, item.GetProperty("duration").GetDouble());
        Assert.Equal("answer", item.GetProperty("askAction").GetString());
        Assert.Equal("", item.GetProperty("rawTranscript").GetString());
        Assert.False(item.TryGetProperty("plainOutput", out _));
        Assert.False(item.TryGetProperty("audioFile", out _));
        Assert.False(item.TryGetProperty("audioPath", out _));
    }

    [Fact]
    public void ReadsAFileWrittenByTheMacApp()
    {
        using var folder = new DataTestFolder();
        File.WriteAllText(folder.File("history.json"), """
            [
              {
                "appBundleID" : "com.tinyspeck.slackmacgap",
                "appName" : "Slack",
                "audioFile" : "5B1F8D2E-3C4A-4E6B-9F70-123456789ABC.wav",
                "category" : "chat",
                "date" : "2026-10-01T12:34:56Z",
                "duration" : 3.25,
                "id" : "5B1F8D2E-3C4A-4E6B-9F70-123456789ABC",
                "mode" : "translate",
                "output" : "Hello",
                "plainOutput" : "hello",
                "rawTranscript" : "こんにちは",
                "status" : "failed",
                "targetLanguage" : "en-US",
                "wordCount" : 1
              }
            ]
            """);
        var item = Assert.Single(new HistoryStore(folder.Path).Items);
        Assert.Equal(Mode.Translate, item.Mode);
        Assert.Equal(HistoryStatus.Failed, item.Status);
        Assert.Equal(AppCategory.Chat, item.Category);
        Assert.Equal(new DateTimeOffset(2026, 10, 1, 12, 34, 56, TimeSpan.Zero), item.Date);
        Assert.Equal("5B1F8D2E-3C4A-4E6B-9F70-123456789ABC.wav", item.AudioFile);
        Assert.Equal("en-US", item.TargetLanguage);
        Assert.Null(item.Language);
        Assert.Equal(3.25, item.Duration);
    }

    [Fact]
    public void FilterSelectsDictationsAndAsk()
    {
        var dictate = Item("a");
        var translate = Item("b", mode: Mode.Translate);
        var ask = Item("c", mode: Mode.Ask);
        Assert.All(new[] { dictate, translate, ask }, i => Assert.True(HistoryFilter.All.Includes(i)));
        Assert.Equal([true, true, false], new[] { dictate, translate, ask }.Select(i => HistoryFilter.Dictations.Includes(i)));
        Assert.Equal([false, false, true], new[] { dictate, translate, ask }.Select(i => HistoryFilter.Ask.Includes(i)));
        Assert.Equal("Ask anything", HistoryFilter.Ask.Title);
        Assert.NotEmpty(HistoryFilter.All.Title);
    }

    [Fact]
    public void WorksFromSeveralThreads()
    {
        using var folder = new DataTestFolder();
        var store = new HistoryStore(folder.Path);
        Parallel.For(0, 30, i => store.Add(Item("item" + i), Retention.Forever));
        Assert.Equal(30, store.Items.Count);
        Assert.Equal(30, new HistoryStore(folder.Path).Items.Count);
    }
}
