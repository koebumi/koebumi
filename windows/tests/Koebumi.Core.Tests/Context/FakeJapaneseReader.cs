using Koebumi.Core;

namespace Koebumi.Core.Tests;

/// Mac 版のテストが頼っている macOS の日本語解析（CFStringTokenizer）の代わりになる、偽の IJapaneseReader。
/// テストの文に出てくる語だけを辞書で持ち、辞書にない語は次のように分ける。
/// かなの連なりは 1 つの語で、読みは表記そのまま（ひらがな）。英数字の連なりと、辞書にない漢字などの連なりは 1 つの語で、読みは空。
/// 空白と記号は語にしない
public sealed class FakeJapaneseReader : IJapaneseReader
{
    static readonly Dictionary<string, string> Words = new()
    {
        // 人名
        ["渡辺"] = "わたなべ", ["渡邉"] = "わたなべ", ["健太"] = "けんた", ["太郎"] = "たろう", ["東海林"] = "しょうじ", ["庄司"] = "しょうじ",
        ["斎藤"] = "さいとう", ["齋藤"] = "さいとう", ["高橋"] = "たかはし", ["髙橋"] = "たかはし", ["伊藤"] = "いとう", ["伊東"] = "いとう",
        ["小野"] = "おの", ["大野"] = "おおの", ["皆"] = "みな", ["美奈"] = "みな", ["田中"] = "たなか", ["佐藤"] = "さとう", ["山田"] = "やまだ",
        // 敬称（ScreenNameFixer.Honorifics）
        ["さん"] = "さん", ["様"] = "さま", ["さま"] = "さま", ["くん"] = "くん", ["君"] = "くん", ["ちゃん"] = "ちゃん", ["氏"] = "し",
        ["先生"] = "せんせい", ["部長"] = "ぶちょう", ["課長"] = "かちょう", ["社長"] = "しゃちょう", ["専務"] = "せんむ", ["常務"] = "じょうむ",
        ["係長"] = "かかりちょう", ["主任"] = "しゅにん",
        // そのほか
        ["明日"] = "あした", ["件"] = "けん", ["共有"] = "きょうゆう", ["資料"] = "しりょう", ["見積書"] = "みつもりしょ", ["署名"] = "しょめい",
        ["公園"] = "こうえん", ["講演"] = "こうえん",
    };

    static readonly int MaxWordLength = Words.Keys.Max(w => w.Length);

    public IReadOnlyList<ReadingToken> Tokenize(string text)
    {
        var tokens = new List<ReadingToken>();
        int i = 0;
        while (i < text.Length)
        {
            if (IsSeparator(text[i])) { i++; continue; }
            if (Longest(text, i) is { } word)
            {
                tokens.Add(new ReadingToken(word, Words[word], i));
                i += word.Length;
                continue;
            }
            int start = i;
            Func<char, bool> sameRun = IsKana(text[i]) ? IsKana : IsAsciiWord(text[i]) ? IsAsciiWord : IsOther;
            do i++; while (i < text.Length && sameRun(text[i]) && Longest(text, i) is null);
            var surface = text[start..i];
            tokens.Add(new ReadingToken(surface, IsKana(text[start]) ? KanaConverter.ToHiragana(surface) : "", start));
        }
        return tokens;
    }

    static string? Longest(string text, int index)
    {
        for (int length = Math.Min(MaxWordLength, text.Length - index); length > 0; length--)
        {
            var candidate = text.Substring(index, length);
            if (Words.ContainsKey(candidate)) return candidate;
        }
        return null;
    }

    static bool IsKana(char c) => CharClasses.Of(c) == CharClass.Kana;
    static bool IsAsciiWord(char c) => char.IsAsciiLetterOrDigit(c);
    static bool IsSeparator(char c) => char.IsWhiteSpace(c) || char.IsPunctuation(c) || char.IsSymbol(c) || CharClasses.Of(c) == CharClass.CjkPunct;
    static bool IsOther(char c) => !IsSeparator(c) && !IsKana(c) && !IsAsciiWord(c);
}
