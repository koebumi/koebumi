using System.Text.RegularExpressions;

namespace Koebumi.Core;

/// 返信先のメール（画面に出ている受信メール）から読んだ、相手の名前と間柄。
/// この PC の中で画面の文字から読む。宛名の敬称と書き出しの挨拶をそろえるのに使う。
public sealed record MailReplyContext
{
    /// 相手の姓（差出人の表示名か、受信メールでの名乗り）
    public string? Name { get; init; }
    /// 相手の姓名（表示名が「東海林 太郎」なら「東海林太郎」）
    public string? FullName { get; init; }
    /// 相手に付ける敬称（様・さん）
    public string Honorific { get; init; } = "様";
    /// 社外の相手か。受信メールの挨拶が「お世話になっております」なら true、「お疲れ様です」なら false、どちらもなければ null
    public bool? External { get; init; }

    /// 宛名（東海林様）
    public string? Addressee => Name is { } name ? name + Honorific : null;
    /// 書き出しの挨拶。社内の相手には「お疲れ様です。」、それ以外は「お世話になっております。」
    public string Greeting => External == false ? "お疲れ様です。" : "お世話になっております。";
}

/// 日本語のメールの宛名と挨拶を、返信先のメールに合わせる決まった処理（AI を使わない）
public static class MailReply
{
    const string Han = ContextScripts.Han;
    const string Hiragana = ContextScripts.Hiragana;
    const string Katakana = ContextScripts.Katakana;
    const string EndOfLine = ContextScripts.EndOfLine;

    const string ExternalGreeting = "(?:いつも|大変)?(?:お世話になっております|お世話になります|お世話様です)";
    const string InternalGreeting = "(?:お疲れ様|お疲れさま|おつかれさま)(?:です|でございます)";
    const string FamilyName = "[" + Han + "]{1,4}|[" + Katakana + "ー]{2,8}";
    /// 差出人の表示名とアドレス（東海林 太郎 <shoji@example.co.jp>）。Gmail は名前とアドレスを別の行に出す
    const string Sender = @"(?m)^([^\n]*?)(?<![" + Han + Katakana + @"ー])([" + Han + @"]{1,7}|[" + Katakana + @"ー]{2,12})(?:[ 　]([" + Han + Hiragana + Katakana + @"ー]{1,8}))?[ 　]*(?:\r?\n)?[ 　]*[<＜][^<>＜＞\s@]+@[^<>＜＞\s]+[>＞]";
    /// 受信メールの書き出しの宛名の行（矢野様・矢野さん・株式会社ABC 矢野様）。返信する人の名前と、相手が使った敬称がわかる
    const string Opening = @"(?m)^[>\s　]*(?:[^\n]{0,30}[ 　])?(" + FamilyName + @")(?:[ 　]?(?:" + FamilyName + @"))?[ 　]?(様|さま|さん|殿)[、,]?[ \t　]*" + EndOfLine;
    /// 挨拶の後の名乗り（株式会社ABC の東海林です）
    const string Introduction = "(?:" + ExternalGreeting + "|" + InternalGreeting
        + @")[。．、！!\s　]*(?:[^。．\n、ごお][^。．\n]{0,29}?の)?([" + Han + @"]{2,4}|[" + Katakana + @"ー]{2,8})(?:です|でございます|と申します)[。．]";
    /// 行頭の名乗り（情報科学研究科　田中です。）。挨拶（こんにちは）より先に名乗るメールもある
    const string LineIntroduction = @"(?m)^[>\s　]*(?:[^。．\n、ごお][^。．\n、]{0,29}?(?:の|[ 　]))?([" + Han + @"]{2,4}|[" + Katakana + @"ー]{2,8})(?:です|でございます|と申します)[。．]";
    /// 宛先・CC の行の頭
    const string RecipientLine = @"^\s*(?:To|Cc|CC|Bcc|BCC|宛先)\s*[:：]";
    /// 書き出しの挨拶を置き換えるときの、挨拶の前（行頭の空白と、宛名）
    const string GreetingPrefix = @"(?m)^([ \t　]*(?:[^\n、,。]{1,16}(?:様|さん|さま|各位|殿)[、,　 ]*)?)(?:";

    const RegexOptions Options = RegexOptions.CultureInvariant;
    static readonly Regex EitherGreetingRegex = new(ExternalGreeting + "|" + InternalGreeting, Options);
    static readonly Regex InternalGreetingRegex = new(InternalGreeting, Options);
    static readonly Regex StartsWithGreetingRegex = new("^(?:" + ExternalGreeting + "|" + InternalGreeting + ")", Options);
    static readonly Regex SenderRegex = new(Sender, Options);
    static readonly Regex OpeningRegex = new(Opening, Options);
    static readonly Regex IntroductionRegex = new(Introduction, Options);
    static readonly Regex LineIntroductionRegex = new(LineIntroduction, Options);
    static readonly Regex RecipientLineRegex = new(RecipientLine, Options);
    static readonly Regex ReplaceInternalGreetingRegex = new(GreetingPrefix + InternalGreeting + ")", Options);
    static readonly Regex ReplaceExternalGreetingRegex = new(GreetingPrefix + ExternalGreeting + ")", Options);

    /// 画面の文字から返信先を読む。メールアプリは返信の引用を入力欄のカーソルより後や作成欄の下に、Gmail はスレッドを入力欄より前に出す。
    /// カーソルや入力欄より後ろの文字は先頭（いちばん新しいメール）を、入力欄より前の文字は最後（入力欄に近い、いちばん新しいメール）を先に見る。
    /// 姓名を分けるのに ScreenNameFixer.Reader を使う
    public static MailReplyContext? Context(SurroundingText s) => Context(s, ScreenNameFixer.Reader);

    public static MailReplyContext? Context(SurroundingText s, IJapaneseReader? reader)
    {
        var texts = new (string Text, bool NewestFirst)[] { (s.After, true), (s.ScreenAfter, true), (s.Screen, false) }
            .Where(t => t.Text.Length > 0).ToList();
        if (texts.Count == 0) return null;
        string[]? Find(Regex re)
        {
            foreach (var (text, newestFirst) in texts)
            {
                var found = AllMatches(re, text, newestFirst);
                if (found.Count > 0) return found[0];
            }
            return null;
        }

        bool? external = null;
        if (Find(EitherGreetingRegex) is { } greeting) external = !InternalGreetingRegex.IsMatch(greeting[0]);
        // 受信メールの宛名は、返信する人（自分）の名前。差出人の候補から外す
        var opening = Find(OpeningRegex);
        bool IsMe(string n) => opening is not null && (opening[1].StartsWith(n, StringComparison.Ordinal) || n.StartsWith(opening[1], StringComparison.Ordinal));
        var honorific = "様";
        if (opening is not null) honorific = opening[2] == "さん" ? "さん" : "様";
        else if (external == false) honorific = "さん";

        string? name = null, fullName = null;
        foreach (var (text, newestFirst) in texts)
        {
            foreach (var m in AllMatches(SenderRegex, text, newestFirst))
            {
                if (IsMe(m[2])) continue;
                // 宛先・CC の行は、自分かほかの受信者
                if (RecipientLineRegex.IsMatch(m[1])) continue;
                name = m[2];
                fullName = m[3].Length == 0 ? null : m[2] + m[3];
                break;
            }
            if (name is not null) break;
        }
        if (name is null)
        {
            foreach (var re in new[] { IntroductionRegex, LineIntroductionRegex })
            {
                if (Find(re) is not { } m) continue;
                var intro = m[1];
                if (IsMe(intro) || !texts.Any(t => Signs(t.Text, intro))) continue;
                name = intro;
                break;
            }
        }
        if (name is { } full && fullName is null && FamilyOf(full, reader) is { } family)
        {
            // 表示名が空白なしの姓名（東海林太郎）なら、姓だけを宛名に使う
            name = family;
            fullName = full;
        }
        if (name is null && external is null) return null;
        return new MailReplyContext { Name = name, FullName = fullName, Honorific = honorific, External = external };
    }

    /// 書き出しの挨拶と、相手の名前の敬称を直す。話していない内容は足さない
    public static string Adjust(string text, MailReplyContext context)
    {
        if (!text.Any(c => CharClasses.Of(c) == CharClass.Kana)) return text;
        var t = text;
        if (context.External is { } external)
            t = ReplaceGreeting(t, external ? ReplaceInternalGreetingRegex : ReplaceExternalGreetingRegex, external ? "お世話になっております" : "お疲れ様です");
        if (context.Honorific == "様" && context.Name is { } name)
        {
            // 社外の相手を「さん」と呼んだら「様」にする（「様」を「さん」には変えない）
            var names = new[] { context.FullName, name }.OfType<string>().Select(Regex.Escape);
            t = Regex.Replace(t, "(" + string.Join("|", names) + ")(?:さん|さま)", "${1}様", Options);
        }
        return t;
    }

    /// 頼まれて書いた下書き（Ask anything）を返信先に合わせる。挨拶で始まり宛名がなければ、宛名の行を足す
    public static string FinishDraft(string text, MailReplyContext context)
    {
        var t = Adjust(text, context);
        if (context.Addressee is not { } addressee || context.Name is not { } name || t.Contains(name, StringComparison.Ordinal)
            || !StartsWithGreetingRegex.IsMatch(t))
            return t;
        return addressee + "\n\n" + t;
    }

    /// 書き出し（最初の 3 行）の行頭か、同じ行の宛名の後ろにある挨拶を 1 つだけ置き換える
    static string ReplaceGreeting(string text, Regex pattern, string greeting)
    {
        var m = pattern.Match(text);
        if (!m.Success || CountNewlines(text.AsSpan(0, m.Index)) >= 3) return text;
        return string.Concat(text.AsSpan(0, m.Index), m.Groups[1].Value, greeting, text.AsSpan(m.Index + m.Length));
    }

    /// 改行の数（「\r\n」は 1 つ）
    static int CountNewlines(ReadOnlySpan<char> s)
    {
        int count = 0;
        for (int i = 0; i < s.Length; i++)
        {
            if (s[i] == '\r' && i + 1 < s.Length && s[i + 1] == '\n') i++;
            if (CharClasses.IsNewline(s[i])) count++;
        }
        return count;
    }

    /// 署名のように、名前で終わる行があるか（東海林 太郎・営業部 東海林）。名乗りに見えるだけの文（議事録です）を名前とみなさない
    static bool Signs(string text, string name) =>
        Regex.IsMatch(text, @"(?m)(?:^|[ 　])" + Regex.Escape(name) + @"(?:[ 　]?[" + Han + Hiragana + @"]{1,4})?[ \t　]*" + EndOfLine, Options);

    /// 空白のない姓名（東海林太郎）を、日本語解析で姓と名に分ける。分けられなければ null
    static string? FamilyOf(string full, IJapaneseReader? reader)
    {
        if (full.Length < 3 || !full.All(c => CharClasses.Of(c) == CharClass.Han)) return null;
        var tokens = ScreenNameFixer.Tokens(full, reader);
        return tokens.Count == 2 ? tokens[0].Surface : null;
    }

    /// マッチごとの文字列（0 番が全体、続けてグループ）。newestFirst が false なら後ろのマッチから並べる
    static List<string[]> AllMatches(Regex re, string text, bool newestFirst)
    {
        var found = re.Matches(text)
            .Select(m => Enumerable.Range(0, m.Groups.Count).Select(i => m.Groups[i].Success ? m.Groups[i].Value : "").ToArray())
            .ToList();
        if (!newestFirst) found.Reverse();
        return found;
    }
}
