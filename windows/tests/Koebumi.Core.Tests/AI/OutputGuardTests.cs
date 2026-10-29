using Koebumi.Core;

namespace Koebumi.Core.Tests;

// Mac 版の TextCleanupTests.swift の OutputGuardTests と TranslationCheckTests
public class OutputGuardTests
{
    static readonly FakeJapaneseReader Reader = new();

    [Fact]
    public void AcceptsNormalCleanup()
    {
        Assert.True(OutputGuard.Accepts("えーと、明日の会議なんですけど、あのー、資料を準備しておいてください。", "明日の会議なんですけど、資料を準備しておいてください。"));
        Assert.True(OutputGuard.Accepts("明日は田中さんと、いや、違う、佐藤さんと、いや、やっぱり田中さんと打ち合わせです", "明日は田中さんと打ち合わせです。"));
        Assert.True(OutputGuard.Accepts("やることは3つあって、1つ目は資料作成、2つ目はメールの返信、3つ目は会議の準備です。",
            "やることは3つあります。\n1. 資料作成\n2. メールの返信\n3. 会議の準備"));
        Assert.True(OutputGuard.Accepts("um so let's ship it on Tuesday, no wait, Wednesday", "Let's ship it on Wednesday."));
        Assert.True(OutputGuard.Accepts("クロードコードを開いて", "Claude Codeを開いて。", ["Claude Code"]));
        Assert.True(OutputGuard.Accepts("はい", "はい。"));
        Assert.True(OutputGuard.Accepts("今何時", "今何時？"));
    }

    [Fact]
    public void RejectsAnswersAndRefusals()
    {
        Assert.False(OutputGuard.Accepts("自己紹介してください。", "こんにちは！私はAIアシスタントです。文章の作成や質問への回答など、さまざまなお手伝いができます。"));
        Assert.False(OutputGuard.Accepts("日本の首都はどこですか", "東京です。"));
        Assert.False(OutputGuard.Accepts("write me a poem about the ocean", "I'm sorry, but I can't help with that."));
        Assert.False(OutputGuard.Accepts("今週の振り返りです。月曜日はクライアントと打ち合わせをして、火曜日と水曜日は実装を進めました。", "振り返り。"));
        Assert.False(OutputGuard.Accepts("明日は晴れです", ""));
    }

    [Fact]
    public void ChecksCorrectedPartIsKept()
    {
        const string source = "明日は9時集合ですけど、違う9時半に集合してください。";
        Assert.True(OutputGuard.KeepsCorrection(source, "明日は9時半に集合してください。"));
        Assert.False(OutputGuard.KeepsCorrection(source, "明日は9時集合です。"));
        Assert.True(OutputGuard.KeepsCorrection("明日は晴れです", "明日は晴れです。"));
    }

    [Fact]
    public void KeepsTheNamesThatWereSpoken()
    {
        // 画面に出ている別の人の名前に書き換えた
        Assert.False(OutputGuard.KeepsNames("しょうじさんにも共有しておきます", "矢野さんにも共有しておきます。", [], Reader));
        // 同じ読みの表記に直すのは正しい
        Assert.True(OutputGuard.KeepsNames("しょうじさんにも共有しておきます", "東海林さんにも共有しておきます。", [], Reader));
        Assert.True(OutputGuard.KeepsNames("渡辺さんに共有しておきます", "渡邉さんに共有しておきます。", [], Reader));
        Assert.True(OutputGuard.KeepsNames("社長が言ってた件", "社長がおっしゃっていた件", [], Reader));
        // 辞書の語は、読みが違っても正しい
        Assert.True(OutputGuard.KeepsNames("棚香さんに送ります", "田中さんに送ります。", ["田中"], Reader));
    }

    [Fact]
    public void KeepsParticlesAfterQuantities()
    {
        Assert.False(OutputGuard.KeepsQuantityParticles("明日は3時に4時からの会議の準備をします。", "明日は3時から4時からの会議の準備をします。"));
        Assert.False(OutputGuard.KeepsQuantityParticles("明日の会議3時に4時からでお願いします。", "明日の会議は3時から4時までお願いします。"));
        Assert.True(OutputGuard.KeepsQuantityParticles("明日の会議3時に4時からでお願いします。", "明日の会議4時からでお願いします。"));
        Assert.False(OutputGuard.KeepsQuantityParticles("3時に、4時からの会議の資料を送ります。", "3時、4時からの会議の資料を送ります。"));
        Assert.True(OutputGuard.KeepsQuantityParticles("予算は300万円で、納期は12月15日です。", "予算は300万円で、納期は12月15日です。"));
        // ビジネス敬語の「から → より」は意味が変わらない
        Assert.True(OutputGuard.KeepsQuantityParticles("明日3時から打ち合わせです", "明日3時より打ち合わせがございます。"));
    }

    [Fact]
    public void KeepsCasualRegister()
    {
        Assert.False(OutputGuard.KeepsRegister("答えが間違ってた", "答えが間違っていました。"));
        Assert.False(OutputGuard.KeepsRegister("明日の天気を教えて", "明日の天気を教えてください。"));
        Assert.True(OutputGuard.KeepsRegister("明日の天気を教えてください", "明日の天気を教えてください。"));
        Assert.True(OutputGuard.KeepsRegister("了解", "了解。"));
        Assert.True(OutputGuard.KeepsRegister("こっちの方がましだ", "こっちの方がましだ。"));
    }

    [Fact]
    public void KeepsCasualQuestionsCasual()
    {
        Assert.Equal("今何時？", OutputGuard.KeepingCasualQuestions("今何時", "今何時ですか？"));
        Assert.Equal("会議室はどこですか？", OutputGuard.KeepingCasualQuestions("会議室はどこですか", "会議室はどこですか？"));
    }

    // 以下は Windows 版で足したテスト

    [Fact]
    public void KeepsNamesCannotJudgeWithoutAReader()
    {
        // 読みの実装がなければ名前を見分けられないので、何も断らない
        Assert.True(OutputGuard.KeepsNames("しょうじさんに送ります", "矢野さんに送ります。", [], null));
    }

    [Fact]
    public void LettersAndOverlap()
    {
        Assert.Equal(["a", "b", "1", "あ", "𠮷"], OutputGuard.Letters("A, b! 1 あ。𠮷"));
        Assert.Equal(1.0, OutputGuard.Overlap(OutputGuard.Letters("abc"), OutputGuard.Letters("xabcx")));
        Assert.Equal(0.5, OutputGuard.Overlap(OutputGuard.Letters("abx"), OutputGuard.Letters("abc")));
        Assert.Equal(0.0, OutputGuard.Overlap(OutputGuard.Letters("a"), OutputGuard.Letters("b")));
        Assert.Equal(1.0, OutputGuard.Overlap(OutputGuard.Letters("a"), OutputGuard.Letters("A")));
    }
}

public class TranslationCheckTests
{
    [Fact]
    public void DetectsUntranslatedOutput()
    {
        Assert.False(Languages.IsWritten("明日の会議資料を送ってください", "ko-KR"));
        Assert.True(Languages.IsWritten("내일 회의 자료를 보내 주세요.", "ko-KR"));
        Assert.False(Languages.IsWritten("Please send me the slides", "ja-JP"));
        Assert.True(Languages.IsWritten("正午までにスライドを送ってください。", "ja-JP"));
        Assert.True(Languages.IsWritten("请把明天会议的资料发给我。", "zh-CN"));
        Assert.False(Languages.IsWritten("明日の会議の資料を送ってください", "zh-CN"));
        Assert.True(Languages.IsWritten("Mañana parece que va a llover.", "es-ES"));
        Assert.True(Languages.IsWritten("Could we use Claude Code?", "en-US"));
        Assert.False(Languages.IsWritten("明日は雨です", "en-US"));
    }
}
