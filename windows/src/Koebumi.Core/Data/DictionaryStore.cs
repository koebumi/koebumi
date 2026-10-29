using System.Globalization;
using System.Text;
using System.Text.Json.Serialization;

namespace Koebumi.Core;

public enum DictionarySource { Manual, Auto }

public sealed record DictionaryEntry
{
    public Guid Id { get; init; } = Guid.NewGuid();
    public string Term { get; init; } = "";
    public DictionarySource Source { get; init; } = DictionarySource.Manual;
    [JsonConverter(typeof(Iso8601DateConverter))]
    public DateTimeOffset CreatedAt { get; init; } = DateTimeOffset.UtcNow;
    /// 音声認識での聞き取られ方（自動追加では直される前の語）。カンマか読点で区切って複数書ける。
    public string? Replaced { get; init; }

    [JsonIgnore]
    public IReadOnlyList<string> Aliases =>
        [.. SplitList(Replaced).Select(TrimSpaces).Where(a => a.Length > 0 && a != Term)];

    static readonly char[] Separators = [',', '、', '，'];

    /// カンマか読点で区切った一覧を分ける（空の要素は捨てる）
    internal static string[] SplitList(string? text) => (text ?? "").Split(Separators, StringSplitOptions.RemoveEmptyEntries);

    /// 前後の空白を取る（Swift の `.whitespaces`。改行は取らない）
    internal static string TrimSpaces(string s)
    {
        int start = 0, end = s.Length;
        while (start < end && IsSpace(s[start])) start++;
        while (end > start && IsSpace(s[end - 1])) end--;
        return s[start..end];
    }

    static bool IsSpace(char c) => c == '\t' || char.GetUnicodeCategory(c) == UnicodeCategory.SpaceSeparator;
}

public enum DictionaryFilter { All, Auto, Manual }

public static class DictionaryFilterExtensions
{
    extension(DictionaryFilter filter)
    {
        public string Title => filter switch
        {
            DictionaryFilter.All => T("すべて", "All"),
            DictionaryFilter.Auto => T("自動追加", "Auto-added"),
            _ => T("手動追加", "Manually added"),
        };

        public bool Includes(DictionaryEntry entry) => filter switch
        {
            DictionaryFilter.All => true,
            DictionaryFilter.Auto => entry.Source == DictionarySource.Auto,
            _ => entry.Source == DictionarySource.Manual,
        };
    }
}

/// 個人辞書。音声認識のヒント（prompt）と整形時の綴り指定に使う。
/// ほかのプロセス（エージェントが動かす CLI など）も同じファイルに書くので、書き換える前に更新を調べて読み直す（ReloadIfChanged）。
/// どのスレッドからでも呼べる。Changed は、変更したスレッドで（ロックを外してから）呼ぶので、画面の更新は呼び出し側で UI スレッドに移す
public sealed class DictionaryStore
{
    public const string FileName = "dictionary.json";
    const int MaxTermLength = 80;

    public enum AddKind { Added, AddedHeard, Unchanged, Invalid }

    public sealed class AddResult : IEquatable<AddResult>
    {
        public AddKind Kind { get; }
        /// AddedHeard のとき、新しく足した聞き取られ方
        public IReadOnlyList<string> Heard { get; }

        AddResult(AddKind kind, IReadOnlyList<string> heard) { Kind = kind; Heard = heard; }

        public static readonly AddResult Added = new(AddKind.Added, []);
        /// 既にある語に、新しい聞き取られ方だけを足した
        public static AddResult AddedHeard(IReadOnlyList<string> heard) => new(AddKind.AddedHeard, heard);
        public static readonly AddResult Unchanged = new(AddKind.Unchanged, []);
        /// 空か、長すぎる（80 文字まで）
        public static readonly AddResult Invalid = new(AddKind.Invalid, []);

        public bool Equals(AddResult? other) => other is not null && Kind == other.Kind && Heard.SequenceEqual(other.Heard);
        public override bool Equals(object? obj) => Equals(obj as AddResult);
        public override int GetHashCode() => HashCode.Combine(Kind, Heard.Count);
        public override string ToString() => Kind == AddKind.AddedHeard ? $"AddedHeard([{string.Join(", ", Heard)}])" : Kind.ToString();
    }

    /// CSV の 1 行。Heard は聞き取られ方（3 列目）
    public readonly record struct CsvRow(string Term, string? Heard);

    /// 最後に読んだか書いたときのファイルの状態。違っていれば、ほかのプロセスが書き換えている
    readonly record struct FileStamp(DateTime Modified, long Length);

    readonly object _gate = new();
    /// null ならファイルに読み書きしない（テスト用）
    readonly string? _file;
    volatile IReadOnlyList<DictionaryEntry> _entries = [];
    FileStamp? _stamp;
    bool _dirty;

    /// 辞書が変わった（自分の操作と、ほかのプロセスの書き換えを読み直したとき）
    public event EventHandler? Changed;

    /// folder が null なら %APPDATA%\Koebumi（Storage.Root）。inMemory ならファイルに読み書きしない
    public DictionaryStore(string? folder = null, bool inMemory = false)
    {
        if (!inMemory)
        {
            folder ??= Storage.Root;
            Directory.CreateDirectory(folder);
            _file = Path.Combine(folder, FileName);
        }
        LoadCore();
        _dirty = false;
    }

    /// 新しい順の一覧。呼んだ時点の写しなので、あとから変わらない
    public IReadOnlyList<DictionaryEntry> Entries => _entries;

    public IReadOnlyList<string> Terms => [.. _entries.Select(e => e.Term)];

    /// 聞き取られ方 → 正しい表記（認識結果の置き換えに使う）。
    /// 自動追加の語は、漢字・ひらがなの聞き取られ方では置き換えない（「公園 → 講演」のような同音語の直しは文脈次第のため）。
    public IReadOnlyDictionary<string, string> Aliases
    {
        get
        {
            var entries = _entries;
            return AllAliases(entries)
                .Where(p => entries.Any(e => e.Source == DictionarySource.Manual && e.Aliases.Contains(p.Key)) || !NeedsContext(p.Key))
                .ToDictionary(p => p.Key, p => p.Value);
        }
    }

    /// 置き換えずに、AI に文脈を見て直してもらう聞き取られ方
    public IReadOnlyDictionary<string, string> AliasHints
    {
        get
        {
            var entries = _entries;
            var replaced = Aliases;
            return AllAliases(entries).Where(p => !replaced.ContainsKey(p.Key)).ToDictionary(p => p.Key, p => p.Value);
        }
    }

    static Dictionary<string, string> AllAliases(IReadOnlyList<DictionaryEntry> entries)
    {
        var map = new Dictionary<string, string>();
        for (int i = entries.Count - 1; i >= 0; i--)
            foreach (var a in entries[i].Aliases) map[a] = entries[i].Term;
        return map;
    }

    /// 漢字・ひらがなを含む（同音語がありうる）
    public static bool NeedsContext(string alias) =>
        alias.Any(c => CharClasses.Of(c) is CharClass.Han or CharClass.Kana && !CharClasses.IsKatakana(c));

    /// ほかのプロセスがファイルを書き換えていたら読み直す。書き換える前に呼び、古い一覧で上書きしないようにする
    public void ReloadIfChanged() => Mutate(ReloadIfChangedCore);

    /// 新しい語を登録したら true
    public bool Add(string term, DictionarySource source, string? replaced = null) =>
        Locked(() => AddCore(term, source, replaced));

    /// 語を登録する。既にある語なら、まだない聞き取られ方だけを足す。聞き取られ方はカンマか読点で区切ってもよい
    public AddResult Register(string term, IEnumerable<string> heard, DictionarySource source = DictionarySource.Manual) =>
        Locked(() => RegisterCore(term, heard, source));

    /// 直した語を自動で追加する。辞書が変わったら true（取り消せるのは、ここで変えたものだけ）。
    /// 逆向きの直し（前に覚えた A → B を、B → A と直した）は新しい方を残す。置き換えが行ったり来たりしないように。
    public bool Learn(string term, string replaced) => Locked(() =>
    {
        ReloadIfChangedCore();
        if (_entries.Any(e => e.Source == DictionarySource.Manual && e.Term == replaced && e.Aliases.Contains(term))) return false;
        var before = _entries;
        if (RemoveAliasCore(term, replaced)) SaveCore();
        AddCore(term, DictionarySource.Auto, replaced);
        return !before.SequenceEqual(_entries);
    });

    /// 自動で追加した直しを取り消す（同じ入力の中で、その語をさらに直したか、元に戻したとき）
    public void Forget(string term, string replaced) => Mutate(() =>
    {
        ReloadIfChangedCore();
        if (RemoveAliasCore(replaced, term)) SaveCore();
    });

    public void Update(DictionaryEntry entry, string term, string? replaced = null) => Mutate(() =>
    {
        ReloadIfChangedCore();
        var list = _entries.ToList();
        int i = list.FindIndex(e => e.Id == entry.Id);
        if (i < 0) return;
        var trimmed = term.Trim();
        if (trimmed.Length == 0) return;
        var updated = list[i] with { Term = trimmed };
        if (replaced is not null)
        {
            var r = replaced.Trim();
            updated = updated with { Replaced = r.Length == 0 ? null : r };
        }
        list[i] = updated;
        Commit(list);
    });

    public void Delete(DictionaryEntry entry) => Mutate(() =>
    {
        ReloadIfChangedCore();
        Commit([.. _entries.Where(e => e.Id != entry.Id)]);
    });

    /// 語を名前で消す（CLI から）。見つからなければ false
    public bool Remove(string term) => Locked(() =>
    {
        ReloadIfChangedCore();
        var trimmed = term.Trim();
        if (!_entries.Any(e => e.Term == trimmed)) return false;
        Commit([.. _entries.Where(e => e.Term != trimmed)]);
        return true;
    });

    /// CSV を取り込む。1 列目を単語、3 列目を聞き取られ方として扱い、見出し行（"word" / "term" / "単語"）は飛ばす。
    /// 新しく登録した語の数を返す
    public int ImportCsv(string text) => Locked(() =>
    {
        int count = 0;
        foreach (var row in ParseCsvRows(text))
            if (AddCore(row.Term, DictionarySource.Manual, row.Heard)) count++;
        return count;
    });

    public string ExportCsv() =>
        "term,source,heard_as\n"
        + string.Join("\n", _entries.Select(e => $"{CsvEscape(e.Term)},{Storage.Raw(e.Source)},{CsvEscape(e.Replaced ?? "")}"))
        + "\n";

    public static IReadOnlyList<string> ParseCsv(string text) => [.. ParseCsvRows(text).Select(r => r.Term)];

    public static IReadOnlyList<CsvRow> ParseCsvRows(string text)
    {
        var result = new List<CsvRow>();
        foreach (var line in SplitLines(text))
        {
            var fields = CsvFields(DictionaryEntry.TrimSpaces(line)).Select(DictionaryEntry.TrimSpaces).ToList();
            if (fields.Count == 0 || fields[0].Length == 0) continue;
            var first = fields[0];
            if (Headers.Contains(first.ToLowerInvariant())) continue;
            var heard = fields.Count >= 3 && fields[2].Length > 0 ? fields[2] : null;
            result.Add(new CsvRow(first, heard));
        }
        return result;
    }

    static readonly HashSet<string> Headers = ["word", "term", "単語", "words", "terms"];

    /// 改行の文字（CharacterSet.newlines と同じ）で行に分ける。連続した改行は空の行になる
    static List<string> SplitLines(string text)
    {
        var lines = new List<string>();
        int start = 0;
        for (int i = 0; i < text.Length; i++)
        {
            if (!CharClasses.IsNewline(text[i])) continue;
            lines.Add(text[start..i]);
            start = i + 1;
        }
        lines.Add(text[start..]);
        return lines;
    }

    /// 1 行をカンマで区切る（"..." で囲んだ値の中のカンマと "" に対応）
    static List<string> CsvFields(string line)
    {
        var fields = new List<string>();
        var value = new StringBuilder();
        bool quoted = false;
        for (int i = 0; i < line.Length; i++)
        {
            char c = line[i];
            if (quoted)
            {
                if (c != '"') value.Append(c);
                else if (i + 1 < line.Length && line[i + 1] == '"') { value.Append('"'); i++; }
                else quoted = false;
            }
            else if (c == '"' && value.Length == 0) quoted = true;
            else if (c == ',')
            {
                fields.Add(value.ToString());
                value.Clear();
            }
            else value.Append(c);
        }
        if (line.Length > 0) fields.Add(value.ToString());
        return fields;
    }

    static string CsvEscape(string s) =>
        s.Contains(',') || s.Contains('"') ? "\"" + s.Replace("\"", "\"\"") + "\"" : s;

    // ここから下は、ロックの中で呼ぶ

    bool AddCore(string term, DictionarySource source, string? replaced) =>
        RegisterCore(term, replaced is null ? [] : [replaced], source).Kind == AddKind.Added;

    AddResult RegisterCore(string term, IEnumerable<string> heard, DictionarySource source)
    {
        ReloadIfChangedCore();
        var trimmed = term.Trim();
        if (trimmed.Length == 0 || new StringInfo(trimmed).LengthInTextElements > MaxTermLength) return AddResult.Invalid;
        var newHeard = new List<string>();
        foreach (var raw in heard.SelectMany(DictionaryEntry.SplitList))
        {
            var h = DictionaryEntry.TrimSpaces(raw);
            if (h.Length > 0 && h != trimmed && !newHeard.Contains(h)) newHeard.Add(h);
        }
        var list = _entries.ToList();
        int i = list.FindIndex(e => e.Term == trimmed);
        if (i >= 0)
        {
            var existing = list[i].Aliases;
            newHeard.RemoveAll(h => existing.Contains(h));
            if (newHeard.Count == 0) return AddResult.Unchanged;
            list[i] = list[i] with { Replaced = string.Join(", ", existing.Concat(newHeard)) };
            Commit(list);
            return AddResult.AddedHeard(newHeard);
        }
        list.Insert(0, new DictionaryEntry
        {
            Term = trimmed,
            Source = source,
            Replaced = newHeard.Count == 0 ? null : string.Join(", ", newHeard),
        });
        Commit(list);
        return AddResult.Added;
    }

    /// 自動で追加した語から聞き取られ方を外す。ほかに聞き取られ方がなければ語ごと消す
    bool RemoveAliasCore(string alias, string term)
    {
        var list = _entries.ToList();
        int i = list.FindIndex(e => e.Term == term && e.Source == DictionarySource.Auto);
        if (i < 0 || !list[i].Aliases.Contains(alias)) return false;
        var rest = list[i].Aliases.Where(a => a != alias).ToList();
        if (rest.Count == 0) list.RemoveAt(i);
        else list[i] = list[i] with { Replaced = string.Join(", ", rest) };
        Publish(list);
        return true;
    }

    void ReloadIfChangedCore()
    {
        if (_file is null || StampOf(_file) == _stamp) return;
        LoadCore();
    }

    void LoadCore()
    {
        if (_file is null) return;
        Publish(Storage.LoadAt<List<DictionaryEntry>>(_file) ?? []);
        _stamp = StampOf(_file);
    }

    void Commit(List<DictionaryEntry> list)
    {
        Publish(list);
        SaveCore();
    }

    void Publish(List<DictionaryEntry> list)
    {
        _entries = list.AsReadOnly();
        _dirty = true;
    }

    void SaveCore()
    {
        if (_file is null) return;
        Storage.SaveAt(_entries, _file);
        _stamp = StampOf(_file);
    }

    /// 更新日時とサイズ（Windows のファイルの更新日時は粗く、続けて書くと同じ値になることがあるため、サイズも見る）
    static FileStamp? StampOf(string path)
    {
        var info = new FileInfo(path);
        return info.Exists ? new FileStamp(info.LastWriteTimeUtc, info.Length) : null;
    }

    T Locked<T>(Func<T> body)
    {
        T result;
        bool notify;
        lock (_gate)
        {
            result = body();
            notify = _dirty;
            _dirty = false;
        }
        if (notify) Changed?.Invoke(this, EventArgs.Empty);
        return result;
    }

    void Mutate(Action body) => Locked(() =>
    {
        body();
        return 0;
    });
}
