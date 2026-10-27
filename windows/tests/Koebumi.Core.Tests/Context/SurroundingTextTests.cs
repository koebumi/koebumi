using Koebumi.Core;

namespace Koebumi.Core.Tests;

// promptGetsOnlyTermsWhenAllowed は Prompts と Polisher の PolishRequest、businessPresetOverridesCategoryRegister は Prompts と StylePreset が必要なので、ここには移さない。
// privacyDecidesWhatIsShared と settingsDecodeNewKeys は設定（AppSettings）のテストなので、SettingsTests にある
public partial class SurroundingTextTests
{
    [Fact]
    public void ExtractsNamesAndTerms()
    {
        var s = new SurroundingText { Screen = "東海林さん、Speak の件です。佐藤部長にも共有します。The meeting uses Zoom and AWS. ミーティングは明日です。" };
        var terms = s.Terms;
        Assert.Contains("東海林", terms);
        Assert.Contains("佐藤", terms);
        Assert.Contains("Speak", terms);
        Assert.Contains("Zoom", terms);
        Assert.Contains("AWS", terms);
        Assert.Contains("ミーティング", terms);
        Assert.DoesNotContain("The", terms);
    }

    [Fact]
    public void ExtractsMultiWordTermsAndDisplayNames()
    {
        var terms = new SurroundingText { Screen = "渡邉 健太  10:42\nClaude Code 2.3 のリリースノートです。The release is out." }.Terms;
        Assert.Contains("渡邉", terms);
        Assert.Contains("健太", terms);
        Assert.Contains("Claude Code", terms);
        Assert.DoesNotContain("The release", terms);
        Assert.DoesNotContain("Claude", terms);
        Assert.DoesNotContain("From", new SurroundingText { Screen = "From: 東海林 太郎" }.Terms);
    }

    // Windows の改行（CRLF）でも、チャットの表示名の姓と名を拾う
    [Fact]
    public void ExtractsDisplayNamesAcrossCrlf()
    {
        var terms = new SurroundingText { Screen = "渡邉 健太\r\n10:42\r\nお疲れ様です" }.Terms;
        Assert.Contains("渡邉", terms);
        Assert.Contains("健太", terms);
    }

    [Fact]
    public void JoinsAllPartsAndStopsAtTheLimit()
    {
        var s = new SurroundingText { Before = "東海林さん", After = "Slack", Screen = "佐藤様", ScreenAfter = "Zoom" };
        Assert.Equal(4, s.Terms.Count);
        foreach (var term in new[] { "東海林", "佐藤", "Slack", "Zoom" }) Assert.Contains(term, s.Terms);
        Assert.Equal(2, SurroundingTerms.Extract("東海林さん 佐藤様 田中先生", limit: 2).Count);
    }
}
