using System.Collections.Frozen;
using System.Globalization;
using System.Text;

namespace Koebumi.Core;

// MARK: - 人名の表記

/// 敬称（さん・様など）の前の名前を、読みが同じで画面に出ている表記に直す（渡辺さん → 渡邉さん、しょうじさん → 東海林さん）。
/// 読みは日本語解析（IJapaneseReader）で求める。画面に同じ読みの名前が複数あるときや、元の表記も画面にあるときは直さない。
/// Mac 版は macOS の日本語解析（CFStringTokenizer）、Windows 版は Reader にアプリが読みの実装を入れる
public static class ScreenNameFixer
{
    public static readonly IReadOnlySet<string> Honorifics = new[]
    {
        "さん", "様", "さま", "くん", "君", "ちゃん", "氏", "先生", "部長", "課長", "社長", "専務", "常務", "係長", "主任",
    }.ToFrozenSet();

    /// 既定の読みの実装（アプリが起動時に入れる）。null のときは読みがなく、名前は何も直さない
    public static IJapaneseReader? Reader { get; set; }

    /// 文の中の語と、その読み。Reading は小文字のヘボン式ローマ字（読みがない語は空。英字の語は表記そのもの）、
    /// Start と Length は文の中の位置（UTF-16 の位置と長さ）
    public readonly record struct Token(string Surface, string Reading, int Start, int Length)
    {
        public int End => Start + Length;
    }

    public static string Apply(string text, string reference) => Apply(text, reference, Reader);

    public static string Apply(string text, string reference, IJapaneseReader? reader)
    {
        if (reference.Length == 0 || !Honorifics.Any(h => text.Contains(h, StringComparison.Ordinal))) return text;
        var exact = new Dictionary<string, HashSet<string>>();
        var loose = new Dictionary<string, HashSet<string>>();
        var onScreen = Tokens(reference, reader);
        // 読みのない語は、読みの同じ別の語と間違えないよう数えない
        foreach (var t in onScreen.Where(t => t.Reading.Length > 0 && IsKanji(t.Surface) && t.Surface.Length is >= 2 and <= 4))
        {
            Add(exact, t.Reading.ToLowerInvariant(), t.Surface);
            Add(loose, LooseKey(t.Reading), t.Surface);
        }
        if (exact.Count == 0) return text;
        var surfaces = onScreen.Select(t => t.Surface).ToHashSet();

        var toks = Tokens(text, reader);
        var replacements = new List<(Token Token, string Target)>();
        for (int i = 0; i + 1 < toks.Count; i++)
        {
            if (!Honorifics.Contains(toks[i + 1].Surface)) continue;
            // 敬称の直前の語と、すぐ前に続く漢字の語（「渡辺健太さん」の姓）を見る
            for (int j = i; j >= 0 && j >= i - 1; j--)
            {
                var t = toks[j];
                if (j < i && (t.End != toks[j + 1].Start || !IsKanji(t.Surface))) break;
                // 「田中部長さん」の「田中」のように、別の敬称からも同じ語に届くことがある。同じ語を 2 度直さない
                if (Match(t, exact, loose) is { } target && !surfaces.Contains(t.Surface) && replacements.All(r => r.Token.Start != t.Start))
                    replacements.Add((t, target));
            }
        }
        var output = new StringBuilder(text);
        foreach (var (token, target) in replacements.OrderByDescending(r => r.Token.Start))
            output.Remove(token.Start, token.Length).Insert(token.Start, target);
        return output.ToString();

        static void Add(Dictionary<string, HashSet<string>> map, string key, string surface)
        {
            if (!map.TryGetValue(key, out var set)) map[key] = set = [];
            set.Add(surface);
        }
    }

    static string? Match(Token t, Dictionary<string, HashSet<string>> exact, Dictionary<string, HashSet<string>> loose)
    {
        HashSet<string>? candidates = null;
        if (t.Reading.Length == 0) return null;
        if (IsKanji(t.Surface) && t.Surface.Length >= 2)
            exact.TryGetValue(t.Reading.ToLowerInvariant(), out candidates);
        else if (IsHiragana(t.Surface) && t.Surface.Length >= 3)
            exact.TryGetValue(t.Reading.ToLowerInvariant(), out candidates);
        else if (t.Surface.All(c => c is (>= 'A' and <= 'Z') or (>= 'a' and <= 'z')) && t.Surface.Length >= 3)
            // ローマ字の名前（Shoji）は長音の書き方が揺れるので、長音を詰めて比べる
            loose.TryGetValue(LooseKey(t.Reading), out candidates);
        return candidates is { Count: 1 } && candidates.First() is var target && target != t.Surface ? target : null;
    }

    public static IReadOnlyList<Token> Tokens(string s) => Tokens(s, Reader);

    /// 文を語に分けて、読みを付ける。reader が null のときは読みがないので、文全体を 1 つの語（読みは空）にする
    public static IReadOnlyList<Token> Tokens(string s, IJapaneseReader? reader)
    {
        if (s.Length == 0) return [];
        if (reader is null) return [new Token(s, "", 0, s.Length)];
        var output = new List<Token>();
        foreach (var t in reader.Tokenize(s))
        {
            if (t.Surface.Length == 0) continue;
            var reading = KanaConverter.ToRomaji(t.Reading);
            // 英字の語の読みは、macOS の日本語解析と同じく表記そのもの
            if (reading.Length == 0 && t.Surface.All(char.IsAsciiLetter)) reading = t.Surface;
            output.Add(new Token(t.Surface, reading, t.Start, t.Surface.Length));
        }
        return output;
    }

    static string LooseKey(string reading)
    {
        var k = RemoveDiacritics(reading.ToLowerInvariant());
        foreach (var (longVowel, shortVowel) in new[] { ("ou", "o"), ("oo", "o"), ("uu", "u"), ("aa", "a"), ("ii", "i"), ("ee", "e") })
            k = k.Replace(longVowel, shortVowel, StringComparison.Ordinal);
        return k;
    }

    /// Swift の folding(.diacriticInsensitive) に当たる処理
    static string RemoveDiacritics(string s)
    {
        var sb = new StringBuilder(s.Length);
        foreach (var c in s.Normalize(NormalizationForm.FormD))
            if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark) sb.Append(c);
        return sb.ToString().Normalize(NormalizationForm.FormC);
    }

    static bool IsKanji(string s) => s.Length > 0 && s.All(c => CharClasses.Of(c) == CharClass.Han);
    static bool IsHiragana(string s) => s.Length > 0 && s.All(c => c is >= (char)0x3041 and <= (char)0x309F);
}
