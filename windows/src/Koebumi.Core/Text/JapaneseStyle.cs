using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace Koebumi.Core;

public static class JapaneseNotationExtensions
{
    extension(JapanesePunctuation punctuation)
    {
        public string Title => punctuation switch
        {
            JapanesePunctuation.Standard => T("「、」と「。」", "、 and 。"),
            JapanesePunctuation.CommaMaru => T("「，」と「。」", "， and 。"),
            _ => T("「，」と「．」", "， and ．"),
        };

        public string Comma => punctuation == JapanesePunctuation.Standard ? "、" : "，";
        public string Period => punctuation == JapanesePunctuation.CommaPeriod ? "．" : "。";
    }

    extension(LatinSpacing spacing)
    {
        public string Title => spacing switch
        {
            LatinSpacing.Keep => T("そのまま", "Leave as is"),
            LatinSpacing.Remove => T("入れない（iPhoneを）", "None (iPhoneを)"),
            _ => T("入れる（iPhone を）", "Add (iPhone を)"),
        };
    }
}

/// 日本語の出力を表記ルールに合わせる決まった処理。TextNormalizer で全角・半角と空白をそろえた後に使う。
public static class JapaneseFormatter
{
    // .NET の Regex には文字の種類（\p{Han}・\p{Hiragana}・\p{Katakana}）がないので、Unicode の Script の範囲（基本多言語面）を書く。
    // カタカナの範囲には「・」（U+30FB）と「ー」（U+30FC）を含めない（どちらも Script は Common）
    const string Han = @"\u2E80-\u2E99\u2E9B-\u2EF3\u2F00-\u2FD5\u3005\u3007\u3021-\u3029\u3038-\u303B\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFA6D\uFA70-\uFAD9";
    const string Hiragana = @"\u3041-\u3096\u309D-\u309F";
    const string Katakana = @"\u30A1-\u30FA\u30FD-\u30FF\u31F0-\u31FF\u32D0-\u32FE\u3300-\u3357\uFF66-\uFF6F\uFF71-\uFF9D";

    public static string Apply(string text, JapaneseNotation notation)
    {
        // かなを含む文だけを日本語とみなす（中国語や英語の出力は変えない）
        if (!text.Any(c => CharClasses.Of(c) == CharClass.Kana)) return text;
        var t = FixDoubleHonorifics(text);
        if (notation.HiraganaForms) t = OpenKanji(t);
        if (notation.QuestionMark) t = MarkQuestions(t);
        t = Punctuate(t, notation.Punctuation);
        return Space(t, notation.LatinSpacing);
    }

    static string Punctuate(string text, JapanesePunctuation style)
    {
        var t = text;
        foreach (var c in new[] { "、", "，" }) if (c != style.Comma) t = t.Replace(c, style.Comma);
        foreach (var p in new[] { "。", "．" }) if (p != style.Period) t = t.Replace(p, style.Period);
        return t;
    }

    static readonly Regex Question = new(@"(?m)(です|ます|でしょう|ません|ました|でした|ましょう)か(?:[。．]|(?=[ \t]*$))");

    /// 丁寧語の疑問の文末（〜ですか。〜ませんか。）を「？」で終える。句点のない行末も同じ。
    /// 「そうか。」「いいか。」のような独り言や、「今何時」のように語尾で疑問とわからない文は変えない
    public static string MarkQuestions(string text) => Question.Replace(text, "$1か？");

    const string JapaneseLetter = "[" + Han + Hiragana + Katakana + "ー々]";
    /// 英字で始まる語（iPhone, GPT-5, Node.js, C++）
    const string LatinWord = @"[A-Za-z](?:[A-Za-z0-9+#._/-]*[A-Za-z0-9+#])?";

    static readonly Regex SpaceAfterJapanese = new("(?<=" + JapaneseLetter + ") +(?=[A-Za-z0-9])");
    static readonly Regex SpaceBeforeJapanese = new("(?<=[A-Za-z0-9]) +(?=" + JapaneseLetter + ")");
    static readonly Regex LatinWordRegex = new(LatinWord);
    static readonly Regex OneJapaneseLetter = new(@"\A" + JapaneseLetter + @"\z");

    static string Space(string text, LatinSpacing rule)
    {
        switch (rule)
        {
            case LatinSpacing.Keep:
                return text;
            case LatinSpacing.Remove:
                var t = SpaceAfterJapanese.Replace(text, "");
                t = SpaceBeforeJapanese.Replace(t, "");
                return t;
            default:
                // 英字で始まる語の両側にだけ入れる。「3時」「10分」のような数字と単位はつなげたまま
                var starts = StringInfo.ParseCombiningCharacters(text);
                var output = new StringBuilder(text);
                var matches = LatinWordRegex.Matches(text);
                for (int i = matches.Count - 1; i >= 0; i--)
                {
                    var m = matches[i];
                    int end = m.Index + m.Length;
                    if (end < text.Length && IsJapaneseLetter(text, starts, end)) output.Insert(end, ' ');
                    if (m.Index > 0 && IsJapaneseLetter(text, starts, m.Index - 1)) output.Insert(m.Index, ' ');
                }
                return output.ToString();
        }
    }

    /// index を含む 1 文字（結合文字を含めた文字の単位。Swift の rangeOfComposedCharacterSequence と同じ）が日本語の文字か
    static bool IsJapaneseLetter(string text, int[] starts, int index)
    {
        int k = Array.BinarySearch(starts, index);
        if (k < 0) k = ~k - 1;
        int end = k + 1 < starts.Length ? starts[k + 1] : text.Length;
        return OneJapaneseLetter.IsMatch(text.AsSpan(starts[k], end - starts[k]));
    }

    /// 補助動詞・形式名詞などの「ひらく」書き方（公用文作成の考え方・記者ハンドブックの方針に沿う）。
    /// 本来の意味の動詞・名詞（「資料を下さい」「大事」「出来事」）は変えないよう、前後の文字で絞る。
    static readonly (Regex Pattern, string Template)[] Openings =
    [
        // 補助動詞: 〜して下さい・ご確認下さい → ください
        (new("(?<=[てで])下さ(?=[いるっれら])"), "くださ"),
        (new("(?<=[おご][" + Han + "]{1,3}[" + Hiragana + "]{0,2})下さ(?=[いるっれら])"), "くださ"),
        // 〜して頂く・ご確認頂けますか → いただく
        (new("(?<=[てで])頂(?=[きくけこ])"), "いただ"),
        (new("(?<=[おご][" + Han + "]{1,3}[" + Hiragana + "]{0,2})頂(?=[きくけこ])"), "いただ"),
        // お願い致します・ご連絡致します → いたします（「一致します」は変えない）
        (new("(?<=[" + Hiragana + "])致(?=し[まてた])"), "いた"),
        (new("(?<=[おご][" + Han + "]{1,3})致(?=し[まてた])"), "いた"),
        // 出来る → できる（「出来事」「上出来」は変えない）
        (new("(?<![上不])出来(?=[るなたれずまそて])"), "でき"),
        // 形式名詞: する事が → することが、行く時に → 行くときに、その為に → そのために、この様に → このように
        (new("(?<=[" + Hiragana + "])事(?=[がはをにもで、。]|から|まで|より|$)"), "こと"),
        (new("(?<=[るたいうくすつぬむぶぐなだ])時(?=[はにのもで、]|まで|から)"), "とき"),
        (new("(?<=[のるたいな])為(?=[にのだで、。])"), "ため"),
        (new("(?<=[のな])様(?=[にな]|です|だ)"), "よう"),
        // 接続詞・あいさつ
        (new("(?<![" + Han + "])又(?=は|、)"), "また"),
        (new("(?<![" + Han + "])但し"), "ただし"),
        (new("宜しく"), "よろしく"),
        (new("有難う"), "ありがとう"),
        (new("御座い"), "ござい"),
    ];

    const string HonorificBefore = "(?<=ご覧|お召し上がり|[おご][" + Han + "]{1,2}[" + Hiragana + "]?)";

    /// 二重敬語（おっしゃられる・ご覧になられる）を正しい形に直す。「部長になられた」のような単独の敬語は変えない
    static readonly (Regex Pattern, string Template)[] DoubleHonorifics =
    [
        (new("おっしゃられ(?=[たて])"), "おっしゃっ"),
        (new("おっしゃられ(?=ま)"), "おっしゃい"),
        (new("おっしゃられる"), "おっしゃる"),
        (new("おっしゃられ(?=な)"), "おっしゃら"),
        (new(HonorificBefore + "になられ(?=[たて])"), "になっ"),
        (new(HonorificBefore + "になられ(?=ま)"), "になり"),
        (new(HonorificBefore + "になられる"), "になる"),
    ];

    public static string FixDoubleHonorifics(string text)
    {
        var t = text;
        foreach (var (pattern, template) in DoubleHonorifics) t = pattern.Replace(t, template);
        return t;
    }

    public static string OpenKanji(string text)
    {
        var t = text;
        foreach (var (pattern, template) in Openings) t = pattern.Replace(t, template);
        return t;
    }
}
