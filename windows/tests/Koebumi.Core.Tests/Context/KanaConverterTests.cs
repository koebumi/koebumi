using Koebumi.Core;

namespace Koebumi.Core.Tests;

// Windows 版で足したテスト。Mac 版は macOS の変換を使うので、対応するテストはない
public class KanaConverterTests
{
    [Theory]
    [InlineData("あいうえお", "aiueo")]
    [InlineData("しょうじ", "shouji")]
    [InlineData("きょうゆう", "kyouyuu")]
    [InlineData("じゅうしょ", "juusho")]
    [InlineData("ちゃ", "cha")]
    [InlineData("わたなべ", "watanabe")]
    [InlineData("ぎゃく", "gyaku")]
    [InlineData("がっこう", "gakkou")]
    [InlineData("まっちゃ", "matcha")]
    [InlineData("ちょっと", "chotto")]
    [InlineData("あっ", "a")]
    [InlineData("しんいち", "shinichi")]
    [InlineData("ファイル", "fairu")]
    [InlineData("ティー", "tii")]
    [InlineData("ウィキ", "wiki")]
    [InlineData("ヴァイオリン", "vaiorin")]
    [InlineData("コーヒー", "koohii")]
    [InlineData("ｼｮｳｼﾞ", "shouji")]
    [InlineData("Shojiさん", "Shojisan")]
    [InlineData("東海林です", "東海林desu")]
    [InlineData("", "")]
    public void ConvertsKanaToHepburnRomaji(string kana, string romaji)
    {
        Assert.Equal(romaji, KanaConverter.ToRomaji(kana));
    }

    [Fact]
    public void ConvertsBetweenHiraganaAndKatakana()
    {
        Assert.Equal("しょめい", KanaConverter.ToHiragana("ショメイ"));
        Assert.Equal("ショメイ", KanaConverter.ToKatakana("しょめい"));
        // 長音符と、かな以外はそのまま
        Assert.Equal("こーひー Coffee 珈琲", KanaConverter.ToHiragana("コーヒー Coffee 珈琲"));
        Assert.Equal("コーヒー Coffee 珈琲", KanaConverter.ToKatakana("こーひー Coffee 珈琲"));
        Assert.Equal("ゔ", KanaConverter.ToHiragana("ヴ"));
    }
}
