using System.Text.Json;
using Koebumi.Core;

namespace Koebumi.Core.Tests;

// Mac 版の VocabularyTests のうち、辞書（DictionaryEntry・DictionaryStore）を使う csvKeepsHeardAs と dictionaryEntryAliases。
// VocabularyTests のクラスは別のファイルにあるので、ここは別の名前にする
public class DictionaryTests
{
    [Fact]
    public void CsvKeepsHeardAs()
    {
        var csv = "term,source,heard_as\nClaude Code,manual,\"クロードコード, クロード・コード\"\nSpeak,auto,\n\"Foo, Inc.\",manual";
        var rows = DictionaryStore.ParseCsvRows(csv);
        Assert.Equal(["Claude Code", "Speak", "Foo, Inc."], rows.Select(r => r.Term));
        Assert.Equal(["クロードコード, クロード・コード", null, null], rows.Select(r => r.Heard));
    }

    [Fact]
    public void DictionaryEntryAliases()
    {
        var e = new DictionaryEntry { Term = "Claude Code", Source = DictionarySource.Manual, Replaced = "クロードコード, クロード・コード、Claude Code" };
        Assert.Equal(["クロードコード", "クロード・コード"], e.Aliases);
    }

    [Fact]
    public void AliasesFeedTheVocabularyReplacer()
    {
        var store = new DictionaryStore(inMemory: true);
        store.Add("Claude Code", DictionarySource.Manual, "クロードコード, クロード・コード");
        store.Add("Speak", DictionarySource.Manual, "スピーク");
        Assert.Equal("来週Claude Codeのデモ、Speakを起動", VocabularyReplacer.Apply("来週クロードコードのデモ、スピークを起動", store.Aliases));
    }

    [Fact]
    public void AutoAddedWordsAreOnlyHintsWhenTheHeardFormNeedsContext()
    {
        var store = new DictionaryStore(inMemory: true);
        Assert.True(store.Learn("講演", "公園"));  // 同音語（漢字）は文脈次第
        Assert.True(store.Learn("kubectl", "cube cuddle"));
        Assert.True(store.Learn("Speak", "スピーク"));  // カタカナは置き換える
        store.Add("田中", DictionarySource.Manual, "棚香");  // 手動なら漢字でも置き換える
        Assert.Equal(new Dictionary<string, string> { ["cube cuddle"] = "kubectl", ["スピーク"] = "Speak", ["棚香"] = "田中" }, store.Aliases);
        Assert.Equal(new Dictionary<string, string> { ["公園"] = "講演" }, store.AliasHints);
        Assert.True(DictionaryStore.NeedsContext("たなか"));
        Assert.True(DictionaryStore.NeedsContext("田中さん"));
        Assert.False(DictionaryStore.NeedsContext("クロード"));
        Assert.False(DictionaryStore.NeedsContext("cube cuddle"));
    }

    [Fact]
    public void FilterTitlesAndSelection()
    {
        var manual = new DictionaryEntry { Term = "a", Source = DictionarySource.Manual };
        var auto = new DictionaryEntry { Term = "b", Source = DictionarySource.Auto };
        Assert.True(DictionaryFilter.All.Includes(manual) && DictionaryFilter.All.Includes(auto));
        Assert.True(DictionaryFilter.Auto.Includes(auto) && !DictionaryFilter.Auto.Includes(manual));
        Assert.True(DictionaryFilter.Manual.Includes(manual) && !DictionaryFilter.Manual.Includes(auto));
        Assert.All(Enum.GetValues<DictionaryFilter>(), f => Assert.NotEmpty(f.Title));
    }

    [Fact]
    public void ParsesCsvFieldsWithQuotesAndOddLines()
    {
        // 引用符の中のカンマと "" / 前後の空白 / 改行の種類 / 見出しの大文字小文字
        var csv = "Words\r\n  \"Say \"\"hi\"\", ok\" , manual\r\n\r\n,empty\n単語\nTERM,source\nspaced   \u3000\u00a0";
        Assert.Equal(["Say \"hi\", ok", "spaced"], DictionaryStore.ParseCsv(csv));
        Assert.Empty(DictionaryStore.ParseCsv(""));
        Assert.Empty(DictionaryStore.ParseCsv("term\n\n"));
    }
}

public class DictionaryLearningTests
{
    [Fact]
    public void ForgetsOnlyWhatWasLearned()
    {
        var store = new DictionaryStore(inMemory: true);
        store.Add("Claude Code", DictionarySource.Manual, "クロードコード");
        Assert.False(store.Learn("Claude Code", "クロードコード"));  // 登録済み。取り消しの対象にしない

        Assert.True(store.Learn("田中", "棚香"));
        Assert.True(store.Learn("田中", "たなか"));
        store.Forget("田中", "棚香");
        Assert.Equal(["たなか"], store.Entries.First(e => e.Term == "田中").Aliases);
        store.Forget("田中", "たなか");
        Assert.DoesNotContain("田中", store.Terms);
        Assert.Equal(["Claude Code"], store.Terms);
    }

    [Fact]
    public void NewerCorrectionWins()
    {
        var store = new DictionaryStore(inMemory: true);
        store.Learn("Claude", "クロード");
        store.Learn("クロード", "Claude");
        // 置き換えが Claude ⇄ クロード で行ったり来たりしない
        Assert.Equal(new Dictionary<string, string> { ["Claude"] = "クロード" }, store.Aliases);
        Assert.DoesNotContain("Claude", store.Terms);

        // 手動で登録した向きは変えない
        store.Add("Speak", DictionarySource.Manual, "スピーク");
        Assert.False(store.Learn("スピーク", "Speak"));
        Assert.Equal("Speak", store.Aliases["スピーク"]);
    }
}

// Mac 版の DictionaryCommandTests のうち、辞書の部分（登録・ほかのプロセスが足した語を消さない）。
// CLI の書き方の解釈、Claude のスキルの書き出し、分散通知は Mac 版だけなので移していない
[Collection(DataFilesCollection.Name)]
public class DictionaryStoreTests
{
    [Fact]
    public void RegistersTermsAndNewHeardAs()
    {
        var store = new DictionaryStore(inMemory: true);
        Assert.Equal(DictionaryStore.AddResult.Added, store.Register("Koebumi", ["コエブミ"]));
        Assert.Equal(DictionaryStore.AddResult.AddedHeard(["声文", "こえぶみ"]), store.Register("Koebumi", ["コエブミ", "声文、こえぶみ"]));
        Assert.Equal(DictionaryStore.AddResult.Unchanged, store.Register("Koebumi", ["Koebumi"]));
        Assert.Equal(DictionaryStore.AddResult.Invalid, store.Register(" ", []));
        Assert.Equal(DictionaryStore.AddResult.Invalid, store.Register(new string('a', 81), []));
        Assert.Equal(DictionaryStore.AddKind.Added, store.Register(new string('a', 80), []).Kind);
        Assert.Equal(["コエブミ", "声文", "こえぶみ"], store.Entries.First(e => e.Term == "Koebumi").Aliases);
        Assert.Equal(DictionarySource.Manual, store.Entries.First(e => e.Term == "Koebumi").Source);
    }

    [Fact]
    public void TermLengthCountsCharactersNotCodeUnits()
    {
        var store = new DictionaryStore(inMemory: true);
        // 𠮷 は UTF-16 では 2 つ。80 文字までは登録できる
        Assert.Equal(DictionaryStore.AddKind.Added, store.Register(string.Concat(Enumerable.Repeat("𠮷", 80)), []).Kind);
        Assert.Equal(DictionaryStore.AddKind.Invalid, store.Register(string.Concat(Enumerable.Repeat("𠮷", 81)), []).Kind);
    }

    [Fact]
    public void KeepsWordsAnotherProcessAdded()
    {
        using var folder = new DataTestFolder();
        var app = new DictionaryStore(folder.Path);
        app.Add("Claude Code", DictionarySource.Manual, "クロードコード");

        // アプリが動いている間に、CLI が別のプロセスで語を足す
        var cli = new DictionaryStore(folder.Path);
        Assert.Equal(DictionaryStore.AddResult.Added, cli.Register("DictationController", ["ディクテーションコントローラー"]));

        // アプリが自動で語を覚えても、CLI が足した語を古い一覧で上書きしない
        Assert.True(app.Learn("田中", "棚香"));
        Assert.Equal(new HashSet<string> { "Claude Code", "DictationController", "田中" }, new DictionaryStore(folder.Path).Terms.ToHashSet());

        Assert.True(cli.Remove("田中"));
        app.ReloadIfChanged();
        Assert.Equal(new HashSet<string> { "Claude Code", "DictationController" }, app.Terms.ToHashSet());
    }

    [Fact]
    public void ReloadsAndRaisesChangedWhenAnotherInstanceWritesTheFile()
    {
        using var folder = new DataTestFolder();
        var app = new DictionaryStore(folder.Path);
        int changed = 0;
        app.Changed += (_, _) => changed++;
        app.ReloadIfChanged();
        Assert.Equal(0, changed);

        new DictionaryStore(folder.Path).Register("Koebumi", ["コエブミ"]);
        app.ReloadIfChanged();
        Assert.Equal(["Koebumi"], app.Terms);
        Assert.Equal(1, changed);
        app.ReloadIfChanged();
        Assert.Equal(1, changed);

        app.Add("田中", DictionarySource.Manual);
        Assert.Equal(2, changed);
        Assert.False(app.Add("田中", DictionarySource.Manual));  // 変わらないときは知らせない
        Assert.Equal(2, changed);
    }

    [Fact]
    public void PersistsInTheSameJsonShapeAsTheMacApp()
    {
        using var folder = new DataTestFolder();
        var store = new DictionaryStore(folder.Path);
        store.Learn("田中", "棚香");
        store.Add("Koebumi", DictionarySource.Manual);
        var json = File.ReadAllText(folder.File("dictionary.json"));
        using var doc = JsonDocument.Parse(json);
        var items = doc.RootElement.EnumerateArray().ToList();
        Assert.Equal(2, items.Count);
        Assert.Equal("Koebumi", items[0].GetProperty("term").GetString());
        Assert.Equal("manual", items[0].GetProperty("source").GetString());
        Assert.False(items[0].TryGetProperty("replaced", out _));
        Assert.False(items[0].TryGetProperty("aliases", out _));
        Assert.Equal("auto", items[1].GetProperty("source").GetString());
        Assert.Equal("棚香", items[1].GetProperty("replaced").GetString());
        Assert.Matches(@"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$", items[1].GetProperty("createdAt").GetString());
        Assert.True(Guid.TryParse(items[1].GetProperty("id").GetString(), out _));

        var again = new DictionaryStore(folder.Path);
        Assert.Equal(["Koebumi", "田中"], again.Terms);
        Assert.Equal(store.Entries[1].Id, again.Entries[1].Id);
        Assert.Equal(DictionarySource.Auto, again.Entries[1].Source);
    }

    [Fact]
    public void ReadsAFileWrittenByTheMacApp()
    {
        using var folder = new DataTestFolder();
        File.WriteAllText(folder.File("dictionary.json"), """
            [
              {
                "createdAt" : "2026-10-01T12:34:56Z",
                "id" : "5B1F8D2E-3C4A-4E6B-9F70-123456789ABC",
                "replaced" : "クロードコード",
                "source" : "manual",
                "term" : "Claude Code"
              }
            ]
            """);
        var store = new DictionaryStore(folder.Path);
        var entry = Assert.Single(store.Entries);
        Assert.Equal("Claude Code", entry.Term);
        Assert.Equal(new Guid("5B1F8D2E-3C4A-4E6B-9F70-123456789ABC"), entry.Id);
        Assert.Equal(new DateTimeOffset(2026, 10, 1, 12, 34, 56, TimeSpan.Zero), entry.CreatedAt);
        Assert.Equal(["クロードコード"], entry.Aliases);
    }

    [Fact]
    public void UpdatesAndDeletesEntries()
    {
        var store = new DictionaryStore(inMemory: true);
        store.Add("Koebumi", DictionarySource.Manual, "コエブミ");
        var entry = store.Entries[0];
        store.Update(entry, "  声文 ");
        Assert.Equal("声文", store.Entries[0].Term);
        Assert.Equal("コエブミ", store.Entries[0].Replaced);  // replaced を渡さなければそのまま
        store.Update(store.Entries[0], "声文", "  こえぶみ ");
        Assert.Equal("こえぶみ", store.Entries[0].Replaced);
        store.Update(store.Entries[0], " ");  // 空の語には変えない
        Assert.Equal("声文", store.Entries[0].Term);
        store.Update(store.Entries[0], "声文", "");
        Assert.Null(store.Entries[0].Replaced);
        store.Delete(store.Entries[0]);
        Assert.Empty(store.Entries);
        Assert.False(store.Remove("声文"));
    }

    [Fact]
    public void ImportsAndExportsCsv()
    {
        var store = new DictionaryStore(inMemory: true);
        var imported = store.ImportCsv("term,source,heard_as\nClaude Code,manual,\"クロードコード, クロード・コード\"\nSpeak,auto,\n\"Foo, Inc.\",manual\nSpeak\n");
        Assert.Equal(3, imported);  // 2 回目の Speak は登録済み
        Assert.Equal(["Foo, Inc.", "Speak", "Claude Code"], store.Terms);
        Assert.All(store.Entries, e => Assert.Equal(DictionarySource.Manual, e.Source));
        Assert.Equal(
            "term,source,heard_as\n\"Foo, Inc.\",manual,\nSpeak,manual,\nClaude Code,manual,\"クロードコード, クロード・コード\"\n",
            store.ExportCsv());
        Assert.Equal("term,source,heard_as\n\n", new DictionaryStore(inMemory: true).ExportCsv());

        var other = new DictionaryStore(inMemory: true);
        Assert.Equal(3, other.ImportCsv(store.ExportCsv()));
        Assert.Equal(store.Terms.Order(), other.Terms.Order());
        Assert.Equal(store.Aliases, other.Aliases);
    }

    [Fact]
    public void WorksFromSeveralThreads()
    {
        using var folder = new DataTestFolder();
        var store = new DictionaryStore(folder.Path);
        int changed = 0;
        store.Changed += (_, _) => Interlocked.Increment(ref changed);
        Parallel.For(0, 40, i => store.Add("word" + i, DictionarySource.Manual));
        Assert.Equal(40, store.Entries.Count);
        Assert.Equal(40, changed);
        Assert.Equal(40, new DictionaryStore(folder.Path).Entries.Count);
    }
}
