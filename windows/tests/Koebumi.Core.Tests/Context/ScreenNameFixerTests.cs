using Koebumi.Core;

namespace Koebumi.Core.Tests;

public class ScreenNameFixerTests
{
    static readonly FakeJapaneseReader Reader = new();

    static string Fix(string text, string screen) => ScreenNameFixer.Apply(text, screen, Reader);

    [Fact]
    public void UsesScreenSpellingForSameReading()
    {
        Assert.Equal("渡邉さんに共有しておきます。", Fix("渡辺さんに共有しておきます。", "渡邉 健太  10:42\n明日のリリースの件"));
        Assert.Equal("東海林さん、見積書ありがとうございます。", Fix("しょうじさん、見積書ありがとうございます。", "From: 東海林 太郎\n東海林です。"));
        Assert.Equal("東海林さん、ありがとうございます。", Fix("Shojiさん、ありがとうございます。", "東海林です。"));
        // Apple の音声認識が出す同音の表記（庄司・渡辺）も直る
        Assert.Equal("東海林さん、見積書ありがとうございます。", Fix("庄司さん、見積書ありがとうございます。", "From: 東海林 太郎"));
        Assert.Equal("齋藤部長と髙橋様に送ります。", Fix("斎藤部長と高橋様に送ります。", "齋藤 / 髙橋"));
        Assert.Equal("渡邉健太さんへ", Fix("渡辺健太さんへ", "渡邉 健太"));
    }

    [Fact]
    public void LeavesAmbiguousOrUnrelatedNamesAlone()
    {
        // 同じ読みの名前が画面に 2 つ
        Assert.Equal("いとうさんに送ります。", Fix("いとうさんに送ります。", "伊藤さんと伊東さん"));
        // 元の表記も画面にある
        Assert.Equal("渡辺さんに送ります。", Fix("渡辺さんに送ります。", "渡辺さんと渡邉さん"));
        // 敬称が付いていない語は変えない（公園 → 講演 のような同音語は直さない）
        Assert.Equal("公園で会いましょう。", Fix("公園で会いましょう。", "講演の資料"));
        // 大野と小野は長音を詰めると同じになるが、日本語の読みは詰めない
        Assert.Equal("おおのさんに送ります。", Fix("おおのさんに送ります。", "小野です"));
        Assert.Equal("皆さんに共有します。", Fix("皆さんに共有します。", "美奈"));
    }

    // 以下は Windows 版で足したテスト（読みの実装を差し替える作りに合わせたもの）

    [Fact]
    public void ChangesNothingWithoutAReader()
    {
        Assert.Equal("渡辺さんに共有しておきます。", ScreenNameFixer.Apply("渡辺さんに共有しておきます。", "渡邉 健太", null));
        var tokens = ScreenNameFixer.Tokens("渡辺さん", null);
        Assert.Equal([new ScreenNameFixer.Token("渡辺さん", "", 0, 4)], tokens);
        Assert.Empty(ScreenNameFixer.Tokens("", null));
    }

    [Fact]
    public void UsesTheDefaultReaderOnlyWhenNoReaderIsGiven()
    {
        var saved = ScreenNameFixer.Reader;
        try
        {
            ScreenNameFixer.Reader = Reader;
            Assert.Equal("渡邉さんに共有しておきます。", ScreenNameFixer.Apply("渡辺さんに共有しておきます。", "渡邉 健太"));
            Assert.Equal("渡辺さんに共有しておきます。", ScreenNameFixer.Apply("渡辺さんに共有しておきます。", "渡邉 健太", null));
            ScreenNameFixer.Reader = null;
            Assert.Equal("渡辺さんに共有しておきます。", ScreenNameFixer.Apply("渡辺さんに共有しておきます。", "渡邉 健太"));
        }
        finally
        {
            ScreenNameFixer.Reader = saved;
        }
    }

    [Fact]
    public void TokensHaveRomajiReadingsAndPositions()
    {
        var tokens = ScreenNameFixer.Tokens("渡辺健太さん、Shojiです", Reader);
        Assert.Equal(
            [
                new ScreenNameFixer.Token("渡辺", "watanabe", 0, 2),
                new ScreenNameFixer.Token("健太", "kenta", 2, 2),
                new ScreenNameFixer.Token("さん", "san", 4, 2),
                new ScreenNameFixer.Token("Shoji", "Shoji", 7, 5),
                new ScreenNameFixer.Token("です", "desu", 12, 2),
            ],
            tokens);
        Assert.Equal(14, tokens[^1].End);
        Assert.Contains("さん", ScreenNameFixer.Honorifics);
        Assert.Contains("主任", ScreenNameFixer.Honorifics);
    }

    // 「庄司部長さん」の「庄司」は、「部長」の前としても「さん」の前の姓としても見つかる。長さの違う表記（庄司 → 東海林）でも 1 度だけ直す
    [Fact]
    public void FixesAWordOnlyOnceWhenTwoHonorificsFollow()
    {
        Assert.Equal("東海林部長さんへ", Fix("庄司部長さんへ", "東海林"));
    }
}
