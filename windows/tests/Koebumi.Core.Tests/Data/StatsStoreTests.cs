using System.Text.Json;
using Koebumi.Core;

namespace Koebumi.Core.Tests;

// 連続日数（streakCountsConsecutiveDays）と単語数（wordCountHandlesJapanese）は、Mac 版と同じ分け方で ContextTests・TextTests にある
[Collection(DataFilesCollection.Name)]
public class StatsStoreTests
{
    [Fact]
    public void RecordsWordsSecondsAndDays()
    {
        var store = new StatsStore(inMemory: true);
        int changed = 0;
        store.Changed += (_, _) => changed++;
        var day = new DateTime(2026, 10, 27, 9, 0, 0, DateTimeKind.Local);
        store.Record(30, 12, day);
        store.Record(20, 8, day.AddHours(5));
        store.Record(10, 5, day.AddDays(-1));
        Assert.Equal(60, store.Stats.TotalWords);
        Assert.Equal(25, store.Stats.TotalSeconds);
        Assert.Equal(3, store.Stats.Sessions);
        Assert.Equal(new Dictionary<string, int> { ["2026-10-27"] = 50, ["2026-10-26"] = 10 }, store.Stats.DailyWords);
        Assert.Equal(3, changed);
    }

    [Fact]
    public void ComputesAverageWpmAndTimeSaved()
    {
        var store = new StatsStore(inMemory: true);
        Assert.Equal(0, store.AverageWPM);
        Assert.Equal(0, store.TimeSaved);
        store.Record(10, 4);  // 5 秒以下は平均を出さない
        Assert.Equal(0, store.AverageWPM);
        store.Record(110, 56);  // 120 語 / 60 秒
        Assert.Equal(120, store.AverageWPM);
        Assert.Equal(180 - 60, store.TimeSaved);  // 120 語を 40 語/分で打つと 180 秒
        store.Record(0, 600);
        Assert.Equal(0, store.TimeSaved);  // 負にはならない
    }

    [Fact]
    public void LastDaysListsTheOldestFirstAndFillsMissingDays()
    {
        var store = new StatsStore(inMemory: true);
        var now = new DateTime(2026, 3, 1, 23, 30, 0, DateTimeKind.Local);
        store.Record(5, 3, now);
        store.Record(7, 3, now.AddDays(-2));  // うるう年ではない年の 2 月 27 日
        var days = store.LastDays(4, now);
        Assert.Equal([new DateTime(2026, 2, 26), new DateTime(2026, 2, 27), new DateTime(2026, 2, 28), new DateTime(2026, 3, 1)], days.Select(d => d.Date));
        Assert.Equal([0, 7, 0, 5], days.Select(d => d.Words));
        Assert.Empty(store.LastDays(0, now));
    }

    [Fact]
    public void CurrentStreakCountsUpToToday()
    {
        var store = new StatsStore(inMemory: true);
        Assert.Equal(0, store.CurrentStreak);
        store.Record(5, 3, DateTime.Now);
        store.Record(5, 3, DateTime.Now.AddDays(-1));
        store.Record(0, 3, DateTime.Now.AddDays(-2));  // 単語が 0 の日は続いたことにしない
        store.Record(5, 3, DateTime.Now.AddDays(-3));
        Assert.Equal(2, store.CurrentStreak);
    }

    [Fact]
    public void DayKeyIsTheLocalCalendarDay()
    {
        Assert.Equal("2026-01-05", StatsStore.DayKey(new DateTime(2026, 1, 5, 23, 59, 59, DateTimeKind.Local)));
        Assert.Equal("2026-01-05", StatsStore.DayKey(new DateTime(2026, 1, 5, 0, 0, 0, DateTimeKind.Unspecified)));
        var utc = new DateTime(2026, 1, 5, 20, 0, 0, DateTimeKind.Utc);
        Assert.Equal(utc.ToLocalTime().ToString("yyyy-MM-dd"), StatsStore.DayKey(utc));
    }

    [Fact]
    public void PersistsInTheSameJsonShapeAsTheMacApp()
    {
        using var folder = new DataTestFolder();
        var store = new StatsStore(folder.Path);
        store.Record(30, 12.5, new DateTime(2026, 10, 27, 9, 0, 0, DateTimeKind.Local));
        using var doc = JsonDocument.Parse(File.ReadAllText(folder.File("stats.json")));
        var root = doc.RootElement;
        Assert.Equal(30, root.GetProperty("totalWords").GetInt32());
        Assert.Equal(12.5, root.GetProperty("totalSeconds").GetDouble());
        Assert.Equal(1, root.GetProperty("sessions").GetInt32());
        Assert.Equal(30, root.GetProperty("dailyWords").GetProperty("2026-10-27").GetInt32());

        var again = new StatsStore(folder.Path);
        Assert.Equal(30, again.Stats.TotalWords);
        Assert.Equal(30, again.Stats.DailyWords["2026-10-27"]);
    }

    [Fact]
    public void WorksFromSeveralThreads()
    {
        using var folder = new DataTestFolder();
        var store = new StatsStore(folder.Path);
        Parallel.For(0, 50, _ => store.Record(2, 1));
        Assert.Equal(100, store.Stats.TotalWords);
        Assert.Equal(50, store.Stats.Sessions);
        Assert.Equal(100, new StatsStore(folder.Path).Stats.TotalWords);
    }
}
