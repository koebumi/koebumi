using Koebumi.Core;

namespace Koebumi.Core.Tests;

// Mac 版の LogicTests.swift の ContextTests のうち、アプリの分類・連続日数・保存期間。
// settingsDecodeFillsMissingKeys は SettingsTests.DecodeFillsMissingKeysAndSkipsBadValues で確かめている
public partial class ContextTests
{
    // Mac 版の classifiesApps を、Windows の exe 名とブラウザのタイトルに書き直したもの
    [Fact]
    public void ClassifiesApps()
    {
        Assert.Equal(AppCategory.Chat, AppContext.Classify("slack.exe", null));
        Assert.Equal(AppCategory.Email, AppContext.Classify("chrome.exe", "受信トレイ - Gmail"));
        Assert.Equal(AppCategory.Email, AppContext.Classify("thunderbird.exe", null));
        Assert.Equal(AppCategory.Email, AppContext.Classify("Spark Desktop.exe", null));
        Assert.Equal(AppCategory.Email, AppContext.Classify("msedge.exe", "iCloud メール - 受信"));
        Assert.Equal(AppCategory.Email, AppContext.Classify("chrome.exe", "Inbox - Fastmail"));
        Assert.Equal(AppCategory.Ai, AppContext.Classify("chrome.exe", "ChatGPT"));
        Assert.Equal(AppCategory.Code, AppContext.Classify("idea64.exe", null));
        Assert.Equal(AppCategory.Other, AppContext.Classify("example.exe", "Untitled"));
    }

    [Fact]
    public void ClassifiesWindowsAppsByExeName()
    {
        foreach (var exe in new[] { "OUTLOOK.EXE", "olk.exe", "thunderbird.exe", "Spark Desktop.exe" })
            Assert.Equal(AppCategory.Email, AppContext.Classify(exe, null));
        foreach (var exe in new[] { "slack.exe", "ms-teams.exe", "Teams.exe", "Discord.exe", "LINE.exe", "Telegram.exe", "WhatsApp.exe" })
            Assert.Equal(AppCategory.Chat, AppContext.Classify(exe, null));
        foreach (var exe in new[] { "WINWORD.EXE", "notepad.exe", "Notion.exe", "Obsidian.exe", "ONENOTE.EXE" })
            Assert.Equal(AppCategory.Document, AppContext.Classify(exe, null));
        foreach (var exe in new[] { "Code.exe", "devenv.exe", "idea64.exe", "Cursor.exe", "WindowsTerminal.exe" })
            Assert.Equal(AppCategory.Code, AppContext.Classify(exe, null));
        foreach (var exe in new[] { "ChatGPT.exe", "Claude.exe" })
            Assert.Equal(AppCategory.Ai, AppContext.Classify(exe, null));
        // 表にあるアプリは、タイトルより exe 名が先
        Assert.Equal(AppCategory.Code, AppContext.Classify("Code.exe", "Gmail - notes.md"));
    }

    [Fact]
    public void ClassifiesBrowsersByWindowTitle()
    {
        foreach (var exe in new[] { "chrome.exe", "msedge.exe", "firefox.exe", "brave.exe", "arc.exe", "vivaldi.exe", "opera.exe" })
        {
            Assert.Equal(AppCategory.Email, AppContext.Classify(exe, "Inbox - Outlook"));
            Assert.Equal(AppCategory.Chat, AppContext.Classify(exe, "general | Acme | Slack"));
            Assert.Equal(AppCategory.Chat, AppContext.Classify(exe, "Microsoft Teams"));
            Assert.Equal(AppCategory.Ai, AppContext.Classify(exe, "Claude"));
            Assert.Equal(AppCategory.Ai, AppContext.Classify(exe, "Gemini"));
            Assert.Equal(AppCategory.Document, AppContext.Classify(exe, "議事録 - Google ドキュメント"));
            Assert.Equal(AppCategory.Document, AppContext.Classify(exe, "Notion"));
            Assert.Equal(AppCategory.Code, AppContext.Classify(exe, "koebumi/koebumi: Voice dictation · GitHub"));
            Assert.Equal(AppCategory.Other, AppContext.Classify(exe, "Weather forecast"));
            Assert.Equal(AppCategory.Other, AppContext.Classify(exe, null));
        }
        // 先に書いてあるキーワードが先（Mac 版と同じ順）
        Assert.Equal(AppCategory.Email, AppContext.Classify("chrome.exe", "Slack と Gmail"));
        // 大文字小文字は区別する（Mac 版の String.contains と同じ）
        Assert.Equal(AppCategory.Other, AppContext.Classify("chrome.exe", "gmail"));
        // ブラウザ以外の窓のタイトルは見ない
        Assert.Equal(AppCategory.Other, AppContext.Classify("explorer.exe", "Gmail"));
        Assert.Equal(AppCategory.Other, AppContext.Classify(null, "Gmail"));
    }

    [Fact]
    public void ExeNamesAreMatchedWithoutRegardToCaseOrPath()
    {
        Assert.Equal(AppCategory.Email, AppContext.Classify("outlook.exe", null));
        Assert.Equal(AppCategory.Email, AppContext.Classify("Outlook.Exe", null));
        Assert.Equal(AppCategory.Email, AppContext.Classify(@"C:\Program Files\Microsoft Office\root\Office16\OUTLOOK.EXE", null));
        Assert.Equal(AppCategory.Chat, AppContext.Classify("Slack", null));  // Process.ProcessName のように拡張子がなくてもよい
        Assert.Equal(AppCategory.Other, AppContext.Classify("", "Gmail"));
        Assert.Equal("outlook.exe", AppContext.NormalizeExeName(@"C:\x\OUTLOOK.EXE"));
        Assert.Equal("spark desktop.exe", AppContext.NormalizeExeName("Spark Desktop"));
        Assert.Null(AppContext.NormalizeExeName("  "));
        Assert.Null(AppContext.NormalizeExeName(null));
        Assert.True(AppContext.IsBrowser("Chrome.EXE"));
        Assert.False(AppContext.IsBrowser("slack.exe"));
    }

    [Fact]
    public void OverridesWinOverTheTable()
    {
        var overrides = new Dictionary<string, AppCategory>
        {
            ["slack.exe"] = AppCategory.Document,
            ["chrome.exe"] = AppCategory.Ai,
            ["myeditor.exe"] = AppCategory.Code,
        };
        Assert.Equal(AppCategory.Document, AppContext.Classify("Slack.exe", null, overrides));
        Assert.Equal(AppCategory.Ai, AppContext.Classify("chrome.exe", "受信トレイ - Gmail", overrides));
        Assert.Equal(AppCategory.Code, AppContext.Classify("MyEditor.EXE", "Untitled", overrides));
        Assert.Equal(AppCategory.Email, AppContext.Classify("olk.exe", null, overrides));
        // キーが大文字で書かれていても当たる
        Assert.Equal(AppCategory.Chat, AppContext.Classify("outlook.exe", null, new Dictionary<string, AppCategory> { ["OUTLOOK.EXE"] = AppCategory.Chat }));
        // 設定（AppSettings）のものをそのまま渡せる
        var settings = new AppSettings();
        settings.AppCategoryOverrides["notepad.exe"] = AppCategory.Email;
        Assert.Equal(AppCategory.Email, AppContext.Classify("notepad.exe", null, settings.AppCategoryOverrides));
    }

    [Fact]
    public void DescribeBuildsTheAppContext()
    {
        var info = AppContext.Describe(@"C:\Apps\Slack.exe", "Slack", "general - Acme", 1234);
        Assert.Equal(new AppContextInfo("slack.exe", "Slack", "general - Acme", AppCategory.Chat, 1234), info);
        Assert.Equal("Cursor", AppContext.Describe("Cursor.exe", null, null, null).AppName);
        Assert.Equal("App", AppContext.Describe(null, "", null, null).AppName);
        Assert.Equal(AppCategory.Document, AppContext.Describe("slack.exe", "Slack", null, null, new Dictionary<string, AppCategory> { ["slack.exe"] = AppCategory.Document }).Category);
        Assert.Equal(new AppContextInfo(null, "Unknown", null, AppCategory.Other, null), AppContextInfo.Unknown);
    }

    [Fact]
    public void StreakCountsConsecutiveDays()
    {
        var today = DateTime.Today;
        var days = new[] { 0, 1, 2, 4 }.Select(d => StatsStore.DayKey(today.AddDays(-d))).ToHashSet();
        Assert.Equal(3, StatsStore.Streak(days, today));
        var fromYesterday = new[] { 1, 2 }.Select(d => StatsStore.DayKey(today.AddDays(-d))).ToHashSet();
        Assert.Equal(2, StatsStore.Streak(fromYesterday, today));
        Assert.Equal(0, StatsStore.Streak(new HashSet<string>(), today));
        Assert.Equal(0, StatsStore.Streak(new[] { 2, 3 }.Select(d => StatsStore.DayKey(today.AddDays(-d))).ToHashSet(), today));
    }

    [Fact]
    public void RetentionPrunesOldItems()
    {
        Assert.Equal(TimeSpan.FromSeconds(7 * 86400), Retention.Week.Interval);
        Assert.Null(Retention.Forever.Interval);
        Assert.Equal(TimeSpan.Zero, Retention.Never.Interval);
    }
}
