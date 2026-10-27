using System.Text;

namespace Koebumi.Core;

/// 話した内容の最初と最後にある、呼び出す言葉だけの文を定型文にする（AI を使わない決まった処理）。
/// 呼び出す言葉の読みは ScreenNameFixer.Reader（または引数の reader）で求める
public static class SnippetExpander
{
    public const string AddresseeToken = "{宛名}";
    public const string GreetingToken = "{挨拶}";
    /// 呼び出す言葉として比べる長さの上限（文字数）
    const int MaxTriggerLength = 30;
    static readonly HashSet<string> Delimiters = ["。", "、", "，", "．", ",", ".", "!", "！", "?", "？", "\n", " ", "　", "\t"];
    static readonly string[] PoliteEndings = ["ます", "です", "ました", "でした", "ください", "ません", "ましょう"];

    public sealed record Parts
    {
        public IReadOnlyList<Snippet> Leading { get; init; } = [];
        /// AI で整形する部分
        public string Body { get; init; } = "";
        public IReadOnlyList<Snippet> Trailing { get; init; } = [];

        public bool HasSnippets => Leading.Count > 0 || Trailing.Count > 0;

        // 定型文の並びを中身で比べる（レコードの既定の比べ方は、リストの参照を比べてしまう）
        public bool Equals(Parts? other) =>
            other is not null && Body == other.Body && Leading.SequenceEqual(other.Leading) && Trailing.SequenceEqual(other.Trailing);

        public override int GetHashCode() => HashCode.Combine(Body, Leading.Count, Trailing.Count);
    }

    /// 書き起こしの最初と最後から、呼び出す言葉だけを話した文を取り出す（「よろしくお願いします。署名」→ 本文と「署名」）。
    /// 文の中で使った語（「署名をお願いします」）は呼び出しとみなさない
    public static Parts Split(string transcript, IReadOnlyList<Snippet> snippets) => Split(transcript, snippets, ScreenNameFixer.Reader);

    public static Parts Split(string transcript, IReadOnlyList<Snippet> snippets, IJapaneseReader? reader)
    {
        var body = ContextText.TrimWhitespacesAndNewlines(transcript);
        var usable = snippets
            .Where(s => Key(s.Trigger).Length > 0 && ContextText.TrimWhitespacesAndNewlines(s.Text).Length > 0)
            .ToList();
        if (usable.Count == 0) return new Parts { Body = body };
        var leading = new List<Snippet>();
        var trailing = new List<Snippet>();
        while (MatchEnd(body, usable, reader) is { } last)
        {
            trailing.Insert(0, last.Snippet);
            body = last.Remainder;
        }
        while (MatchStart(body, usable, reader) is { } first)
        {
            leading.Add(first.Snippet);
            body = first.Remainder;
        }
        return new Parts { Leading = leading, Body = body, Trailing = trailing };
    }

    /// 定型文の本文。宛名がわからないときは、{宛名} だけの行とその後の空行を書かない。{挨拶} は相手が社内なら「お疲れ様です。」
    public static string Render(Snippet snippet, MailReplyContext? reply)
    {
        var lines = new List<string>();
        var dropBlank = false;
        foreach (var line in snippet.Text.Split('\n'))
        {
            var blank = ContextText.TrimWhitespaces(line).Length == 0;
            if (line.Contains(AddresseeToken, StringComparison.Ordinal) && reply?.Addressee is null
                && ContextText.TrimWhitespaces(line.Replace(AddresseeToken, "", StringComparison.Ordinal)).Length == 0)
            {
                dropBlank = true;
                continue;
            }
            if (dropBlank && blank) { dropBlank = false; continue; }
            dropBlank = false;
            lines.Add(line.Replace(AddresseeToken, reply?.Addressee ?? "", StringComparison.Ordinal)
                .Replace(GreetingToken, (reply ?? new MailReplyContext()).Greeting, StringComparison.Ordinal));
        }
        return ContextText.TrimNewlines(string.Join("\n", lines));
    }

    /// 整形した本文と定型文を、1 行空けてつなぐ
    public static string Join(Parts parts, string body, MailReplyContext? reply) =>
        string.Join("\n\n",
            parts.Leading.Select(s => Render(s, reply)).Concat([body]).Concat(parts.Trailing.Select(s => Render(s, reply)))
                .Where(s => s.Length > 0));

    /// 本文を整形するときのカーソル前後。定型文と接する側は、カーソル前後の代わりに定型文を見せる（本文は定型文と段落を分けて入れる）
    public static SurroundingText? Surrounding(SurroundingText? s, Parts around, MailReplyContext? reply)
    {
        if (s is null) return null;
        if (around.Leading.Count > 0) s = s with { Before = string.Join("\n\n", around.Leading.Select(x => Render(x, reply))) + "\n\n" };
        if (around.Trailing.Count > 0) s = s with { After = "\n\n" + string.Join("\n\n", around.Trailing.Select(x => Render(x, reply))) };
        return s;
    }

    /// 定型文から入れるとき、カーソルの前の行に文があれば段落を分ける（「よろしくお願いいたします。」の後に「署名」）
    public static string LeadingBreak(Parts parts, string? before)
    {
        if (!(parts.Leading.Count > 0 || (parts.Body.Length == 0 && parts.HasSnippets))) return "";
        if (string.IsNullOrEmpty(before) || ContextText.IsNewline(ContextText.Last(before))) return "";
        return "\n\n";
    }

    /// 呼び出す言葉と、話した言葉が同じか。表記（署名・しょめい・ショメイ）が違っても、読みが同じなら同じとみなす
    public static bool Matches(string spoken, string trigger) => Matches(spoken, trigger, ScreenNameFixer.Reader);

    public static bool Matches(string spoken, string trigger, IJapaneseReader? reader)
    {
        string a = Key(spoken), b = Key(trigger);
        if (a.Length > 0 && a == b) return true;
        string ra = Reading(spoken, reader), rb = Reading(trigger, reader);
        return ra.Length > 0 && ra == rb;
    }

    /// 比べるための表記（空白と記号を除き、カタカナはひらがなに、英字は小文字にする）
    static string Key(string s) =>
        LettersAndNumbers(KanaConverter.ToHiragana(s).Normalize(NormalizationForm.FormC).ToLowerInvariant());

    /// 読みのローマ字（署名 → shomei）
    static string Reading(string s, IJapaneseReader? reader) =>
        LettersAndNumbers(string.Concat(ScreenNameFixer.Tokens(s, reader).Select(t => t.Reading.Length == 0 ? t.Surface : t.Reading)).ToLowerInvariant());

    static string LettersAndNumbers(string s) => string.Concat(ContextText.Elements(s).Where(ContextText.IsLetterOrNumber));

    /// 最後の文が呼び出す言葉なら、その定型文と残りを返す。区切りの後から始まる、いちばん長い一致を使う
    static (Snippet Snippet, string Remainder)? MatchEnd(string text, List<Snippet> snippets, IJapaneseReader? reader)
    {
        var chars = ContextText.Elements(text);
        int end = chars.Length;
        while (end > 0 && Delimiters.Contains(chars[end - 1])) end--;
        if (end == 0) return null;
        (Snippet Snippet, int Start)? best = null;
        for (int start = end - 1; start >= 0 && end - start <= MaxTriggerLength; start--)
        {
            if ((start == 0 || Delimiters.Contains(chars[start - 1]) || EndsSentence(chars, start)) && !Delimiters.Contains(chars[start]))
            {
                var spoken = string.Concat(chars[start..end]);
                if (snippets.FirstOrDefault(s => Matches(spoken, s.Trigger, reader)) is { } found) best = (found, start);
            }
        }
        if (best is not { } b) return null;
        // 「〜です、署名」の「、」と空白は残さない（「。」は文の終わりなので残す）
        int restEnd = b.Start;
        while (restEnd > 0 && ContextText.In(" 　\t、，,\n", chars[restEnd - 1])) restEnd--;
        return (b.Snippet, string.Concat(chars[..restEnd]));
    }

    /// 丁寧語の文末で終わっているか。音声認識が句点を付けずに次の語を続けたとき（お願いします署名）も、ここで文が切れたとみなす
    static bool EndsSentence(string[] chars, int start)
    {
        int from = Math.Max(0, start - 4);
        var tail = string.Concat(chars[from..start]);
        return PoliteEndings.Any(e => tail.EndsWith(e, StringComparison.Ordinal));
    }

    /// 最初の文が呼び出す言葉なら、その定型文と残りを返す
    static (Snippet Snippet, string Remainder)? MatchStart(string text, List<Snippet> snippets, IJapaneseReader? reader)
    {
        var chars = ContextText.Elements(text);
        int begin = 0;
        while (begin < chars.Length && Delimiters.Contains(chars[begin])) begin++;
        if (begin >= chars.Length) return null;
        (Snippet Snippet, int End)? best = null;
        for (int end = begin + 1; end <= chars.Length && end - begin <= MaxTriggerLength; end++)
        {
            if ((end == chars.Length || Delimiters.Contains(chars[end])) && !Delimiters.Contains(chars[end - 1]))
            {
                var spoken = string.Concat(chars[begin..end]);
                if (snippets.FirstOrDefault(s => Matches(spoken, s.Trigger, reader)) is { } found) best = (found, end);
            }
        }
        if (best is not { } b) return null;
        int restStart = b.End;
        while (restStart < chars.Length && Delimiters.Contains(chars[restStart])) restStart++;
        return (b.Snippet, string.Concat(chars[restStart..]));
    }
}
