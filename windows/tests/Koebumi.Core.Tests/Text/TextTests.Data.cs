using Koebumi.Core;

namespace Koebumi.Core.Tests;

// Mac 版の LogicTests.swift の TextTests のうち、データ（Data/）の処理を使うもの
public partial class TextTests
{
    [Fact]
    public void WordCountHandlesJapanese()
    {
        Assert.Equal(3, StatsStore.WordCount("We ship today."));
        Assert.True(StatsStore.WordCount("明日は晴れです") >= 3);
    }

    // NLTokenizer のかわりの、文字の種類で区切る数え方（Mac 版とは完全には一致しない）
    [Fact]
    public void WordCountSplitsByScript()
    {
        Assert.Equal(4, StatsStore.WordCount("明日は晴れです"));  // 明日 / は / 晴 / れです
        Assert.Equal(0, StatsStore.WordCount(""));
        Assert.Equal(0, StatsStore.WordCount("  。、！？ ... --- ___ "));
        Assert.Equal(2, StatsStore.WordCount("don't stop"));
        Assert.Equal(3, StatsStore.WordCount("It’s U.S. time"));  // It’s / U.S / time
        Assert.Equal(1, StatsStore.WordCount("1,000"));
        Assert.Equal(1, StatsStore.WordCount("3.5"));
        Assert.Equal(2, StatsStore.WordCount("well-known"));
        Assert.Equal(1, StatsStore.WordCount("snake_case"));
        Assert.Equal(3, StatsStore.WordCount("Ghosttyで入力"));  // Ghostty / で / 入力
        Assert.Equal(1, StatsStore.WordCount("クロードコード"));
        Assert.Equal(1, StatsStore.WordCount("ほーむ"));  // 長音はひらがなの中でも切れない
        Assert.Equal(4, StatsStore.WordCount("ありがとうございます"));  // ひらがなは 3 文字で 1 語（切り上げ）
        Assert.Equal(3, StatsStore.WordCount("音声認識結果"));  // 漢字は 2 文字で 1 語
        Assert.Equal(2, StatsStore.WordCount("🙂 hello 🙂 world"));  // 絵文字は数えない
        Assert.Equal(1, StatsStore.WordCount("𠮷"));
        Assert.Equal(1, StatsStore.WordCount("caf" + (char)0xE9));
        Assert.Equal(1, StatsStore.WordCount("cafe" + (char)0x301));  // e + 結合文字
    }

    [Fact]
    public void CsvParsing()
    {
        var csv = "term,source\nSpeak,manual\n\"Foo, Inc.\",manual\n田中\n\n";
        Assert.Equal(["Speak", "Foo, Inc.", "田中"], DictionaryStore.ParseCsv(csv));
    }
}
