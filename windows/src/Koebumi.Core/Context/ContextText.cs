using System.Globalization;
using System.Text;

namespace Koebumi.Core;

/// Swift の String・Character と同じ単位（拡張書記素クラスター）で文字列を扱う小さな道具。
/// C# の char は UTF-16 の単位なので、サロゲートペアや結合文字を割らないよう、ここで 1 文字ずつ切り出す。
/// 文字の性質（空白・英字・小文字など）は Swift の Character と同じく、先頭のスカラー値で決める
internal static class ContextText
{
    /// 1 文字（書記素クラスター）ずつの配列
    public static string[] Elements(string s)
    {
        var list = new List<string>();
        var e = StringInfo.GetTextElementEnumerator(s);
        while (e.MoveNext()) list.Add(e.GetTextElement());
        return [.. list];
    }

    /// 先頭の 1 文字。空なら ""
    public static string First(string s) => s.Length == 0 ? "" : StringInfo.GetNextTextElement(s);

    /// 最後の 1 文字。空なら ""
    public static string Last(string s)
    {
        if (s.Length == 0) return "";
        var starts = StringInfo.ParseCombiningCharacters(s);
        return s[starts[^1]..];
    }

    /// 文字数（Swift の String.count）
    public static int Count(string s) => new StringInfo(s).LengthInTextElements;

    /// 1 文字の element が、set の中の 1 文字か（Swift の `"…".contains(character)`）。複数の文字からなる element（"\r\n" など）は含まれない
    public static bool In(string set, string element) => element.Length == 1 && set.Contains(element[0]);

    static Rune FirstRune(string element) =>
        element.Length > 0 && Rune.TryGetRuneAt(element, 0, out var r) ? r : Rune.ReplacementChar;

    /// Swift の Character.isWhitespace（改行を含む）
    public static bool IsWhitespace(string element) => element.Length > 0 && Rune.IsWhiteSpace(FirstRune(element));
    /// Swift の Character.isNewline（"\r\n" も改行）
    public static bool IsNewline(string element) => element.Length > 0 && CharClasses.IsNewline(element[0]);
    public static bool IsLetter(string element) => element.Length > 0 && Rune.IsLetter(FirstRune(element));
    public static bool IsLetterOrNumber(string element) =>
        element.Length > 0 && (Rune.IsLetter(FirstRune(element)) || Rune.IsNumber(FirstRune(element)));
    public static bool IsLowercase(string element) => element.Length > 0 && Rune.IsLower(FirstRune(element));
    public static bool IsUppercase(string element) => element.Length > 0 && Rune.IsUpper(FirstRune(element));

    /// Swift の CharClass(Character)。基本多言語面の外の文字は、文字なら Latin、そうでなければ Other にする
    public static CharClass ClassOf(string element)
    {
        if (element.Length == 0) return CharClass.Other;
        if (char.IsHighSurrogate(element[0]))
            return element.Length > 1 && Rune.IsLetter(FirstRune(element)) ? CharClass.Latin : CharClass.Other;
        return CharClasses.Of(element[0]);
    }

    /// 英数字か（Latin か Digit）
    public static bool IsLatin(string element) => ClassOf(element) is CharClass.Latin or CharClass.Digit;

    // Foundation の CharacterSet.whitespaces（Zs と tab）と newlines
    static bool IsBlank(char c) => c == '\t' || CharUnicodeInfo.GetUnicodeCategory(c) == UnicodeCategory.SpaceSeparator;

    /// 前後の空白（改行は除く）を取る。Swift の `trimmingCharacters(in: .whitespaces)`
    public static string TrimWhitespaces(string s) => Trim(s, IsBlank);
    /// 前後の空白と改行を取る。Swift の `trimmingCharacters(in: .whitespacesAndNewlines)`
    public static string TrimWhitespacesAndNewlines(string s) => Trim(s, c => IsBlank(c) || CharClasses.IsNewline(c));
    /// 前後の改行を取る。Swift の `trimmingCharacters(in: .newlines)`
    public static string TrimNewlines(string s) => Trim(s, CharClasses.IsNewline);

    static string Trim(string s, Func<char, bool> isTrimmed)
    {
        int start = 0, end = s.Length;
        while (start < end && isTrimmed(s[start])) start++;
        while (end > start && isTrimmed(s[end - 1])) end--;
        return s[start..end];
    }
}

/// 正規表現で使う文字の種類。.NET の Regex には \p{Han}・\p{Hiragana}・\p{Katakana} がないので、Unicode の Script の範囲（基本多言語面）を書く。
/// カタカナの範囲には「・」（U+30FB）と「ー」（U+30FC）を含めない（どちらも Script は Common）。必要なら呼び出し側で足す。
/// 漢字の範囲には「々」（U+3005）を含む
internal static class ContextScripts
{
    public const string Han = @"\u2E80-\u2E99\u2E9B-\u2EF3\u2F00-\u2FD5\u3005\u3007\u3021-\u3029\u3038-\u303B\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFA6D\uFA70-\uFAD9";
    public const string Hiragana = @"\u3041-\u3096\u309D-\u309F";
    public const string Katakana = @"\u30A1-\u30FA\u30FD-\u30FF\u31F0-\u31FF\u32D0-\u32FE\u3300-\u3357\uFF66-\uFF6F\uFF71-\uFF9D";

    /// 行末（複数行モードの `$` の代わり）。.NET の `$` は「\n」の前にしか合わないので、Windows の改行「\r\n」の「\r」の前も行末とみなす
    public const string EndOfLine = @"(?=\r?$)";
}
