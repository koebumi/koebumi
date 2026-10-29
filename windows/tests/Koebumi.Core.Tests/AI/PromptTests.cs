using Koebumi.Core;

namespace Koebumi.Core.Tests;

// Mac 版の TextCleanupTests.swift の PromptTests。LineBreakMergeTests は Apple の音声認識だけの処理なので移していない
public class PromptTests
{
    [Fact]
    public void DetectsSelfCorrections()
    {
        Assert.NotNull(Prompts.CorrectionHint("明日は9時集合ですけど、違う9時半に集合してください。"));
        Assert.NotNull(Prompts.CorrectionHint("ランチはカレーにしよう、やっぱりラーメンにしよう。"));
        Assert.NotNull(Prompts.CorrectionHint("金曜日に、あ、木曜日に提出します"));
        Assert.NotNull(Prompts.CorrectionHint("ship it Tuesday, no wait, Wednesday"));
        Assert.Null(Prompts.CorrectionHint("明日は晴れです"));
        Assert.Null(Prompts.CorrectionHint("あの人は意見が違う"));
        Assert.Null(Prompts.CorrectionHint("あ、そうだ、明日は休みです"));  // 文頭の「あ、」は感嘆
        Assert.NotNull(Prompts.CorrectionHint("会議は3時から、じゃなくて4時からに変更になりました。"));
        Assert.Null(Prompts.CorrectionHint("猫じゃなくて犬が好きです。"));  // 対比
        Assert.Null(Prompts.CorrectionHint("このラーメン、やっぱり美味しいね。"));
        Assert.Null(Prompts.CorrectionHint("いや、それは違うと思います。"));
        Assert.Null(Prompts.CorrectionHint("そうですね。いや、それは違うと思います。"));
        Assert.NotNull(Prompts.CorrectionHint("会議は3時からいや4時からに変更になりました。"));  // 認識で読点が消えた
        Assert.NotNull(Prompts.CorrectionHint("ランチはカレーにしよう。やっぱりラーメンにしよう。"));  // 認識で文が分かれた
        // 認識で「いや」が「に」になった・落ちた言い直し
        Assert.Equal("4時からでお願いします", Prompts.FindCorrection("明日の会議3時に4時からでお願いします。")?.After);
        Assert.Equal("4時からでお願いします", Prompts.FindCorrection("明日の会議3時4時からでお願いします。")?.After);
        Assert.Null(Prompts.FindCorrection("会議は3時から4時までです。"));  // 範囲
        Assert.Null(Prompts.FindCorrection("1日2日で終わります。"));  // 言い回し
        Assert.Null(Prompts.FindCorrection("10人に1人が持っています。"));  // 割合
        Assert.Null(Prompts.FindCorrection("5回に1回は失敗します。"));
        Assert.Null(Prompts.FindCorrection("プランは1000円、2000円、3000円の3種類です。"));  // 列挙
        Assert.Null(Prompts.FindCorrection("1回、2回と繰り返します。"));
        Assert.Null(Prompts.FindCorrection("3時に2時間ほど作業します。"));  // 後の数は「2時間」
        Assert.Null(Prompts.FindCorrection("3人で5人分の仕事をした。"));
        Assert.Equal("4時半からでお願いします", Prompts.FindCorrection("会議は3時に4時半からでお願いします。")?.After);
        Assert.Null(Prompts.FindCorrection("3時に、4時からの会議の資料を送ります。"));  // 後の時刻は「会議」にかかる
        // 数字だけが違う「じゃなくて」は言い直し
        Assert.Equal("4時からでお願いします", Prompts.FindCorrection("明日の会議は3時じゃなくて4時からでお願いします。")?.After);
        // 認識で「あ、いや」が「あいや」とつながった
        Assert.Equal("4時の会議があります", Prompts.FindCorrection("明日から3時の会議があり。あいや、4時の会議があります。")?.After);
        Assert.Equal("4時からです", Prompts.FindCorrection("明日のミーティングは3時からで、あいや4時からです。")?.After);
        var doubled = Prompts.FindCorrection("金額は50万円、あ、違う、55万円でお願いします。");
        Assert.Equal("金額は50万円", doubled?.Before);
        Assert.Equal("55万円でお願いします", doubled?.After);
    }

    [Fact]
    public void DetectsEnumerations()
    {
        Assert.NotNull(Prompts.ListHint("やることは3つあって、1つ目は資料作成、2つ目はメールの返信、3つ目は会議の準備です。"));
        Assert.NotNull(Prompts.ListHint("手順としては、まずアプリをインストールして、次にアカウントを作成して、最後に通知をオンにしてください。"));
        Assert.NotNull(Prompts.ListHint("we need first the budget second the timeline"));
        Assert.Null(Prompts.ListHint("At first I was worried, but I finally finished it"));
        Assert.Null(Prompts.ListHint("昨日は買い物に行って、それから映画を見た"));
        Assert.Null(Prompts.ListHint("まず結論から言うと、明日は休みです。"));
        Assert.Null(Prompts.ListHint("明日は晴れです"));
    }

    [Fact]
    public void SplitsLongTranscriptsAtSentences()
    {
        var text = string.Concat(Enumerable.Repeat("これはテストの文です。", 30));
        var parts = Prompts.Split(text, 100);
        Assert.Equal(4, parts.Count);
        Assert.All(parts, p => Assert.True(p.Text.Length <= 100 && p.Text.EndsWith('。')));
        Assert.Equal(text, string.Concat(parts.Select(p => p.Text + p.Separator)));
        Assert.Equal(["short"], Prompts.Split("short", 100).Select(p => p.Text));
        var lines = Prompts.Split("Hey Tom,\n\nThanks for the deck.\nBob", 100);
        Assert.Equal(["Hey Tom,", "Thanks for the deck.", "Bob"], lines.Select(p => p.Text));
        Assert.Equal(["\n\n", "\n", ""], lines.Select(p => p.Separator));
    }

    [Fact]
    public void TranslationPromptEndsWithTarget()
    {
        var r = new PolishRequest
        {
            Transcript = "こんにちは", Mode = Mode.Translate, SourceLanguages = ["ja-JP"], TargetLanguage = "en-US",
            AppName = "Slack", Category = AppCategory.Chat, StyleDescription = "casual",
        };
        Assert.EndsWith("Write it in English (United States).", Prompts.PolishUser(r));
    }

    [Fact]
    public void RewriteKeepsLanguageUnlessAsked()
    {
        Assert.True(Prompts.ChangesLanguage("明日行けないわ", "I cannot attend tomorrow.", "もっと丁寧にして"));
        Assert.False(Prompts.ChangesLanguage("明日の会議は中止です", "Tomorrow's meeting is canceled.", "これを英語にして"));
        Assert.False(Prompts.ChangesLanguage("明日行けないわ", "明日は伺えません。", "もっと丁寧にして"));
    }

    [Fact]
    public void CleanOutputStripsLabels()
    {
        Assert.Equal("Hello there", Prompts.CleanOutput("Output: Hello there"));
        Assert.Equal("こんにちは", Prompts.CleanOutput("出力：こんにちは"));
    }

    // 以下は Windows 版で足したテスト

    [Fact]
    public void TreatsKanjiNumeralsAsNumbersWhenComparingTheShape()
    {
        // Swift の Character.isNumber は漢数字も数とみなす
        Assert.Equal("四時からでお願いします", Prompts.FindCorrection("明日の会議は三時じゃなくて四時からでお願いします。")?.After);
    }

    [Fact]
    public void HintsNameTheMarkerAndBothParts()
    {
        Assert.Equal(
            "Note: the speaker said \"ランチはカレーにしよう\", then corrected it with \"やっぱり\" to \"ラーメンにしよう\". Use only the corrected version, and drop the words it replaces.",
            Prompts.CorrectionHint("ランチはカレーにしよう、やっぱりラーメンにしよう。"));
        var dropped = Prompts.CorrectionHint("明日の会議3時に4時からでお願いします。");
        Assert.NotNull(dropped);
        Assert.StartsWith("Note: in \"", dropped);
        Assert.EndsWith("Never invent words the speaker did not say, such as まで.", dropped);
    }

    [Fact]
    public void SystemPromptsEndWithTheOutputInstruction()
    {
        Assert.StartsWith(Prompts.PolishRules + "\n\nExamples:\n<example>\n<transcript>\nえーと、明日の会議なんですけど", Prompts.PolishSystem);
        Assert.EndsWith("</example>\n\nOutput only the final text, with no preamble, quotes or explanation.", Prompts.PolishSystem);
        Assert.Contains("<example target=\"English (United States)\">", Prompts.TranslateSystem);
        Assert.Contains("<example vocabulary=\"GitHub, Notion\">", Prompts.PolishSystem);
        Assert.EndsWith("Output only the translated text, with no preamble, quotes, notes or the original.", Prompts.TranslateSystem);
        Assert.StartsWith(Prompts.StyleRules + "\n\nRespond with a JSON object only:\n", Prompts.StyleSystem);
        Assert.Contains("\"categories\"", Prompts.StyleSystem);
        Assert.StartsWith(Prompts.AskSystemCommon + "\n\nRespond with a JSON object only,", Prompts.AskSystemJSON);
    }

    [Fact]
    public void ExamplesFollowTheSpokenLanguage()
    {
        PolishRequest Request(string language, Mode mode = Mode.Dictate) => new() { SourceLanguages = [language], Mode = mode, TargetLanguage = "en-US" };
        Assert.All(Prompts.Examples(Request("ja-JP")), e => Assert.Equal("ja-JP", e.Language));
        Assert.All(Prompts.Examples(Request("en-GB")), e => Assert.Equal("en-US", e.Language));
        // 例のない言語は英語の例
        Assert.All(Prompts.Examples(Request("fr-FR")), e => Assert.StartsWith("en", e.Language));
        Assert.Equal(Prompts.TranslationExamples, Prompts.Examples(Request("ja-JP", Mode.Translate)));
    }

    [Fact]
    public void SmallModelUserAddsHintsOnlyWhenNeeded()
    {
        var plain = new PolishRequest { Transcript = "明日は晴れです", SourceLanguages = ["ja-JP"] };
        Assert.Equal(Prompts.PolishUser(plain), Prompts.SmallModelUser(plain));
        var corrected = plain with { Transcript = "ランチはカレーにしよう、やっぱりラーメンにしよう。" };
        Assert.EndsWith(Prompts.CorrectionHint(corrected.Transcript)!, Prompts.SmallModelUser(corrected));
        var list = plain with { Transcript = "手順は、まず電源を切って、次にケーブルを抜いてください。" };
        Assert.EndsWith(Prompts.ListHint(list.Transcript)!, Prompts.SmallModelUser(list));
        // 翻訳には箇条書きの指摘を足さない
        Assert.DoesNotContain("enumerates", Prompts.SmallModelUser(list with { Mode = Mode.Translate, TargetLanguage = "en-US" }));
    }

    [Fact]
    public void VocabularyShowsMisheardAliases()
    {
        var r = new PolishRequest
        {
            Transcript = "x", SourceLanguages = ["ja-JP"], Vocabulary = ["Claude Code", "Notion"],
            AliasHints = new Dictionary<string, string> { ["クロード・コード"] = "Claude Code", ["クロードコード"] = "Claude Code" },
        };
        Assert.Contains("Vocabulary (exact spellings): Claude Code (may be misheard as クロードコード / クロード・コード), Notion", Prompts.PolishUser(r));
    }

    [Fact]
    public void StripsThinkingAndExtractsJson()
    {
        Assert.Equal("答え", Prompts.StripThinking("<think>考え中</think>\n答え\n"));
        Assert.Equal("<think>終わらない", Prompts.StripThinking("<think>終わらない"));
        Assert.Equal("{\"a\": {\"b\": 1}}", Prompts.ExtractJSON("```json\n{\"a\": {\"b\": 1}}\n```"));
        Assert.Equal("no json", Prompts.ExtractJSON("no json"));
    }

    [Fact]
    public void PromptsUseLfLineBreaks()
    {
        // ソースが CRLF でチェックアウトされても、モデルに渡す文に CR が混ざらないこと（.gitattributes で LF にそろえている）
        var texts = new[]
        {
            Prompts.PolishRules, Prompts.PolishSystem, Prompts.TranslateRules, Prompts.TranslateSystem, Prompts.AskSystemCommon,
            Prompts.AskSystemJSON, Prompts.AskSystemTools, Prompts.RewriteRules, Prompts.EmailDraftRules, Prompts.StyleRules, Prompts.StyleSystem,
        };
        Assert.All(texts, t => Assert.DoesNotContain('\r', t));
    }

    [Fact]
    public void OutcomeReadsJsonAnswers()
    {
        var withSelection = new AskRequest { Query = "q", Selection = "x", SelectionEditable = true, HasFocusedTextField = true, AppName = "A" };
        Assert.Equal(new AskOutcome.Replace("y"), Prompts.Outcome("```json\n{\"action\": \"replace\", \"text\": \" y \", \"url\": \"\"}\n```", withSelection));
        Assert.Equal(new AskOutcome.Answer("ただの文章"), Prompts.Outcome("ただの文章", withSelection));
        Assert.Equal(new AskOutcome.Answer("答え"), Prompts.Outcome("<think>x</think>答え", withSelection));
        // 説明の代わりに URL を書いてきたら説明なしにする
        var opened = Prompts.Outcome("{\"action\": \"OPEN_URL\", \"text\": \"https://example.com/a\", \"url\": \" https://example.com/a \"}", withSelection);
        Assert.Equal(new AskOutcome.OpenURL(new Uri("https://example.com/a"), ""), opened);
        Assert.Equal(new AskOutcome.Insert("本文"), Prompts.Outcome("insert", "本文", "", withSelection));
        Assert.Equal(new AskOutcome.Answer(""), Prompts.Outcome("insert", "  ", "", withSelection));
    }
}
