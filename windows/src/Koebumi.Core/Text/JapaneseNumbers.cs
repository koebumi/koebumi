using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace Koebumi.Core;

/// 音声認識が漢数字で書いた数を算用数字にする（三時 → 3時、三千万 → 3000万、一日目 → 1日目、一点五倍 → 1.5倍）。
/// この Mac のモデル（Qwen3-ASR など）は漢数字で、Apple の音声認識は算用数字で書くので、どちらでも同じ表記にする。
/// 言い直し（「3時、いや4時」）や時刻の助詞の確認も、算用数字を前提にしている。
/// 「一緒」「一時的」「十分です」「三日月」「二三日」のような語は変えないよう、単位が続く数と、万・億を含む数だけを直す。
public static class JapaneseNumbers
{
    static readonly Dictionary<char, int> Digits = new()
    {
        ['〇'] = 0, ['一'] = 1, ['二'] = 2, ['三'] = 3, ['四'] = 4, ['五'] = 5, ['六'] = 6, ['七'] = 7, ['八'] = 8, ['九'] = 9,
    };
    static readonly Dictionary<char, int> SmallUnits = new() { ['十'] = 10, ['百'] = 100, ['千'] = 1000 };
    static readonly char[] LargeUnits = ['兆', '億', '万'];

    static bool IsNumeral(char c) => Digits.ContainsKey(c) || SmallUnits.ContainsKey(c) || LargeUnits.Contains(c);

    /// 数の後ろに続く単位（長いものから並べる）
    const string Units = "時間|時半|時|分|秒|日間|日|週間|週|[かヶカヵケ]月間?|月|年間|年生|年|歳|才|人|名|個|件|回|つ|枚|本|台|冊|匹|頭|羽|社|店|種類|階|番目|番線|番地|番手|番|号|位|点|度|倍|割|円|ドル|ユーロ|泊|連(?:休|勝|敗|覇|泊|続)|章|話|巻|行|列|組|着|周年|周|代|世紀|[かヶカ]国|[かヶカ]所|箇所|キロ|メートル|センチ|ミリ|グラム|トン|リットル|パーセント|ページ|ポイント|ギガ|メガ|テラ|バイト";
    static readonly Regex Unit = new("^(?:" + Units + ")");
    /// 数と単位と句読点だけの文（三千万。三時。十二月二十日）
    static readonly Regex NumbersOnly = new(@"\A(?:[〇一二三四五六七八九十百千万億兆]|" + Units + @"|[\s、。，．！？!?,.])+\z");

    /// 単位の後ろに続いてもよい漢字（3日目・3時間後・3人分・500円玉）。ほかの漢字が続くなら語の一部（三日月・六本木・一本化）
    const string AfterUnit = "目間半前後以程弱強超余頃過分当連毎玉台末上下先内近未";

    /// 前にあると語の一部になる漢字（統一・唯一・同一人物・数十人・何百回）
    const string WordBefore = "統唯同単均画逐随択数何幾";

    /// 単位が続いても変えない言い回し
    static readonly Regex Idioms = new(
        "二度と|一巻の終わり|ご一行|人一倍|一点一点|一つ一つ|一つひとつ|一人一人|一人ひとり|一人(?:で|っ子|ぼっち|きり)|十人十色|百人一首|三位一体|二人三脚|五分五分|九分九厘|八百万の神|四十九日|千歳|千代");

    static readonly string[] AfterTenMinutes = ["後", "前", "間", "以", "程", "過", "ほど", "くらい", "ぐらい", "おき", "ごと"];
    static readonly string[] ClockBefore = ["午前", "午後", "朝", "夜", "夕方", "深夜", "明日", "今日", "昨日"];
    static readonly string[] ClockAfter = ["に", "から", "まで", "頃", "ごろ", "過ぎ", "すぎ", "前", "台", "以降", "ちょうど"];

    public static string Arabize(string text)
    {
        if (!text.Any(IsNumeral)) return text;
        // かなを含まない文は中国語かもしれない（快一点）ので、数と単位だけでできているときだけ直す
        if (!text.Any(c => CharClasses.Of(c) == CharClass.Kana) && !NumbersOnly.IsMatch(text)) return text;
        var protectedIndices = new HashSet<int>();
        foreach (Match m in Idioms.Matches(text))
        {
            for (int p = m.Index; p < m.Index + m.Length; p++) protectedIndices.Add(p);
        }

        var output = new StringBuilder(text.Length);
        int i = 0;
        while (i < text.Length)
        {
            if (!IsNumeral(text[i]) || (i > 0 && IsNumeral(text[i - 1])))
            {
                output.Append(text[i]);
                i++;
                continue;
            }
            int j = i;
            while (j < text.Length && IsNumeral(text[j])) j++;
            var run = text[i..j];
            bool isProtected = false;
            for (int p = i; p < j; p++) isProtected |= protectedIndices.Contains(p);
            // Convert が見るのは、前の 2 文字と後ろの 8 文字まで
            if (!isProtected && Convert(run, text[Math.Max(0, i - 2)..i], text[j..Math.Min(text.Length, j + 8)]) is { } converted)
            {
                output.Append(converted.Text);
                i = j + converted.Consumed;
            }
            else
            {
                output.Append(run);
                i = j;
            }
        }
        return output.ToString();
    }

    /// 数の並びを算用数字にした文字列と、後ろから続けて読んだ文字数（小数の「点五」）を返す。変えないなら null。
    /// before は数の前の 2 文字まで、after は数の後ろの 8 文字まで
    static (string Text, int Consumed)? Convert(string run, string before, string after)
    {
        if (Parse(run) is not { } number) return null;
        if (before.Length > 0 && before[^1] is var last
            && (WordBefore.Contains(last) || CharClasses.Of(last) == CharClass.Digit || CharClasses.Of(last) == CharClass.Latin)) return null;
        var rest = after[..Math.Min(8, after.Length)];

        var m = Unit.Match(rest);
        if (!m.Success)
        {
            // 単位がなくても数とわかる形（三千万、二十ぐらい、百二十。）。四十七士・八百屋のように漢字やカタカナが続くなら語の一部
            if (run.Any(LargeUnits.Contains)) return (number, 0);
            if (run.Length >= 2 && (after.Length == 0 || (CharClasses.Of(after[0]) != CharClass.Han && !CharClasses.IsKatakana(after[0])))) return (number, 0);
            return null;
        }
        var unitText = m.Value;
        var tail = rest[m.Length..];
        bool plain = !run.Any(LargeUnits.Contains);

        // 小数（三点五 → 3.5）
        var fraction = new string(tail.TakeWhile(Digits.ContainsKey).ToArray());
        if (unitText == "点" && plain && fraction.Length > 0)
        {
            return (number + "." + string.Concat(fraction.Select(c => Digits[c].ToString(CultureInfo.InvariantCulture))), 1 + fraction.Length);
        }
        // 分数（三分の一 → 3分の1）
        var numeratorRun = new string(tail.Skip(1).TakeWhile(IsNumeral).ToArray());
        if (unitText == "分" && plain && tail.StartsWith('の') && Parse(numeratorRun) is { } numerator)
        {
            return (number + "分の" + numerator, 2 + numeratorRun.Length);
        }
        if (tail.Length > 0 && tail[0] is var next && CharClasses.Of(next) == CharClass.Han && !IsNumeral(next)
            && !AfterUnit.Contains(next) && !tail.StartsWith("中旬", StringComparison.Ordinal)) return null;
        if (unitText == "回" && tail.StartsWith('り')) return null;  // 一回り
        if (run == "十" && unitText == "分")
        {
            // 「十分です」「十分に」は じゅうぶん。時刻と時間の長さのときだけ 10分 にする
            return before.EndsWith('時') || AfterTenMinutes.Any(s => tail.StartsWith(s, StringComparison.Ordinal)) ? (number, 0) : null;
        }
        if (run == "一")
        {
            switch (unitText)
            {
                case "時":  // 一時的・一時は（いちじ）と区別する
                    bool clock = ClockBefore.Any(s => before.EndsWith(s, StringComparison.Ordinal));
                    if (!(clock || ClockAfter.Any(s => tail.StartsWith(s, StringComparison.Ordinal)))) return null;
                    break;
                case "度": if (!tail.StartsWith('目')) return null; break;  // もう一度・一度も
                case "番" or "代": return null;  // 一番好き・一代で
                case "円":  // 関東一円
                    if (before.Length > 0 && before[^1] is var b && CharClasses.Of(b) == CharClass.Han && !"約計各全".Contains(b)) return null;
                    break;
            }
        }
        return (number, 0);
    }

    /// 漢数字の並びを算用数字にする（三千万 → 3000万、二〇二六 → 2026、四十七 → 47）。数として読めなければ null
    static string? Parse(string run)
    {
        if (run.All(Digits.ContainsKey))
        {
            if (run.Length == 1) return Digits[run[0]].ToString(CultureInfo.InvariantCulture);
            // 「二〇二六」のような位取りの書き方だけを数とみなす（「二三日」「七五三」「〇〇さん」は変えない）
            if (!run.Contains('〇') || !run.Any(c => c != '〇')) return null;
            return string.Concat(run.Select(c => Digits[c].ToString(CultureInfo.InvariantCulture)));
        }
        var output = new StringBuilder();
        var segment = new StringBuilder();
        int previous = -1;  // 兆・億・万の順に小さくなる
        foreach (char c in run)
        {
            int rank = Array.IndexOf(LargeUnits, c);
            if (rank >= 0)
            {
                if (rank <= previous || Value(segment.ToString()) is not { } v) return null;
                output.Append(v.ToString(CultureInfo.InvariantCulture)).Append(c);
                previous = rank;
                segment.Clear();
            }
            else
            {
                segment.Append(c);
            }
        }
        if (segment.Length > 0)
        {
            if (Value(segment.ToString()) is not { } v) return null;
            output.Append(v.ToString(CultureInfo.InvariantCulture));
        }
        return output.ToString();
    }

    /// 万より小さい部分（三千五百 → 3500）。「二三」のように数字が続く、「百千」のように位が逆になるものは null
    static int? Value(string segment)
    {
        int total = 0;
        int? digit = null;
        int lastUnit = 10_000;
        foreach (char c in segment)
        {
            if (Digits.TryGetValue(c, out int d) && d > 0)
            {
                if (digit != null) return null;
                digit = d;
            }
            else if (SmallUnits.TryGetValue(c, out int u) && u < lastUnit)
            {
                total += (digit ?? 1) * u;
                digit = null;
                lastUnit = u;
            }
            else
            {
                return null;
            }
        }
        total += digit ?? 0;
        return total > 0 ? total : null;
    }
}
