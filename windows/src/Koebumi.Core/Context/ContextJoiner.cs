namespace Koebumi.Core;

// MARK: - つなぎ方

/// 入力する文を、カーソル前後の文字列と自然につながるように整える（空白・文頭の大文字・重なった句読点）。AI を使わない。
public static class ContextJoiner
{
    /// 文の途中で小文字にしてよい語（固有名詞は変えない）
    static readonly HashSet<string> Lowercasable =
    [
        "The", "A", "An", "And", "But", "So", "Or", "It", "This", "That", "These", "Those", "We", "You", "They",
        "He", "She", "There", "Then", "Also", "If", "When", "Because", "Which", "Who", "To", "In", "On", "At", "For", "With",
    ];

    /// Swift の Character.isNewline と同じ文字（LF・CR・VT・FF と NEL・LS・PS）
    static readonly char[] NewlineChars = [(char)0x0A, (char)0x0D, (char)0x0B, (char)0x0C, (char)0x85, (char)0x2028, (char)0x2029];

    public static string Join(string text, string before, string after)
    {
        var t = text;
        if (t.Length == 0) return t;
        // prev: カーソルの前の最後の 1 文字、next: カーソルの後の最初の 1 文字（なければ null）
        string? prev = before.Length == 0 ? null : ContextText.Last(before);
        string? next = after.Length == 0 ? null : ContextText.First(after);

        // 書き出しが、カーソルの前にある最後の行（宛名など）と同じなら繰り返さない（「東海林様」の下に「東海林様、…」）
        var lastLine = before.Split(NewlineChars, StringSplitOptions.RemoveEmptyEntries).LastOrDefault();
        if (lastLine is not null)
        {
            var line = ContextText.TrimWhitespaces(lastLine);
            if (ContextText.Count(line) >= 2 && t.StartsWith(line, StringComparison.Ordinal))
            {
                var rest = t[line.Length..];
                var sep = ContextText.First(rest);
                if (sep.Length > 0 && ContextText.In("、,，\n ", sep))
                {
                    t = ContextText.TrimWhitespacesAndNewlines(rest[sep.Length..]);
                    if (t.Length == 0) return text;
                }
            }
        }

        if (prev is not null && !ContextText.IsWhitespace(prev))
        {
            // 前が文の区切りなら、文頭の読点を消す（「です。」+「、それから」）
            if (ContextText.In("。．！？、，", prev) && ContextText.In("、，。．", ContextText.First(t)))
                t = t[ContextText.First(t).Length..];
            // 英語は前の語とのあいだに空白を入れる
            var head = t.Length == 0 ? " " : ContextText.First(t);
            if ((ContextText.IsLatin(prev) || ContextText.In(".,!?;:)]}%", prev)) && (ContextText.IsLatin(head) || ContextText.In("([{", head)))
                t = " " + t;
        }

        // 文の途中に入れるなら先頭を小文字に、文の頭なら大文字にする（英語）
        var trimmedBefore = ContextText.TrimWhitespaces(before);
        if (trimmedBefore.Length > 0)
        {
            var p = ContextText.Last(trimmedBefore);
            if (!ContextText.IsNewline(p))
            {
                var midSentence = ContextText.IsLatin(p) || p == ",";
                t = Recase(t, toLower: midSentence, toUpper: ContextText.In(".!?", p));
            }
        }

        if (next is not null && !ContextText.IsWhitespace(next) && t.Length > 0)
        {
            var end = ContextText.Last(t);
            // 後ろが句点なら、入れる文の最後の句点や「？」を消す（「。。」「？。」にしない）
            if (ContextText.In("。．", next) && (ContextText.In("。．？", end) || next == "." && end == "."))
            {
                t = t[..^end.Length];
            }
            else if (ContextText.ClassOf(next).IsCJK && ContextText.In("。．", end) && !(prev is null || ContextText.In("。．！？\n", prev)))
            {
                // 日本語の文の途中に差し込むときは文末の「。」を付けない
                t = t[..^end.Length];
            }
            else if (ContextText.IsLowercase(next) && end == "." && prev is not null && ContextText.IsLatin(prev))
            {
                t = t[..^end.Length];
            }
            if (t.Length > 0)
            {
                var last = ContextText.Last(t);
                if (ContextText.IsLatin(next) && (ContextText.IsLatin(last) || ContextText.In(".,!?;:", last))) t += " ";
            }
        }
        return t;
    }

    static string Recase(string text, bool toLower, bool toUpper)
    {
        int spaces = 0;
        while (spaces < text.Length && text[spaces] == ' ') spaces++;
        var leading = text[..spaces];
        var body = text[spaces..];
        var c = ContextText.First(body);
        if (c.Length == 0 || ContextText.ClassOf(c) != CharClass.Latin) return text;
        if (toUpper && ContextText.IsLowercase(c))
            return leading + c.ToUpperInvariant() + body[c.Length..];
        if (toLower && ContextText.IsUppercase(c))
        {
            var word = string.Concat(ContextText.Elements(body).TakeWhile(ContextText.IsLetter));
            if (Lowercasable.Contains(word)) return leading + word.ToLowerInvariant() + body[word.Length..];
        }
        return text;
    }
}
