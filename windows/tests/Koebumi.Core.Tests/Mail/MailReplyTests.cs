using Koebumi.Core;

namespace Koebumi.Core.Tests;

// polishFixesNameHonorificAndGreetingWithoutAI は Polisher が必要なので、ここには移さない。
// 同じファイルにある TextDiffTests は Text/TextDiffTests.cs にある。EmailDraftTests は Prompts が必要なので、移していない
public partial class MailReplyTests
{
    static readonly FakeJapaneseReader Reader = new();

    static MailReplyContext? Read(SurroundingText s) => MailReply.Context(s, Reader);

    /// Apple Mail の返信。引用は入力欄のカーソルより後ろにある
    const string AppleMailQuote = "\n\n2026/10/22 15:00、東海林 太郎 <shoji@example.co.jp>のメール:\n\n> 矢野様\n>\n"
        + "> いつもお世話になっております。\n> 株式会社ABCの東海林です。";

    [Fact]
    public void ReadsSenderAndRegisterFromQuotedReply()
    {
        var c = Read(new SurroundingText { After = AppleMailQuote });
        Assert.Equal("東海林", c?.Name);
        Assert.Equal("東海林太郎", c?.FullName);
        Assert.Equal("様", c?.Honorific);
        Assert.Equal(true, c?.External);
        Assert.Equal("東海林様", c?.Addressee);
        Assert.Equal("お世話になっております。", c?.Greeting);
    }

    [Fact]
    public void ReadsARichTextReplyBelowTheUsersSignature()
    {
        // Web 表示の本文をテキストマーカーで読んだ文（引用に「> 」が付かず、自分の署名が引用の前にある）
        var after = "\n\n--\n矢野 康介\n\n\n2026/10/20 10:00、東海林 太郎 <shoji@example.co.jp>のメール：\n\n矢野様\n\n"
            + "いつも大変お世話になっております。\n株式会社サンプルの東海林です。\n\n先日の打ち合わせの資料をお送りします。\n"
            + "ご確認のほど、よろしくお願いいたします。\n\n--\n株式会社サンプル\n営業部 東海林 太郎";
        var c = Read(new SurroundingText { After = after, Screen = "宛先:\nCc:\n￼\n件名:\n差出人:\n署名:" });
        Assert.Equal("東海林様", c?.Addressee);
        Assert.Equal(true, c?.External);
    }

    [Fact]
    public void ReadsANameIntroducedBeforeTheGreeting()
    {
        // 差出人がアドレスだけで、挨拶（こんにちは）より先に「所属　名前です。」と名乗るメール。名前は署名の行で確かめる
        var after = "\n株式会社サンプル 営業部\n矢野 康介\nyano@example.com\n\n\n\n2026/10/24 18:30、tanaka@example.ac.jp のメール:\n\n"
            + "林さん\n矢野さん\n\n情報科学研究科2年　田中です。\n\nこんにちは。\n先日の件について連絡です。\n\nよろしくお願いします。\n\n"
            + "--------------------------------\n情報科学研究科\n田中　太郎\ntanaka@example.ac.jp";
        var c = Read(new SurroundingText { After = after });
        Assert.Equal("田中さん", c?.Addressee);
        Assert.Null(c?.External);
        // 署名に同じ名前がなければ、名乗りとみなさない
        var unsigned = "2026/10/24 18:30、tanaka@example.ac.jp のメール:\n\n矢野さん\n\n研究室の議事録です。\n\nご確認ください。";
        Assert.Null(Read(new SurroundingText { After = unsigned })?.Name);
    }

    [Fact]
    public void ReadsTheQuoteBelowTheComposerInSpark()
    {
        // Spark: 作成欄の上にスレッド（入力欄に近い末尾だけ）、下に「引用を表示」で開いた引用がある
        var screen = "よろしくお願いします。\n--------------------------------\nサンプル大学 広報課\n山田　花子\nyamada@example.ac.jp\n"
            + "宛先\nyamada@example.ac.jp\nRe: 取材の件";
        var screenAfter = "サンプル大学大学院\ns1234567@example.ac.jp\n矢野行祐\n"
            + "2026年10月20日 18:03 +0900, yamada@example.ac.jp<yamada@example.ac.jp>:\n\n林さん\n矢野さん\n"
            + "サンプル大学　山田です。\nこんばんは。\n先日お話しした取材の件です。";
        var c = Read(new SurroundingText { After = "\n", Screen = screen, ScreenAfter = screenAfter });
        Assert.Equal("山田さん", c?.Addressee);
        Assert.Null(c?.External);
    }

    [Fact]
    public void ReadsTheNewestMessageOfAThread()
    {
        // Gmail はスレッドを入力欄より前に出す。入力欄に近い（後ろの）メールが返信先
        var screen = "矢野 浩介\n<yano@example.com>\n東海林様\nお世話になっております。矢野です。\n"
            + "佐藤 花子\n<sato@example.com>\n矢野さん\nお疲れ様です。佐藤です。\n資料を確認しました。";
        var c = Read(new SurroundingText { Screen = screen });
        Assert.Equal("佐藤", c?.Name);
        Assert.Equal("さん", c?.Honorific);
        Assert.Equal(false, c?.External);
        Assert.Equal("お疲れ様です。", c?.Greeting);
    }

    [Fact]
    public void SkipsTheUsersOwnAddress()
    {
        var screen = "To: 矢野 浩介 <yano@example.com>\n矢野様\nお世話になっております。";
        var c = Read(new SurroundingText { Screen = screen });
        Assert.Null(c?.Name);
        Assert.Equal(true, c?.External);
    }

    [Fact]
    public void UsesAnIntroductionOnlyWhenTheSignatureHasTheName()
    {
        var signed = "矢野様\nお世話になっております。株式会社ABCの東海林です。\n見積書を添付いたします。\n株式会社ABC 営業部\n東海林 太郎";
        Assert.Equal("東海林", Read(new SurroundingText { Screen = signed })?.Name);
        // 「〜の議事録です」は名乗りではない
        var minutes = "矢野様\nお世話になっております。先日の会議の議事録です。\nご確認ください。";
        Assert.Null(Read(new SurroundingText { Screen = minutes })?.Name);
    }

    [Fact]
    public void ReturnsNilWithoutAnyClue()
    {
        Assert.Null(Read(new SurroundingText { Screen = "受信トレイ\n未読 3 件" }));
        Assert.Null(Read(new SurroundingText()));
    }

    [Fact]
    public void FixesTheOpeningGreetingToTheRelationship()
    {
        var external = new MailReplyContext { Name = "東海林", External = true };
        Assert.Equal("お世話になっております。資料を送ります。", MailReply.Adjust("お疲れ様です。資料を送ります。", external));
        Assert.Equal("東海林様、お世話になっております。", MailReply.Adjust("東海林さん、お疲れさまです。", external));
        var colleague = new MailReplyContext { Name = "佐藤", Honorific = "さん", External = false };
        Assert.Equal("佐藤さん\n\nお疲れ様です。\n資料を送ります。",
            MailReply.Adjust("佐藤さん\n\nいつもお世話になっております。\n資料を送ります。", colleague));
        // 書き出しでない挨拶（4 行目より後・文の途中）は変えない
        Assert.Equal("資料を送ります。\nよろしく\nお願いします。\nお疲れ様です。",
            MailReply.Adjust("資料を送ります。\nよろしく\nお願いします。\nお疲れ様です。", external));
        Assert.Equal("先方にお疲れ様ですと伝えてください。", MailReply.Adjust("先方にお疲れ様ですと伝えてください。", external));
    }

    [Fact]
    public void RaisesHonorificsButNeverLowersThem()
    {
        var external = new MailReplyContext { Name = "東海林", FullName = "東海林太郎", External = true };
        Assert.Equal("東海林様にご確認いただきました。", MailReply.Adjust("東海林さんにご確認いただきました。", external));
        Assert.Equal("東海林太郎様", MailReply.Adjust("東海林太郎さま", external));
        var colleague = new MailReplyContext { Name = "佐藤", Honorific = "さん", External = false };
        Assert.Equal("佐藤様にお送りしました。", MailReply.Adjust("佐藤様にお送りしました。", colleague));
        // 日本語でない文は変えない
        var english = new MailReplyContext { Name = "Smith", External = false };
        Assert.Equal("Hi Smith, Best regards", MailReply.Adjust("Hi Smith, Best regards", english));
    }

    [Fact]
    public void DraftsGetTheAddresseeLine()
    {
        var c = new MailReplyContext { Name = "東海林", External = true };
        Assert.Equal("東海林様\n\nお世話になっております。\n承知いたしました。", MailReply.FinishDraft("お疲れ様です。\n承知いたしました。", c));
        // 宛名を書いてあれば足さない
        Assert.Equal("東海林様\n\nお世話になっております。", MailReply.FinishDraft("東海林様\n\nお世話になっております。", c));
        // 挨拶で始まらない下書きにも足さない
        Assert.Equal("承知いたしました。", MailReply.FinishDraft("承知いたしました。", c));
    }

    // 以下は Windows 版で足したテスト

    [Fact]
    public void SplitsAFullNameWithoutASpaceIntoFamilyAndGivenName()
    {
        // 表示名が空白なしの姓名なら、日本語解析で姓だけを宛名に使う
        var c = Read(new SurroundingText { After = "\n\n東海林太郎 <shoji@example.co.jp>のメール:\n\n> 矢野様\n> お世話になっております。" });
        Assert.Equal("東海林", c?.Name);
        Assert.Equal("東海林太郎", c?.FullName);
        Assert.Equal("東海林様", c?.Addressee);
        // 読みの実装がなければ、分けずにそのまま使う
        var plain = MailReply.Context(new SurroundingText { After = "\n\n東海林太郎 <shoji@example.co.jp>のメール:\n\n> 矢野様" }, null);
        Assert.Equal("東海林太郎", plain?.Name);
        Assert.Null(plain?.FullName);
    }

    [Fact]
    public void ReadsAReplyWithWindowsLineEndings()
    {
        var after = AppleMailQuote.Replace("\n", "\r\n");
        var c = Read(new SurroundingText { After = after });
        Assert.Equal("東海林様", c?.Addressee);
        Assert.Equal(true, c?.External);
        Assert.Equal("お世話になっております。\r\n資料を送ります。", MailReply.Adjust("お疲れ様です。\r\n資料を送ります。", c!));
    }
}
