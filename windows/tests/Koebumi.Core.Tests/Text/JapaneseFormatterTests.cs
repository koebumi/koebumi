using Koebumi.Core;

namespace Koebumi.Core.Tests;

public class JapaneseFormatterTests
{
    static string Format(string text, Action<JapaneseNotation>? configure = null)
    {
        var n = new JapaneseNotation();
        configure?.Invoke(n);
        return JapaneseFormatter.Apply(text, n);
    }

    [Fact]
    public void OpensAuxiliaryVerbsAndFormalNouns()
    {
        Assert.Equal("資料を確認してください。", Format("資料を確認して下さい。"));
        Assert.Equal("ご確認ください。", Format("ご確認下さい。"));
        Assert.Equal("送っていただけますか？", Format("送って頂けますか。"));
        Assert.Equal("ご検討いただければ幸いです。", Format("ご検討頂ければ幸いです。"));
        Assert.Equal("よろしくお願いいたします。", Format("よろしくお願い致します。"));
        Assert.Equal("明日できることから進めます。", Format("明日出来ることから進めます。"));
        Assert.Equal("明日できることから進めます。", Format("明日出来る事から進めます。"));
        Assert.Equal("会議に出ることができません。", Format("会議に出る事ができません。"));
        Assert.Equal("困ったときは連絡してください。", Format("困った時は連絡してください。"));
        Assert.Equal("そのために準備します。", Format("その為に準備します。"));
        Assert.Equal("このように進めます。", Format("この様に進めます。"));
        Assert.Equal("よろしくお願いします。ありがとうございます。", Format("宜しくお願いします。有難うございます。"));
    }

    [Fact]
    public void KeepsContentWordsInKanji()
    {
        // 本来の意味の動詞・名詞は変えない
        Assert.Equal("資料を下さい。", Format("資料を下さい。"));
        Assert.Equal("意見が一致しました。", Format("意見が一致しました。"));
        Assert.Equal("大事な出来事です。", Format("大事な出来事です。"));
        Assert.Equal("上出来な結果でした。", Format("上出来な結果でした。"));
        Assert.Equal("不出来なところがあった。", Format("不出来なところがあった。"));
        Assert.Equal("3時に田中様に会います。", Format("3時に田中様に会います。"));
        Assert.Equal("同時に変更に取りかかります。", Format("同時に変更に取りかかります。"));
        Assert.Equal("行為の為替", Format("行為の為替"));
    }

    [Fact]
    public void HiraganaFormsCanBeTurnedOff()
    {
        Assert.Equal("確認して下さい。", Format("確認して下さい。", n => n.HiraganaForms = false));
    }

    [Fact]
    public void PunctuationStyles()
    {
        var text = "はい、承知しました。明日送ります。";
        Assert.Equal(text, Format(text));
        Assert.Equal("はい，承知しました。明日送ります。", Format(text, n => n.Punctuation = JapanesePunctuation.CommaMaru));
        Assert.Equal("はい，承知しました．明日送ります．", Format(text, n => n.Punctuation = JapanesePunctuation.CommaPeriod));
        Assert.Equal("はい、わかりました。", Format("はい，わかりました．"));
    }

    [Fact]
    public void LatinSpacing()
    {
        Assert.Equal("iPhoneをGPT-5で使う", Format("iPhone を GPT-5 で使う", n => n.LatinSpacing = Koebumi.Core.LatinSpacing.Remove));
        Assert.Equal("iPhone を GPT-5 で3時に使う", Format("iPhoneをGPT-5で3時に使う", n => n.LatinSpacing = Koebumi.Core.LatinSpacing.Insert));
        Assert.Equal("Node.js と C++ の5G 回線", Format("Node.jsとC++の5G回線", n => n.LatinSpacing = Koebumi.Core.LatinSpacing.Insert));
        Assert.Equal("iPhone を使う", Format("iPhone を使う"));  // 既定はそのまま
    }

    [Fact]
    public void EndsPoliteQuestionsWithQuestionMark()
    {
        Assert.Equal("会議室はどこですか？", Format("会議室はどこですか。"));
        Assert.Equal("資料を送っていただけますでしょうか？", Format("資料を送っていただけますでしょうか。"));
        Assert.Equal("一緒に行きませんか？明日なら空いています。", Format("一緒に行きませんか。明日なら空いています。"));
        Assert.Equal("もう終わりましたか？\n次に進みましょうか？", Format("もう終わりましたか\n次に進みましょうか"));
        Assert.Equal("どこですか？", Format("どこですか．", n => n.Punctuation = JapanesePunctuation.CommaPeriod));
        Assert.Equal("「大丈夫ですか？」と聞かれました。", Format("「大丈夫ですか。」と聞かれました。"));
    }

    [Fact]
    public void LeavesNonQuestionsAndCasualEndingsAlone()
    {
        // 独り言の「か」や、語尾で疑問とわからない文は変えない
        Assert.Equal("そうか。まあ、いいか。", Format("そうか。まあ、いいか。"));
        Assert.Equal("参加するかどうか。", Format("参加するかどうか。"));
        Assert.Equal("そうですかね。", Format("そうですかね。"));
        Assert.Equal("ですか、と聞かれました。", Format("ですか、と聞かれました。"));
        Assert.Equal("今何時。", Format("今何時。"));
        Assert.Equal("会議室はどこですか。", Format("会議室はどこですか。", n => n.QuestionMark = false));
    }

    [Fact]
    public void LeavesNonJapaneseAlone()
    {
        Assert.Equal("Please check it, thanks.", Format("Please check it, thanks.", n => n.Punctuation = JapanesePunctuation.CommaPeriod));
        Assert.Equal("我们明天见。", Format("我们明天见。", n => n.Punctuation = JapanesePunctuation.CommaPeriod));
    }

    [Fact]
    public void FixesDoubleHonorifics()
    {
        Assert.Equal("社長がおっしゃった件ですが、もうご覧になりましたか？", Format("社長がおっしゃられた件ですが、もうご覧になられましたか。"));
        Assert.Equal("先生がおっしゃる通りです。", Format("先生がおっしゃられる通りです。"));
        Assert.Equal("何時にお越しになりますか？", Format("何時にお越しになられますか。"));
        // 単独の敬語は変えない
        Assert.Equal("田中さんが部長になられたそうです。", Format("田中さんが部長になられたそうです。"));
    }
}
