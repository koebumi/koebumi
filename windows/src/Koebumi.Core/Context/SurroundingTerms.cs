using System.Text.RegularExpressions;

namespace Koebumi.Core;

public static class SurroundingTextExtensions
{
    extension(SurroundingText s)
    {
        /// 音声認識のヒントにする語（敬称の付いた人名・カタカナ語・英字の固有名詞）
        public IReadOnlyList<string> Terms =>
            SurroundingTerms.Extract(string.Join("\n", s.Before, s.After, s.Screen, s.ScreenAfter));
    }
}

// MARK: - 音声認識のヒント

public static class SurroundingTerms
{
    const string Han = ContextScripts.Han;
    const string Katakana = ContextScripts.Katakana;

    static readonly Regex[] Patterns = new[]
    {
        // 敬称の付いた人名（田中さん・佐藤様・鈴木部長）
        "[" + Han + "]{1,4}(?=さん|様|さま|くん|君|ちゃん|氏|先生|部長|課長|社長|専務|常務)",
        // 姓と名を空白で区切った表示名（チャットの「渡邉 健太」）の姓と名
        @"(?<=^|\s)[" + Han + "]{1,4}(?=[ 　][" + Han + @"]{1,4}(?:\s|$))",
        "(?<=[" + Han + "][ 　])[" + Han + @"]{1,4}(?=\s|$)",
        // 大文字で始まる語の並び（Claude Code, Google Docs）
        @"\b[A-Z][A-Za-z0-9]*(?:[ ][A-Z][A-Za-z0-9]*)+\b",
        // 大文字や数字を含む英字の語（iPhone, AWS, GPT-5）
        @"\b[A-Za-z][A-Za-z0-9]*[A-Z0-9][A-Za-z0-9-]*\b",
        // 大文字で始まる語（Claude, Slack）
        @"\b[A-Z][a-z]{2,}\b",
        // カタカナ語（サービス名・人名）
        "[" + Katakana + "ー]{3,12}",
    }.Select(p => new Regex(p, RegexOptions.Multiline | RegexOptions.CultureInvariant)).ToArray();

    static readonly HashSet<string> Stopwords =
    [
        "The", "This", "That", "These", "Those", "And", "But", "For", "With", "You", "Your", "Our", "They", "Thanks", "Thank",
        "Hi", "Hello", "Dear", "Best", "Regards", "Please", "What", "When", "Where", "Why", "How", "Yes", "Not", "Are", "Was",
        "From", "Subject", "Date", "Sent", "Reply", "Forward", "Fwd",
    ];

    public static IReadOnlyList<string> Extract(string text, int limit = 40)
    {
        var seen = new HashSet<string>();
        var output = new List<string>();
        foreach (var re in Patterns)
        {
            foreach (Match m in re.Matches(text))
            {
                var term = m.Value;
                var space = term.IndexOf(' ');
                var first = space < 0 ? term : term[..space];
                if (term.Length < 2 || Stopwords.Contains(term) || Stopwords.Contains(first) || !seen.Add(term)) continue;
                // 「Claude Code」を拾ったら「Claude」「Code」は足さない
                if (!term.Contains(' ') && output.Any(o => o.Split(' ', StringSplitOptions.RemoveEmptyEntries).Contains(term))) continue;
                output.Add(term);
                if (output.Count >= limit) return output;
            }
        }
        return output;
    }
}
