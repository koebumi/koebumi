namespace Koebumi.Core;

/// 入力先アプリの情報。トーン調整（アプリ別スタイル）に使う。
/// ExeName は exe のファイル名を小文字にしたもの（例: outlook.exe）。設定の AppCategoryOverrides のキーと、履歴の AppBundleID に使う
public sealed record AppContextInfo(string? ExeName, string AppName, string? WindowTitle, AppCategory Category, int? ProcessId)
{
    public static AppContextInfo Unknown => new(null, "Unknown", null, AppCategory.Other, null);
}

public static class AppContext
{
    /// 最前面の窓の情報から、入力先アプリの情報を作る。アプリの種類は、設定で選び直したもの（overrides）が先
    public static AppContextInfo Describe(
        string? exeName, string? appName, string? windowTitle, int? processId,
        IReadOnlyDictionary<string, AppCategory>? overrides = null)
    {
        var exe = NormalizeExeName(exeName);
        var shown = appName is { Length: > 0 } ? appName : FileName(exeName) is { } file ? WithoutExtension(file) : "App";
        return new AppContextInfo(exe, shown, windowTitle, Classify(exe, windowTitle, overrides), processId);
    }

    /// exe の名前をそろえる（パスは外し、「.exe」がなければ足して、小文字にする）。名前が空なら null
    public static string? NormalizeExeName(string? exeName)
    {
        if (FileName(exeName) is not { } name) return null;
        if (!name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)) name += ".exe";
        return name.ToLowerInvariant();
    }

    static string? FileName(string? exeName)
    {
        if (string.IsNullOrWhiteSpace(exeName)) return null;
        var name = exeName.Trim();
        name = name[(name.LastIndexOfAny(['\\', '/']) + 1)..];
        return name.Length == 0 ? null : name;
    }

    static string WithoutExtension(string file) =>
        file.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) && file.Length > 4 ? file[..^4] : file;

    /// ブラウザかどうか（ブラウザはウィンドウタイトルで Web アプリを見分ける）
    public static bool IsBrowser(string? exeName) => NormalizeExeName(exeName) is { } exe && Browsers.Contains(exe);

    static Dictionary<string, AppCategory> Table(params (AppCategory Category, string[] Exes)[] groups)
    {
        var table = new Dictionary<string, AppCategory>(StringComparer.OrdinalIgnoreCase);
        foreach (var (category, exes) in groups)
            foreach (var exe in exes) table[exe] = category;
        return table;
    }

    /// Mac 版のバンドル ID の表を、Windows の exe 名に置き換えたもの。Windows にないアプリ（Mail・Notes・Xcode・iTerm2 など）は載せない
    static readonly Dictionary<string, AppCategory> ExeCategories = Table(
        (AppCategory.Email, [
            "outlook.exe", "olk.exe", "hxoutlook.exe", "thunderbird.exe", "spark desktop.exe", "spark.exe", "mailclient.exe",
            "proton mail.exe", "mailspring.exe", "missive.exe", "spike.exe", "mailbird.exe",
        ]),
        (AppCategory.Chat, [
            "slack.exe", "discord.exe", "line.exe", "whatsapp.exe", "whatsapp.root.exe", "ms-teams.exe", "teams.exe",
            "telegram.exe", "messenger.exe", "zoom.exe", "chatwork.exe", "kakaotalk.exe",
        ]),
        (AppCategory.Document, [
            "winword.exe", "notepad.exe", "wordpad.exe", "notion.exe", "obsidian.exe", "onenote.exe", "craft.exe",
            "powerpnt.exe", "figma.exe",
        ]),
        (AppCategory.Code, [
            "code.exe", "code - insiders.exe", "devenv.exe", "cursor.exe", "windsurf.exe", "zed.exe", "sublime_text.exe", "notepad++.exe",
            "idea64.exe", "pycharm64.exe", "webstorm64.exe", "phpstorm64.exe", "rider64.exe", "clion64.exe", "goland64.exe",
            "rubymine64.exe", "datagrip64.exe", "dataspell64.exe", "rustrover64.exe", "aqua64.exe", "studio64.exe", "fleet.exe",
            "windowsterminal.exe", "wt.exe", "cmd.exe", "powershell.exe", "pwsh.exe", "conhost.exe", "openconsole.exe",
            "mintty.exe", "warp.exe", "wezterm-gui.exe", "wezterm.exe", "alacritty.exe",
        ]),
        (AppCategory.Ai, [
            "chatgpt.exe", "codex.exe", "claude.exe", "perplexity.exe", "copilot.exe",
        ]));

    static readonly HashSet<string> Browsers = new(StringComparer.OrdinalIgnoreCase)
    {
        "chrome.exe", "msedge.exe", "firefox.exe", "brave.exe", "arc.exe", "vivaldi.exe", "opera.exe",
        "chromium.exe", "zen.exe", "waterfox.exe", "librewolf.exe", "iexplore.exe",
    };

    /// ブラウザのウィンドウタイトルで判定する Web アプリ（上にあるものが先）
    static readonly (string Keyword, AppCategory Category)[] TitleCategories =
    [
        ("Gmail", AppCategory.Email), ("Outlook", AppCategory.Email), ("Yahoo!メール", AppCategory.Email), ("Yahoo Mail", AppCategory.Email), ("Yahoo! Mail", AppCategory.Email),
        ("Proton Mail", AppCategory.Email), ("iCloud メール", AppCategory.Email), ("iCloud Mail", AppCategory.Email), ("Fastmail", AppCategory.Email), ("Zoho Mail", AppCategory.Email),
        ("AOL Mail", AppCategory.Email), ("Superhuman", AppCategory.Email), ("Shortwave", AppCategory.Email), ("Roundcube", AppCategory.Email), ("Active! mail", AppCategory.Email),
        ("Slack", AppCategory.Chat), ("Discord", AppCategory.Chat), ("Chatwork", AppCategory.Chat), ("Messenger", AppCategory.Chat), ("WhatsApp", AppCategory.Chat),
        ("Microsoft Teams", AppCategory.Chat), ("LINE", AppCategory.Chat), ("Google Chat", AppCategory.Chat),
        ("Google ドキュメント", AppCategory.Document), ("Google Docs", AppCategory.Document), ("Notion", AppCategory.Document), ("Confluence", AppCategory.Document),
        ("Google スライド", AppCategory.Document), ("Google Slides", AppCategory.Document), ("Dropbox Paper", AppCategory.Document), ("note", AppCategory.Document),
        ("GitHub", AppCategory.Code), ("GitLab", AppCategory.Code), ("Stack Overflow", AppCategory.Code), ("CodeSandbox", AppCategory.Code),
        ("ChatGPT", AppCategory.Ai), ("Claude", AppCategory.Ai), ("Gemini", AppCategory.Ai), ("Perplexity", AppCategory.Ai), ("Copilot", AppCategory.Ai),
    ];

    /// 入力先アプリの種類を決める。設定で選び直したもの（overrides。キーは小文字の exe 名）が先、次に exe 名の表、
    /// ブラウザならウィンドウタイトル。どれにも当たらなければ Other。exe 名の大文字小文字は区別しない
    public static AppCategory Classify(string? exeName, string? windowTitle, IReadOnlyDictionary<string, AppCategory>? overrides = null)
    {
        if (NormalizeExeName(exeName) is not { } exe) return AppCategory.Other;
        if (overrides is not null)
        {
            if (overrides.TryGetValue(exe, out var chosen)) return chosen;
            foreach (var (key, category) in overrides)
                if (NormalizeExeName(key) == exe) return category;
        }
        if (ExeCategories.TryGetValue(exe, out var known)) return known;
        if (windowTitle is not null && Browsers.Contains(exe))
        {
            foreach (var (keyword, category) in TitleCategories)
                if (windowTitle.Contains(keyword, StringComparison.Ordinal)) return category;
        }
        return AppCategory.Other;
    }
}
