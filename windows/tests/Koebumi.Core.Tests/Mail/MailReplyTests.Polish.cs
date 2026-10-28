using Koebumi.Core;

namespace Koebumi.Core.Tests;

// Mac 版の MailTests.swift の MailReplyTests.polishFixesNameHonorificAndGreetingWithoutAI
public partial class MailReplyTests
{
    [Fact]
    public async Task PolishFixesNameHonorificAndGreetingWithoutAI()
    {
        var r = new PolishRequest
        {
            Transcript = "しょうじさん、お疲れ様です。資料を送ります", Mode = Mode.Dictate, SourceLanguages = ["ja-JP"],
            AppName = "Mail", Category = AppCategory.Email, StyleDescription = "polite", Notation = new JapaneseNotation(),
            Surrounding = new SurroundingText { After = AppleMailQuote },
            MailReply = Read(new SurroundingText { After = AppleMailQuote }),
        };
        var output = await Polisher.Run(r, null, Reader);
        Assert.Equal("東海林様、お世話になっております。資料を送ります", output.Text);
        Assert.Equal(output.Text, output.Plain);
    }
}
