using Koebumi.Core;

namespace Koebumi.Core.Tests;

// Mac 版の MailTests.swift の EmailDraftTests
public class EmailDraftTests
{
    static AskRequest Request(AppCategory category, MailReplyContext? reply = null) => new()
    {
        Query = "了解しましたと返信を書いて", Selection = null, SelectionEditable = false, HasFocusedTextField = true,
        AppName = "Mail", Vocabulary = [], Category = category, MailReply = reply,
    };

    [Fact]
    public void EmailAppsGetJapaneseEmailConventions()
    {
        Assert.DoesNotContain("お世話になっております", Prompts.AskUser(Request(AppCategory.Chat)));
        var u = Prompts.AskUser(Request(AppCategory.Email));
        Assert.Contains("お世話になっております。 for people outside the company", u);
        Assert.Contains("Do not write a signature", u);
        Assert.DoesNotContain("replying to", u);
    }

    [Fact]
    public void ReplyContextNamesTheRecipient()
    {
        var u = Prompts.AskUser(Request(AppCategory.Email, new MailReplyContext { Name = "佐藤", Honorific = "さん", External = false }));
        Assert.Contains("The user is replying to an email from 佐藤さん. The sender is a colleague, so open with お疲れ様です。", u);
    }

    // 以下は Windows 版で足したテスト

    [Fact]
    public void AskPromptListsSelectionVocabularyAndRequest()
    {
        var u = Prompts.AskUser(new AskRequest
        {
            Query = "短くして", Selection = "長い文章", SelectionEditable = true, AppName = "Notes", Vocabulary = ["Claude Code", "田中"],
        });
        Assert.Equal(
            "App: Notes\nSelected text is editable: yes\n<selection>\n長い文章\n</selection>\nUser vocabulary (exact spellings): Claude Code, 田中\n<request>\n短くして\n</request>",
            u);
        Assert.Equal(
            "App: Notes\nNo text is selected. A text field is focused: no\n<request>\nq\n</request>",
            Prompts.AskUser(new AskRequest { Query = "q", AppName = "Notes" }));
    }
}
