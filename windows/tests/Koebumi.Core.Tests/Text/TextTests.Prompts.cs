using Koebumi.Core;

namespace Koebumi.Core.Tests;

// Mac 版の LogicTests.swift の TextTests のうち、プロンプトの処理を使うもの
public partial class TextTests
{
    [Fact]
    public void CleanOutputStripsWrappers()
    {
        Assert.Equal("Hello there", Prompts.CleanOutput("<think>x</think>\n\"Hello there\""));
        Assert.Equal("コード", Prompts.CleanOutput("```\nコード\n```"));
        Assert.Equal("{\"a\": 1}", Prompts.ExtractJSON("前置き {\"a\": 1} 後"));
    }

    [Fact]
    public void AskOutcomeValidation()
    {
        var withSel = new AskRequest { Query = "q", Selection = "x", SelectionEditable = true, HasFocusedTextField = true, AppName = "A" };
        var noSel = new AskRequest { Query = "q", Selection = null, SelectionEditable = false, HasFocusedTextField = true, AppName = "A" };
        Assert.Equal(new AskOutcome.Replace("y"), Prompts.Outcome("replace", "y", "", withSel));
        Assert.Equal(new AskOutcome.Answer("y"), Prompts.Outcome("replace", "y", "", noSel));
        Assert.Equal(new AskOutcome.Answer("d"), Prompts.Outcome("open_url", "d", "javascript:alert(1)", noSel));
        Assert.Equal(new AskOutcome.OpenURL(new Uri("https://example.com"), "d"), Prompts.Outcome("open_url", "d", "https://example.com", noSel));
    }

    [Fact]
    public void PolishPromptCarriesContext()
    {
        var r = new PolishRequest
        {
            Transcript = "えーと", Mode = Mode.Translate, SourceLanguages = ["ja-JP"], TargetLanguage = "en-US",
            AppName = "Slack", Category = AppCategory.Chat, StyleDescription = "casual", PersonalStyle = "short",
            Vocabulary = ["田中"], Corrections = [new Correction("a", "b")],
        };
        var u = Prompts.PolishUser(r);
        Assert.Contains("App: Slack (chat)", u);
        Assert.Contains("Target language: English (United States)", u);
        Assert.Contains("田中", u);
        Assert.Contains("<transcript>\nえーと\n</transcript>", u);
        Assert.Contains("Edits the user made to earlier outputs (follow these preferences): \"a\" → \"b\"", u);
        Assert.Contains("The user's personal writing style: short", u);
    }
}
