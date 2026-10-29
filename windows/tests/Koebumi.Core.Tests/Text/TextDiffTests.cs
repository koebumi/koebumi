using Koebumi.Core;

namespace Koebumi.Core.Tests;

public class TextDiffTests
{
    [Fact]
    public void ShowsRemovedAndAddedText()
    {
        var d = TextDiff.Segments(from: "資料を送ります。", to: "資料をお送りします。");
        Assert.Equal(new TextDiff.Segment(TextDiff.Kind.Same, "資料を"), d[0]);
        Assert.Contains(new TextDiff.Segment(TextDiff.Kind.Added, "お"), d);
        // 消した部分と同じ部分をつなげると元の文、足した部分と同じ部分をつなげると新しい文になる
        var old = string.Concat(d.Where(s => s.Kind != TextDiff.Kind.Added).Select(s => s.Text));
        var @new = string.Concat(d.Where(s => s.Kind != TextDiff.Kind.Removed).Select(s => s.Text));
        Assert.Equal("資料を送ります。", old);
        Assert.Equal("資料をお送りします。", @new);
    }

    [Fact]
    public void MergesSingleCharactersLeftBetweenRewrites()
    {
        var d = TextDiff.Segments(from: "お客様が言ってた資料、見ました。", to: "お客様がおっしゃっていた資料を拝見しました。");
        Assert.Equal("お客様が言ってた資料、見ました。", string.Concat(d.Where(s => s.Kind != TextDiff.Kind.Added).Select(s => s.Text)));
        Assert.Equal("お客様がおっしゃっていた資料を拝見しました。", string.Concat(d.Where(s => s.Kind != TextDiff.Kind.Removed).Select(s => s.Text)));
        // 1 文字だけの同じ部分を、変更の間に残さない
        for (int i = 1; i < d.Count - 1; i++)
        {
            if (d[i].Kind == TextDiff.Kind.Same) Assert.True(d[i].Text.Length > 1);
        }
    }

    [Fact]
    public void IdenticalTextIsOneSegment()
    {
        Assert.Equal([new TextDiff.Segment(TextDiff.Kind.Same, "同じです。")], TextDiff.Segments(from: "同じです。", to: "同じです。"));
        Assert.Equal([new TextDiff.Segment(TextDiff.Kind.Added, "足した")], TextDiff.Segments(from: "", to: "足した"));
    }
}
