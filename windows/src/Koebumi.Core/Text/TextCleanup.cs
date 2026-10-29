using System.Text;
using System.Text.RegularExpressions;

namespace Koebumi.Core;

/// 認識結果と整形結果の表記をそろえる決まった処理（AI を使わない）。
/// 音声認識が日本語の文中に入れる空白（「明日は 9時」「今何時 ？」）や半角の「?」、全角英数字、漢数字（三時）を直す。
public static class TextNormalizer
{
    static readonly Regex CommaBeforePeriod = new(@"[、，]+([。．！？])");
    static readonly Regex RepeatedPunct = new(@"([、，。！？])[、，。]+");
    static readonly Regex PunctAtLineStart = new(@"(?m)^[、，。]+");
    static readonly Regex BlankLines = new(@"\n{3,}");

    public static string Normalize(string text)
    {
        bool japanese = text.Any(c => CharClasses.Of(c) == CharClass.Kana);
        var chars = JapaneseNumbers.Arabize(text).Select(HalfwidthAlphanumeric).ToArray();

        for (int i = 1; i < chars.Length; i++)
        {
            var next = i + 1 < chars.Length ? CharClasses.Of(chars[i + 1]) : CharClass.Newline;
            // 数字の間の全角の「．」「，」「：」を半角にする（３．５ → 3.5、１，０００ → 1,000、１０：３０ → 10:30）。
            // 全角のままだと、句読点の設定で「3。5」「1、000」になる
            if (CharClasses.Of(chars[i - 1]) == CharClass.Digit && next == CharClass.Digit)
            {
                switch (chars[i])
                {
                    case '．': chars[i] = '.'; break;
                    case '，': chars[i] = ','; break;
                    case '：': chars[i] = ':'; break;
                }
            }
            // 日本語・中国語の後ろの半角句読点を全角にする
            if (!CharClasses.Of(chars[i - 1]).IsCJK) continue;
            switch (chars[i])
            {
                case '?': chars[i] = '？'; break;
                case '!': chars[i] = '！'; break;
                case ',': chars[i] = japanese ? '、' : '，'; break;
                case '.': if (next is CharClass.Newline or CharClass.Space || next.IsCJK) chars[i] = '。'; break;
            }
        }

        // 空白の連なりを、前後の文字を見て消すか 1 つにまとめる（行頭のインデントは残す）
        var output = new StringBuilder(chars.Length);
        int k = 0;
        while (k < chars.Length)
        {
            char c = chars[k];
            if (CharClasses.Of(c) != CharClass.Space)
            {
                output.Append(c);
                k++;
                continue;
            }
            int j = k;
            while (j < chars.Length && CharClasses.Of(chars[j]) == CharClass.Space) j++;
            bool atLineStart = output.Length == 0 || CharClasses.IsNewline(output[^1]);
            if (atLineStart)
            {
                for (int s = k; s < j; s++) output.Append(chars[s] == '\u3000' ? ' ' : chars[s]);
            }
            else if (j < chars.Length && !CharClasses.IsNewline(chars[j]) && !ShouldDropSpace(output[^1], chars[j]))
            {
                output.Append(' ');
            }
            k = j;
        }

        var t = output.ToString();
        // 重なった句読点（「、。」「。。」）をまとめる
        t = CommaBeforePeriod.Replace(t, "$1");
        t = RepeatedPunct.Replace(t, "$1");
        t = PunctAtLineStart.Replace(t, "");
        t = BlankLines.Replace(t, "\n\n");
        return t.Trim();
    }

    static bool ShouldDropSpace(char a, char b)
    {
        var ca = CharClasses.Of(a);
        var cb = CharClasses.Of(b);
        if (ca == CharClass.CjkPunct || cb == CharClass.CjkPunct) return true;
        if (ca.IsCJK && (cb.IsCJK || cb == CharClass.Digit)) return true;
        if (cb.IsCJK && ca == CharClass.Digit) return true;
        // 英語の句読点の前の空白（"hello , world"）
        if (b is ',' or '.' or '?' or '!' or ';' or ':' && ca is CharClass.Latin or CharClass.Digit) return true;
        return false;
    }

    /// 全角英数字（ＡＢＣ１２３）を半角にする。全角カタカナや記号はそのまま。
    static char HalfwidthAlphanumeric(char c) => c switch
    {
        >= '０' and <= '９' or >= 'Ａ' and <= 'Ｚ' or >= 'ａ' and <= 'ｚ' => (char)(c - 0xFEE0),
        _ => c,
    };
}

/// 箇条書きの項目の書き方をそろえる。話した文末が最後の項目にだけ残ったもの（「2. 返信です。」）を、
/// ほかの項目（「1. 資料作成」）に合わせて外す。
public static class ListTidier
{
    static readonly Regex Item = new(@"^[ \t]*(?:[0-9]+[.)]|[-・•])[ \t]+");
    static readonly Regex SpokenEnding = new(@"(?:です|でした)?。$");

    public static string Tidy(string text)
    {
        var lines = text.Split('\n');
        int i = 0;
        while (i < lines.Length)
        {
            if (!IsItem(lines[i])) { i++; continue; }
            int j = i;
            while (j + 1 < lines.Length && IsItem(lines[j + 1])) j++;
            // 2 項目以上あり、最後以外がどれも句点なしで終わっていて、最後の項目が 1 文のときだけ直す
            // （「2. 返信です。以上です。」の「以上です。」は項目の後に続けた文なので、句点を外さない）
            var last = lines[j];
            if (j > i && lines[i..j].All(l => !l.EndsWith('。'))
                && last.AsSpan(0, Math.Max(0, last.Length - 1)).IndexOfAny("。！？") < 0)
            {
                lines[j] = SpokenEnding.Replace(last, "");
            }
            i = j + 1;
        }
        return string.Join("\n", lines);
    }

    static bool IsItem(string line) => Item.IsMatch(line);
}

/// 辞書の「聞き取られ方」（例: スピーク → Speak）を正しい表記に置き換える。
/// Apple の音声認識は辞書のヒントを使わず、英語の語をカタカナで書くため、認識後に直す。
public static class VocabularyReplacer
{
    public static string Apply(string text, IReadOnlyDictionary<string, string> aliases)
    {
        if (aliases.Count == 0 || text.Length == 0) return text;
        var t = text;
        // 長い表記から置き換える（「クロードコード」を「クロード」より先に）
        foreach (var (alias, term) in aliases.OrderByDescending(p => p.Key.Length))
        {
            if (alias.Length == 0 || alias == term) continue;
            t = Replace(alias, term, t);
        }
        return t;
    }

    static string Replace(string alias, string term, string text)
    {
        var result = new StringBuilder();
        int rest = 0;
        int r;
        while ((r = text.IndexOf(alias, rest, StringComparison.OrdinalIgnoreCase)) >= 0)
        {
            int end = r + alias.Length;
            char before = r > rest ? text[r - 1] : (result.Length > 0 ? result[^1] : ' ');
            char after = end < text.Length ? text[end] : ' ';
            // 「スピーカー」の中の「スピーク」や "speaker" の中の "speak" は置き換えない
            bool joined = Continues(alias[0], before) || Continues(alias[^1], after);
            result.Append(text, rest, r - rest);
            if (joined) result.Append(text, r, alias.Length);
            else result.Append(term);
            rest = end;
        }
        return result.Append(text, rest, text.Length - rest).ToString();
    }

    /// 2 つの文字が 1 つの語として続いているか（カタカナ同士、英数字同士）
    static bool Continues(char edge, char neighbor)
    {
        if (CharClasses.IsKatakana(edge)) return CharClasses.IsKatakana(neighbor);
        var e = CharClasses.Of(edge);
        var n = CharClasses.Of(neighbor);
        if (e is CharClass.Latin or CharClass.Digit) return n is CharClass.Latin or CharClass.Digit;
        return false;
    }
}

/// 「改行」「段落」などの音声コマンド。文として単独で話されたときだけ改行にする（「改行コード」などは残す）。
public static class SpokenCommands
{
    /// strict の語は後ろに句読点か行末が来たときだけ、そうでない語は後ろが助詞や英字でなければ改行にする
    /// （「新しい段落田中です」は改行、「新しい行を追加」は残す）
    static readonly (string Words, string Replacement, bool Strict)[] Commands =
    [
        ("新しい段落|次の段落|new paragraph|next paragraph", "\n\n", false),
        ("段落", "\n\n", true),
        ("新しい行|次の行|new line|next line|newline", "\n", false),
        ("改行", "\n", true),
    ];
    const string Space = @"[ \t　]*";
    const string StrictEnd = Space + @"(?:[。、，．.,]" + Space + @"|$|(?=\n))";
    const string LooseEnd = "(?:" + StrictEnd + "|" + Space + @"(?![をがにはのでともへやa-zA-Z \t　]))";

    static readonly Regex[] Patterns = Commands
        .Select(c => new Regex(@"(?:^|(?<=[。、，．！？.,!?\n]))" + Space + "(?:" + c.Words + ")" + (c.Strict ? StrictEnd : LooseEnd),
            RegexOptions.IgnoreCase | RegexOptions.CultureInvariant))
        .ToArray();
    static readonly Regex CommaBeforeNewline = new(@"[、， \t]+\n");

    public static string Apply(string text)
    {
        var t = text;
        for (int i = 0; i < Commands.Length; i++)
        {
            t = Patterns[i].Replace(t, Commands[i].Replacement);
        }
        // 改行の直前に残った読点と空白を消す（英語の "Hi Tom," のカンマは残す）
        return CommaBeforeNewline.Replace(t, "\n");
    }
}

/// AI 整形を使わない・使えないときの整形（フィラーの除去と表記の統一）
public static class BasicCleaner
{
    /// 単独で出てきたら必ずフィラーとみなす語
    const string JaFillers = "えーっと|えーと|えっと|ええと|あのー+|そのー+|うーん|うーむ|んー+";
    /// 後ろに読点などが続くときだけフィラーとみなす語（「あの人」「まあまあ」は残す）
    const string JaFillersBeforePunct = "あの|その|まあ|なんか";
    /// さらに文頭か句読点の後でだけフィラーとみなす語（「ねえー、」の「えー」は残す）
    const string JaInterjections = "えー+|あー+";
    const string EnFillerWords = @"\b(?:u+m+|u+h+|e+r+m+|u+h+m+|h+m+)\b";
    /// 行頭のフィラーは後ろの空白ごと、文中のフィラーは前のカンマと空白ごと取り除く
    const string EnFillersAtLineStartPattern = @"(?m)^[ \t]*" + EnFillerWords + @"[,.]?[ \t]*";
    const string EnFillersPattern = @",?[ \t]*" + EnFillerWords + @"[,.]?(?=\s|$)";
    const string EnStutterWords = "the|a|an|i|to|of|in|on|at|for|and|or|but|we|you|it|my|this|with|is|are|was";

    const string Boundary = @"(?<=^|[。、！？!?\s「])";

    const RegexOptions IgnoreCase = RegexOptions.IgnoreCase | RegexOptions.CultureInvariant;

    static readonly Regex JaFillerWords = new(Boundary + "(?:" + JaFillers + @")(?:ですね)?[、，,… \t　]*");
    static readonly Regex JaOpeners = new(@"(?<=^|[。！？\n])[ \t　]*(?:なんか|あの|その|で)[、，,]+[ \t　]*");
    static readonly Regex JaFillersBeforePunctuation = new("(?:" + JaFillersBeforePunct + @")(?:ですね)?[、，,…]+[ \t　]*");
    static readonly Regex JaInterjectionWords = new(Boundary + "(?:" + JaInterjections + @")(?:ですね)?[、，,。…]+[ \t　]*");
    static readonly Regex JaOpeningDe = new(@"(?<=^|[。！？\n])で、");
    static readonly Regex EnFillersAtLineStart = new(EnFillersAtLineStartPattern, IgnoreCase);
    static readonly Regex EnFillers = new(EnFillersPattern, IgnoreCase);
    static readonly Regex YouKnowAtStart = new(@"(?:^|(?<=[.!?]\s))you know,\s*", IgnoreCase);
    static readonly Regex YouKnowInside = new(@",\s*you know,", IgnoreCase);
    static readonly Regex Stutter = new(@"\b(" + EnStutterWords + @")(?:\s+\1\b)+", IgnoreCase);
    static readonly Regex PunctAtLineStart = new(@"(?m)^[,.、。]+ *");

    /// 内容になりえないフィラー（「えーと」「あのー」「um」）だけを取り除く。AI の出力の仕上げにも使う。
    public static string RemoveFillers(string text)
    {
        var t = JaFillerWords.Replace(text, "");
        // 文頭の「なんか、」「あの、」「その、」「で、」は話し始めのつなぎ（「まあ、」は意味があることもあるので AI に任せる）
        t = JaOpeners.Replace(t, "");
        t = EnFillersAtLineStart.Replace(t, "");
        t = EnFillers.Replace(t, "");
        return t.Trim();
    }

    public static string Clean(string text)
    {
        var t = text;
        t = JaFillerWords.Replace(t, "");
        t = JaFillersBeforePunctuation.Replace(t, "");
        t = JaInterjectionWords.Replace(t, "");
        // 話し始めの「で、」
        t = JaOpeningDe.Replace(t, "");
        t = EnFillersAtLineStart.Replace(t, "");
        t = EnFillers.Replace(t, "");
        t = YouKnowAtStart.Replace(t, "");
        t = YouKnowInside.Replace(t, ",");
        t = Stutter.Replace(t, "$1");
        t = SpokenCommands.Apply(t);
        t = TextNormalizer.Normalize(t);
        t = PunctAtLineStart.Replace(t, "");
        if (t.Length > 0 && char.IsLower(t[0]) && CharClasses.Of(t[0]) == CharClass.Latin)
        {
            t = t[..1].ToUpperInvariant() + t[1..];
        }
        return t;
    }
}
