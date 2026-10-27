using System.Text.Json;
using Koebumi.Core;

namespace Koebumi.Core.Tests;

public class SnippetTests
{
    static readonly FakeJapaneseReader Reader = new();

    static readonly Snippet Signature = new() { Trigger = "署名", Text = "--\n矢野 浩介\n株式会社ABC" };
    static readonly Snippet Opening = new() { Trigger = "書き出し", Text = "{宛名}\n\n{挨拶}\n矢野です。" };
    static readonly Snippet Closing = new() { Trigger = "結び", Text = "引き続きよろしくお願いいたします。" };
    static readonly Snippet[] All = [Signature, Opening, Closing];

    static SnippetExpander.Parts Split(string transcript, IReadOnlyList<Snippet>? snippets = null) =>
        SnippetExpander.Split(transcript, snippets ?? All, Reader);

    [Fact]
    public void ExpandsTriggersSpokenAsTheirOwnSentence()
    {
        var p = Split("資料をお送りします。署名");
        Assert.Equal("資料をお送りします。", p.Body);
        Assert.Equal([Signature], p.Trailing);
        Assert.Empty(p.Leading);

        var both = Split("書き出し、資料をお送りします、結び 署名");
        Assert.Equal([Opening], both.Leading);
        Assert.Equal("資料をお送りします", both.Body);
        Assert.Equal([Closing, Signature], both.Trailing);

        var only = Split("署名。");
        Assert.Empty(only.Body);
        Assert.Equal([Signature], only.Trailing);
    }

    [Fact]
    public void MatchesByReading()
    {
        Assert.Equal([Signature], Split("以上です。しょめい").Trailing);
        Assert.Equal([Signature], Split("ショメイ").Trailing);
        Assert.Equal("thanks.", Split("thanks. My Signature", [new Snippet { Trigger = "my signature", Text = "Yano" }]).Body);
    }

    [Fact]
    public void LeavesTriggerWordsInsideSentences()
    {
        Assert.Equal(new SnippetExpander.Parts { Body = "署名をお願いします" }, Split("署名をお願いします"));
        Assert.Equal(new SnippetExpander.Parts { Body = "契約書の署名" }, Split("契約書の署名"));
        Assert.Equal(new SnippetExpander.Parts { Body = "電子署名" }, Split("電子署名"));
        // 音声認識が句点を付けなくても、丁寧語の文末の後なら呼び出す
        var joined = Split("よろしくお願いします署名");
        Assert.Equal("よろしくお願いします", joined.Body);
        Assert.Equal([Signature], joined.Trailing);
        Assert.Equal(new SnippetExpander.Parts { Body = "署名" }, Split("署名", []));
        // 本文が空の定型文は使わない
        Assert.Empty(Split("署名", [new Snippet { Trigger = "署名", Text = " " }]).Trailing);
    }

    [Fact]
    public void FillsInTheReplyPlaceholders()
    {
        var reply = new MailReplyContext { Name = "東海林", External = true };
        Assert.Equal("東海林様\n\nお世話になっております。\n矢野です。", SnippetExpander.Render(Opening, reply));
        // 宛名がわからなければ、宛名の行と続く空行を書かない
        Assert.Equal("お世話になっております。\n矢野です。", SnippetExpander.Render(Opening, null));
        var colleague = new MailReplyContext { Name = "佐藤", Honorific = "さん", External = false };
        Assert.Equal("佐藤さん\n\nお疲れ様です。\n矢野です。", SnippetExpander.Render(Opening, colleague));
    }

    [Fact]
    public void JoinsSnippetsAsParagraphs()
    {
        var p = Split("書き出し。資料をお送りします。署名");
        Assert.Equal("お世話になっております。\n矢野です。\n\n資料をお送りします。\n\n--\n矢野 浩介\n株式会社ABC",
            SnippetExpander.Join(p, body: "資料をお送りします。", reply: null));
        Assert.Equal("\n\n", SnippetExpander.LeadingBreak(Split("署名"), before: "よろしくお願いいたします。"));
        Assert.Equal("", SnippetExpander.LeadingBreak(Split("署名"), before: "よろしくお願いいたします。\n"));
        Assert.Equal("", SnippetExpander.LeadingBreak(Split("本文です。署名"), before: "前の文。"));
    }

    [Fact]
    public void BodyIsPolishedNextToTheSnippetsNotTheCursor()
    {
        var p = Split("書き出し。資料を送ります。署名");
        var s = SnippetExpander.Surrounding(new SurroundingText { Before = "東海林様\n", After = "以上", Screen = "画面" }, around: p, reply: null);
        Assert.Equal("お世話になっております。\n矢野です。\n\n", s?.Before);
        Assert.Equal("\n\n--\n矢野 浩介\n株式会社ABC", s?.After);
        Assert.Equal("画面", s?.Screen);
    }

    // Mac 版の settingsKeepSnippetsAndNewShortcut。Mac 版の revertLastShortcuts は ⌘⌥Z、Windows 版は Ctrl+Alt+Z
    [Fact]
    public void SettingsKeepSnippetsAndNewShortcut()
    {
        var s = new AppSettings();
        Assert.Equal([Shortcut.CtrlAltZ], s.RevertLastShortcuts);
        Assert.True(s.MailReplyStyle);
        s.Snippets = [Signature];
        var decoded = JsonSerializer.Deserialize<AppSettings>(JsonSerializer.Serialize(s, Storage.Json), Storage.Json)!;
        Assert.Equal([Signature], decoded.Snippets);
        var old = JsonSerializer.Deserialize<AppSettings>("""{"llmProvider": "claude"}""", Storage.Json)!;
        Assert.Empty(old.Snippets);
        Assert.Equal([Shortcut.CtrlAltZ], old.RevertLastShortcuts);
    }

    // 以下は Windows 版で足したテスト

    [Fact]
    public void NeedsNoReaderToMatchTheSameSpelling()
    {
        // 読みの実装がなくても、表記が同じ（カタカナ・ひらがな・大文字小文字の違いを除く）なら呼び出せる
        var p = SnippetExpander.Split("お願いします。ショメイ", [new Snippet { Trigger = "しょめい", Text = "矢野" }], null);
        Assert.Equal("お願いします。", p.Body);
        Assert.Single(p.Trailing);
        Assert.False(SnippetExpander.Matches("署名", "しょめい", null));
        Assert.True(SnippetExpander.Matches("署名", "しょめい", Reader));
    }

    [Fact]
    public void KeepsSurrogatePairsWhole()
    {
        var p = Split("𠮷野さんへ👍。署名");
        Assert.Equal("𠮷野さんへ👍。", p.Body);
        Assert.Equal([Signature], p.Trailing);
    }
}
