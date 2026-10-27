using System.Globalization;
using System.Text;

namespace Koebumi.Core;

/// 累計の利用統計。履歴を消しても残る。
public sealed class UsageStats
{
    public int TotalWords { get; set; }
    public double TotalSeconds { get; set; }
    public int Sessions { get; set; }
    /// yyyy-MM-dd → 単語数
    public Dictionary<string, int> DailyWords { get; set; } = [];
}

/// どのスレッドからでも呼べる。Changed は、変更したスレッドで（ロックを外してから）呼ぶので、画面の更新は呼び出し側で UI スレッドに移す
public sealed class StatsStore
{
    public const string FileName = "stats.json";
    /// 「節約できた時間」の計算に使うタイピング速度（単語/分）
    public const double TypingWPM = 40.0;

    readonly object _gate = new();
    /// null ならファイルに読み書きしない（テスト用）
    readonly string? _file;
    volatile UsageStats _stats = new();

    public event EventHandler? Changed;

    /// folder が null なら %APPDATA%\Koebumi（Storage.Root）。inMemory ならファイルに読み書きしない
    public StatsStore(string? folder = null, bool inMemory = false)
    {
        if (inMemory) return;
        folder ??= Storage.Root;
        Directory.CreateDirectory(folder);
        _file = Path.Combine(folder, FileName);
        _stats = Storage.LoadAt<UsageStats>(_file) ?? new UsageStats();
    }

    /// 呼んだ時点の統計。書き換えない（記録のたびに新しいものに替わる）
    public UsageStats Stats => _stats;

    public void Record(int words, double seconds, DateTime? date = null)
    {
        lock (_gate)
        {
            var s = _stats;
            var daily = new Dictionary<string, int>(s.DailyWords);
            var key = DayKey(date ?? DateTime.Now);
            daily[key] = daily.GetValueOrDefault(key) + words;
            _stats = new UsageStats
            {
                TotalWords = s.TotalWords + words,
                TotalSeconds = s.TotalSeconds + seconds,
                Sessions = s.Sessions + 1,
                DailyWords = daily,
            };
            if (_file is not null) Storage.SaveAt(_stats, _file);
        }
        Changed?.Invoke(this, EventArgs.Empty);
    }

    public int AverageWPM
    {
        get
        {
            var s = _stats;
            return s.TotalSeconds > 5 ? (int)(s.TotalWords / (s.TotalSeconds / 60)) : 0;
        }
    }

    /// タイピングと比べて節約できた時間（秒）
    public double TimeSaved
    {
        get
        {
            var s = _stats;
            return Math.Max(0, s.TotalWords / TypingWPM * 60 - s.TotalSeconds);
        }
    }

    /// 今日までの連続日数（Swift 版の `streak`。静的な Streak(days, today) と名前がぶつかるので CurrentStreak）
    public int CurrentStreak =>
        Streak(_stats.DailyWords.Where(p => p.Value > 0).Select(p => p.Key).ToHashSet(), DateTime.Now);

    /// 直近 n 日の単語数（古い日が先）
    public IReadOnlyList<(DateTime Date, int Words)> LastDays(int n, DateTime? now = null)
    {
        var today = ToLocal(now ?? DateTime.Now).Date;
        var daily = _stats.DailyWords;
        var result = new List<(DateTime, int)>(Math.Max(n, 0));
        for (int offset = n - 1; offset >= 0; offset--)
        {
            var d = today.AddDays(-offset);
            result.Add((d, daily.GetValueOrDefault(DayKey(d))));
        }
        return result;
    }

    /// 暦の日（この PC の時刻）を yyyy-MM-dd にする
    public static string DayKey(DateTime date) =>
        ToLocal(date).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);

    static DateTime ToLocal(DateTime date) => date.Kind == DateTimeKind.Utc ? date.ToLocalTime() : date;

    public static int Streak(IReadOnlySet<string> days, DateTime today)
    {
        var day = ToLocal(today).Date;
        // 今日まだ使っていなくても、昨日まで続いていれば連続とみなす
        if (!days.Contains(DayKey(day))) day = day.AddDays(-1);
        int count = 0;
        while (days.Contains(DayKey(day)))
        {
            count++;
            day = day.AddDays(-1);
        }
        return count;
    }

    /// 単語数を数える。日本語のように空白で区切らない言語も単語単位で数える。
    /// Mac 版は NLTokenizer で数えるが、Windows には同じ分かち書きがないので、文字の種類で区切る決まった数え方にする:
    /// 英数字は 1 続き（don't・3.5・1,000・U.S. も 1 語）、カタカナは 1 続きで 1 語、
    /// 漢字は 2 文字で 1 語、ひらがなは 3 文字で 1 語（切り上げ）。記号と空白は数えない
    public static int WordCount(string text)
    {
        var runes = text.EnumerateRunes().ToArray();
        int count = 0;
        int i = 0;
        while (i < runes.Length)
        {
            var script = ScriptOf(runes[i]);
            int start = i;
            switch (script)
            {
                case Script.Han:
                case Script.Hiragana:
                case Script.Katakana:
                    int letters = 0;
                    for (; i < runes.Length && Continues(script, runes[i]); i++)
                        if (ScriptOf(runes[i]) != Script.Mark) letters++;
                    count += script switch
                    {
                        Script.Han => (letters + 1) / 2,
                        Script.Hiragana => (letters + 2) / 3,
                        _ => 1,
                    };
                    break;
                case Script.Word:
                    for (; i < runes.Length; i++)
                    {
                        var k = ScriptOf(runes[i]);
                        if (k == Script.Word || k == Script.Mark) continue;
                        if (!IsJoiner(runes, i, start)) break;
                    }
                    for (int j = start; j < i; j++)
                    {
                        if (Rune.IsLetter(runes[j]) || Rune.IsNumber(runes[j])) { count++; break; }
                    }
                    break;
                default:
                    i++;
                    break;
            }
        }
        return count;
    }

    enum Script { None, Mark, Han, Hiragana, Katakana, Word }

    static Script ScriptOf(Rune r)
    {
        int v = r.Value;
        if (Rune.GetUnicodeCategory(r) is UnicodeCategory.NonSpacingMark or UnicodeCategory.SpacingCombiningMark or UnicodeCategory.EnclosingMark)
            return Script.Mark;
        if (v is >= 0x20000 and <= 0x323AF || v < 0x10000 && CharClasses.Of((char)v) == CharClass.Han) return Script.Han;
        if (!Rune.IsLetter(r) && !Rune.IsNumber(r) && v != '_') return Script.None;
        if (v is >= 0x3040 and <= 0x309F) return Script.Hiragana;
        if (v < 0x10000 && CharClasses.IsKatakana((char)v)) return Script.Katakana;
        return Script.Word;
    }

    /// 同じ種類の続きか。結合する記号は直前の文字に付き、長音「ー」はひらがなの中でも切れない
    static bool Continues(Script script, Rune r)
    {
        var k = ScriptOf(r);
        return k == script || k == Script.Mark || script == Script.Hiragana && r.Value == 0x30FC;
    }

    /// 英数字の続きの間にある「'」「’」「.」「,」で、前後が文字どうし（don't・U.S.）か数字どうし（3.5・1,000）なら語をつなぐ
    static bool IsJoiner(Rune[] runes, int i, int start)
    {
        if (i <= start || i + 1 >= runes.Length) return false;
        int v = runes[i].Value;
        var (prev, next) = (runes[i - 1], runes[i + 1]);
        if (ScriptOf(prev) != Script.Word || ScriptOf(next) != Script.Word) return false;
        if (v is '\'' or 0x2019 or '.') return Rune.IsLetter(prev) && Rune.IsLetter(next) || Rune.IsNumber(prev) && Rune.IsNumber(next);
        return v == ',' && Rune.IsNumber(prev) && Rune.IsNumber(next);
    }
}
