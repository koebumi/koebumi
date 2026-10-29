using Koebumi.Core;

namespace Koebumi.Core.Tests;

// readsOldSetting と defaultsToNoPunctuationOnlyForNewUsers は設定（AppSettings）の読み込みのテストなので、ここには移さない
public class ChatPunctuationTests
{
    /// 入力する直前の処理（日本語の表記ルール → チャットの句読点）を通す。
    /// Mac 版は Polisher.fit を通すが、Polisher は別の部分なので、fit のうちこの 2 つの処理だけを同じ順で呼ぶ
    /// （語彙・画面の文脈・メールの返信先がないときの fit と同じ結果になる）
    static string Fit(string text, ChatPunctuation rule, AppCategory category = AppCategory.Chat, Mode mode = Mode.Dictate,
        Action<JapaneseNotation>? configure = null)
    {
        var n = new JapaneseNotation();
        configure?.Invoke(n);
        var t = JapaneseFormatter.Apply(text, n);
        if (category == AppCategory.Chat)
        {
            t = (mode == Mode.Translate ? rule.ForTranslation : rule).Apply(t);
        }
        return t;
    }

    [Fact]
    public void KeepsCommasInTranslations()
    {
        // 翻訳した文は読み手の言語の書き方にする。中国語は読点を消すと文が切れ目なくつながる
        var chinese = "明天的会议我可能会晚一点到，你们能先开始吗？";
        Assert.Equal(chinese, Fit(chinese, ChatPunctuation.NoPunctuation, mode: Mode.Translate));
        Assert.Equal("辛苦了。我们已经确认过了，没有问题", Fit("辛苦了。我们已经确认过了，没有问题。", ChatPunctuation.NoPunctuation, mode: Mode.Translate));
        Assert.Equal("Sure, sounds good. See you tomorrow", Fit("Sure, sounds good. See you tomorrow.", ChatPunctuation.NoPunctuation, mode: Mode.Translate));
        Assert.Equal("好的，没问题", Fit("好的，没问题。", ChatPunctuation.NoFinalPeriod, mode: Mode.Translate));
        Assert.Equal("好的，没问题。", Fit("好的，没问题。", ChatPunctuation.Keep, mode: Mode.Translate));
        Assert.Equal("好的，没问题。", Fit("好的，没问题。", ChatPunctuation.NoPunctuation, category: AppCategory.Email, mode: Mode.Translate));
    }

    [Fact]
    public void OmitsFinalPeriodInJapanese()
    {
        var text = "了解です。\n明日やります。";
        Assert.Equal("了解です\n明日やります", Fit(text, ChatPunctuation.NoFinalPeriod));
        Assert.Equal(text, Fit(text, ChatPunctuation.NoFinalPeriod, category: AppCategory.Email));
        Assert.Equal("了解です。", Fit("了解です。", ChatPunctuation.Keep));
        Assert.Equal("了解です。明日でいいですか？", Fit("了解です。明日でいいですか。", ChatPunctuation.NoFinalPeriod));
        Assert.Equal("はい、了解です", Fit("はい、了解です。", ChatPunctuation.NoFinalPeriod));  // 「、」は残す
    }

    [Fact]
    public void OmitsCommasAndPeriodsInJapanese()
    {
        // 「、」は消し、文の切れ目の「。」は空白、行の終わりの「。」は消す
        Assert.Equal("はい了解です りんごみかんぶどうを買います", Fit("はい、了解です。りんご、みかん、ぶどうを買います。", ChatPunctuation.NoPunctuation));
        Assert.Equal("了解です\n明日やります", Fit("了解です。\n明日やります。", ChatPunctuation.NoPunctuation));
        Assert.Equal("了解です 明日でいいですか？", Fit("了解です。明日でいいですか。", ChatPunctuation.NoPunctuation));
        // 閉じかっこの前の「。」は空白にせず詰める
        Assert.Equal("「了解です」と伝えました", Fit("「了解です。」と伝えました。", ChatPunctuation.NoPunctuation));
        // 「，」「．」の書き方でも同じ
        Assert.Equal("はい了解です 明日行きます",
            Fit("はい、了解です。明日行きます。", ChatPunctuation.NoPunctuation, configure: n => n.Punctuation = JapanesePunctuation.CommaPeriod));
        Assert.Equal("はい、了解です。", Fit("はい、了解です。", ChatPunctuation.NoPunctuation, category: AppCategory.Email));
    }

    [Fact]
    public void WorksInEnglish()
    {
        var text = "Sure, sounds good. See you tomorrow.";
        Assert.Equal("Sure, sounds good. See you tomorrow", Fit(text, ChatPunctuation.NoFinalPeriod));
        Assert.Equal("Sure sounds good See you tomorrow", Fit(text, ChatPunctuation.NoPunctuation));
        Assert.Equal(text, Fit(text, ChatPunctuation.NoPunctuation, category: AppCategory.Email));
        Assert.Equal("Thanks!\nSee you", Fit("Thanks!\nSee you.", ChatPunctuation.NoFinalPeriod));
        Assert.Equal("Is that okay?", Fit("Is that okay?", ChatPunctuation.NoPunctuation));
        // 閉じ引用符・閉じかっこの前の句点も消す
        Assert.Equal("He said \"sounds good\" Then he left", Fit("He said \"sounds good.\" Then he left.", ChatPunctuation.NoPunctuation));
        Assert.Equal("(I think so)", Fit("(I think so.)", ChatPunctuation.NoFinalPeriod));
    }

    [Fact]
    public void KeepsNumbersAbbreviationsAndEllipses()
    {
        Assert.Equal("It costs $1,000.50 right? Let's meet at 3 p.m. tomorrow",
            Fit("It costs $1,000.50, right? Let's meet at 3 p.m. tomorrow.", ChatPunctuation.NoPunctuation));
        Assert.Equal("See you at 5 p.m.", Fit("See you at 5 p.m.", ChatPunctuation.NoPunctuation));
        Assert.Equal("Fruit e.g. apples oranges", Fit("Fruit, e.g. apples, oranges.", ChatPunctuation.NoPunctuation));
        Assert.Equal("Well... maybe", Fit("Well... maybe.", ChatPunctuation.NoPunctuation));
        Assert.Equal("Check example.com and v2.5", Fit("Check example.com and v2.5.", ChatPunctuation.NoPunctuation));
        // 箇条書きの番号の「.」は残す
        Assert.Equal("やることは2つあります\n1. 資料作成\n2. 返信", Fit("やることは2つあります。\n1. 資料作成\n2. 返信", ChatPunctuation.NoPunctuation));
        Assert.Equal("Two things:\n  1. Budget\n  2. Timeline", Fit("Two things:\n  1. Budget.\n  2. Timeline.", ChatPunctuation.NoPunctuation));
        // 全角の小数点が「。」にならない
        Assert.Equal("3.5ギガです", Fit("3.5ギガです。", ChatPunctuation.NoPunctuation));
    }

    [Fact]
    public void WorksInOtherLanguages()
    {
        // 中国語は日本語と同じく、「，」「、」を消し、文の切れ目の「。」を空白にする
        Assert.Equal("好的，没问题。我明天早上发给你", Fit("好的，没问题。我明天早上发给你。", ChatPunctuation.NoFinalPeriod));
        Assert.Equal("好的没问题 我明天早上发给你", Fit("好的，没问题。我明天早上发给你。", ChatPunctuation.NoPunctuation));
        Assert.Equal("你好吗？", Fit("你好吗？", ChatPunctuation.NoPunctuation));
        Assert.Equal("네 알겠습니다 내일 아침에 보낼게요", Fit("네, 알겠습니다. 내일 아침에 보낼게요.", ChatPunctuation.NoPunctuation));
        Assert.Equal("¿Vienes mañana? Sí claro", Fit("¿Vienes mañana? Sí, claro.", ChatPunctuation.NoPunctuation));
        Assert.Equal("Ja klar Bis morgen", Fit("Ja, klar. Bis morgen.", ChatPunctuation.NoPunctuation));
        Assert.Equal("نعم سأرسله غدًا", Fit("نعم، سأرسله غدًا.", ChatPunctuation.NoPunctuation));
        Assert.Equal("हाँ ठीक है कल भेज दूँगा", Fit("हाँ, ठीक है। कल भेज दूँगा।", ChatPunctuation.NoPunctuation));
        // 日本語の中の英語
        Assert.Equal("了解です Thanks see you", Fit("了解です。Thanks, see you.", ChatPunctuation.NoPunctuation));
    }
}
