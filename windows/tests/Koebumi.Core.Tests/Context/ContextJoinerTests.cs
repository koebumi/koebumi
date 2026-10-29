using Koebumi.Core;

namespace Koebumi.Core.Tests;

public class ContextJoinerTests
{
    [Fact]
    public void AddsSpacesBetweenEnglishWords()
    {
        Assert.Equal(" then restart the server.", ContextJoiner.Join("then restart the server.", before: "Check the logs,", after: ""));
        Assert.Equal("check the logs ", ContextJoiner.Join("check the logs", before: "", after: "and restart"));
        Assert.Equal("Hello.", ContextJoiner.Join("Hello.", before: "Hi. ", after: ""));
    }

    [Fact]
    public void FixesCapitalization()
    {
        Assert.Equal(" the server is down.", ContextJoiner.Join("The server is down.", before: "I think", after: ""));
        Assert.Equal(" Claude is great.", ContextJoiner.Join("Claude is great.", before: "I think", after: ""));
        Assert.Equal(" We ship today.", ContextJoiner.Join("we ship today.", before: "Done.", after: ""));
    }

    [Fact]
    public void AvoidsDoubledPunctuation()
    {
        Assert.Equal("晴れです", ContextJoiner.Join("晴れです。", before: "今日は", after: "。"));
        Assert.Equal("晴れですか", ContextJoiner.Join("晴れですか？", before: "今日は", after: "。"));
        Assert.Equal("それから", ContextJoiner.Join("、それから", before: "了解です。", after: ""));
        // 日本語の文の途中に差し込むときは句点を付けない
        Assert.Equal("明日の", ContextJoiner.Join("明日の", before: "会議は", after: "10時からです。"));
        Assert.Equal("田中さんと", ContextJoiner.Join("田中さんと。", before: "会議は", after: "話します"));
        // 文の頭に入れるなら句点は残す
        Assert.Equal("了解です。", ContextJoiner.Join("了解です。", before: "", after: "明日の件"));
        Assert.Equal("了解です。", ContextJoiner.Join("了解です。", before: "はい。", after: "明日の件"));
    }

    [Fact]
    public void DoesNotRepeatTheLineBeforeTheCursor()
    {
        Assert.Equal("見積書ありがとうございます。", ContextJoiner.Join("東海林様、見積書ありがとうございます。", before: "東海林様\n\n", after: ""));
        Assert.Equal("東海林様", ContextJoiner.Join("東海林様", before: "東海林様\n", after: ""));
        Assert.Equal("田中さん、了解です。", ContextJoiner.Join("田中さん、了解です。", before: "東海林様\n", after: ""));
    }

    [Fact]
    public void EmptyContextChangesNothing()
    {
        Assert.Equal("明日は晴れです。", ContextJoiner.Join("明日は晴れです。", before: "", after: ""));
        Assert.Equal("Hello there.", ContextJoiner.Join("Hello there.", before: "", after: ""));
    }

    // Windows の改行（CRLF）と、サロゲートペアの文字（Swift の Character と同じ 1 文字）
    [Fact]
    public void HandlesCrlfAndSurrogatePairs()
    {
        Assert.Equal("見積書ありがとうございます。", ContextJoiner.Join("東海林様、見積書ありがとうございます。", before: "東海林様\r\n\r\n", after: ""));
        Assert.Equal("そうだね", ContextJoiner.Join("そうだね", before: "👍", after: ""));
        Assert.Equal("𠮷野さん", ContextJoiner.Join("𠮷野さん", before: "", after: "👍"));
    }
}
