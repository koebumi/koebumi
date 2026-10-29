using System.Text.Json.Serialization;

namespace Koebumi.Core;

public enum HistoryStatus { Success, Failed }

public sealed record HistoryItem
{
    public Guid Id { get; init; } = Guid.NewGuid();
    [JsonConverter(typeof(Iso8601DateConverter))]
    public DateTimeOffset Date { get; init; } = DateTimeOffset.UtcNow;
    public Mode Mode { get; init; }
    public HistoryStatus Status { get; init; } = HistoryStatus.Success;
    public string RawTranscript { get; init; } = "";
    public string Output { get; init; } = "";
    /// AI を通さずに整えた文。AI の整形が output と違ったときだけ残す（履歴で AI が変えたところを見せる）
    public string? PlainOutput { get; init; }
    public string? ErrorMessage { get; init; }
    public string AppName { get; init; } = "";
    /// 入力先アプリの識別子。Mac 版ではバンドル ID、Windows 版では exe 名（小文字。AppContextInfo.ExeName）
    public string? AppBundleID { get; init; }
    public AppCategory Category { get; init; } = AppCategory.Other;
    /// 録音の長さ（秒）
    public double Duration { get; init; }
    public int WordCount { get; init; }
    public string? Language { get; init; }
    public string? TargetLanguage { get; init; }
    public string? SelectedText { get; init; }
    /// answer / replace / insert / open_url
    public string? AskAction { get; init; }
    public string? AudioFile { get; init; }
    public string? Feedback { get; init; }

    /// 音声ファイルの場所（標準の置き場所 Storage.AudioDir の中）。別のフォルダで作った HistoryStore の音声は HistoryStore.AudioPathOf で調べる
    [JsonIgnore]
    public string? AudioPath => AudioFile is null ? null : Path.Combine(Storage.AudioDir, AudioFile);
}

public enum HistoryFilter { All, Dictations, Ask }

public static class HistoryFilterExtensions
{
    extension(HistoryFilter filter)
    {
        public string Title => filter switch
        {
            HistoryFilter.All => T("すべて", "All"),
            HistoryFilter.Dictations => T("ディクテーション", "Dictations"),
            _ => "Ask anything",
        };

        public bool Includes(HistoryItem item) => filter switch
        {
            HistoryFilter.All => true,
            HistoryFilter.Dictations => item.Mode != Mode.Ask,
            _ => item.Mode == Mode.Ask,
        };
    }
}

/// 履歴はこの PC の中だけに保存する。保存期間を過ぎたものは音声ごと削除する。
/// どのスレッドからでも呼べる。Changed は、変更したスレッドで（ロックを外してから）呼ぶので、画面の更新は呼び出し側で UI スレッドに移す
public sealed class HistoryStore
{
    public const string FileName = "history.json";

    readonly object _gate = new();
    readonly string? _folder;
    readonly string _file;
    volatile IReadOnlyList<HistoryItem> _items = [];
    bool _dirty;

    public event EventHandler? Changed;

    /// folder が null なら %APPDATA%\Koebumi（Storage.Root）。音声はその中の Audio フォルダに置く
    public HistoryStore(string? folder = null)
    {
        _folder = folder;
        Directory.CreateDirectory(folder ?? Storage.Root);
        _file = Path.Combine(folder ?? Storage.Root, FileName);
        var loaded = Storage.LoadAt<List<HistoryItem>>(_file);
        if (loaded is not null) _items = loaded.AsReadOnly();
    }

    /// 新しい順の一覧。呼んだ時点の写しなので、あとから変わらない
    public IReadOnlyList<HistoryItem> Items => _items;

    /// 音声ファイルを置くフォルダ
    public string AudioDir
    {
        get
        {
            if (_folder is null) return Storage.AudioDir;
            var dir = Path.Combine(_folder, "Audio");
            Directory.CreateDirectory(dir);
            return dir;
        }
    }

    public string? AudioPathOf(HistoryItem item) => item.AudioFile is null ? null : Path.Combine(AudioDir, item.AudioFile);

    public void Add(HistoryItem item, Retention retention)
    {
        if (retention == Retention.Never)
        {
            DeleteAudio(item);
            return;
        }
        Mutate(() => Commit([item, .. _items]));
    }

    public void Update(HistoryItem item) => Mutate(() =>
    {
        var list = _items.ToList();
        int i = list.FindIndex(x => x.Id == item.Id);
        if (i < 0) return;
        list[i] = item;
        Commit(list);
    });

    public void Delete(HistoryItem item) => Mutate(() =>
    {
        DeleteAudio(item);
        Commit([.. _items.Where(x => x.Id != item.Id)]);
    });

    public void DeleteAll() => Mutate(() =>
    {
        foreach (var item in _items) DeleteAudio(item);
        Commit([]);
    });

    public void Prune(Retention retention, DateTimeOffset? now = null)
    {
        if (retention.Interval is not { } interval) return;
        var cutoff = (now ?? DateTimeOffset.UtcNow) - interval;
        Mutate(() =>
        {
            var expired = _items.Where(x => x.Date < cutoff).ToList();
            if (expired.Count == 0) return;
            foreach (var item in expired) DeleteAudio(item);
            Commit([.. _items.Where(x => x.Date >= cutoff)]);
        });
    }

    public string? LastOutput => _items.FirstOrDefault(x => x.Status == HistoryStatus.Success && x.Output.Length > 0)?.Output;

    /// 録音を WAV で保存して、ファイル名（HistoryItem.AudioFile に入れる）を返す。書けなければ null
    public string? SaveAudio(RecordedAudio audio, Guid id)
    {
        var name = id.ToString("D").ToUpperInvariant() + ".wav";
        try
        {
            var path = Path.Combine(AudioDir, name);
            var tmp = path + ".tmp";
            File.WriteAllBytes(tmp, WAV.Encode(audio));
            File.Move(tmp, path, overwrite: true);
            return name;
        }
        catch
        {
            return null;
        }
    }

    void DeleteAudio(HistoryItem item)
    {
        if (AudioPathOf(item) is not { } path) return;
        try { File.Delete(path); } catch { }
    }

    // ここから下は、ロックの中で呼ぶ

    void Commit(List<HistoryItem> list)
    {
        _items = list.AsReadOnly();
        _dirty = true;
        Storage.SaveAt(_items, _file);
    }

    void Mutate(Action body)
    {
        bool notify;
        lock (_gate)
        {
            body();
            notify = _dirty;
            _dirty = false;
        }
        if (notify) Changed?.Invoke(this, EventArgs.Empty);
    }
}
