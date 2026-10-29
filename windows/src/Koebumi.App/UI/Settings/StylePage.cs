using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using Koebumi.Core;
using static Koebumi.App.SettingsUi;
using CoreAppContext = Koebumi.Core.AppContext;

namespace Koebumi.App;

/// スタイル: アプリの種類ごとのトーン、チャットの句読点、日本語の表記、アプリの種類の上書き
internal sealed class StylePage : SettingsPage
{
    static readonly (string Language, string Text)[] ChatSamples =
    [
        ("ja", "はい、了解です。資料は明日の朝に送ります。"),
        ("en", "Sure, sounds good. I'll send the file tomorrow morning."),
        ("zh", "好的，没问题。我明天早上发给你。"),
        ("ko", "네, 알겠습니다. 내일 아침에 보낼게요."),
    ];

    const string NotationSample = "お手数ですが、iPhone の設定を確認して下さい。明日出来る事から進めてもいいですか。";

    // 追加の行の入力の途中の状態（ページを組み立て直しても残す）
    string newExe = "";
    AppCategory newCategory = AppCategory.Other;

    public StylePage(SettingsWindow host) : base(host) { }

    public override string Title => T("スタイル", "Style");
    public override string Glyph => "\uE790";

    protected override void Build()
    {
        var s = S;
        AddHeader(T("アプリに合わせてトーンを変えます。", "Adapt the tone to each app."));

        AddSection(T("アプリごとのトーン", "Tone per app"),
            T("入力先のアプリの種類に合わせて言葉づかいを変えます。「自動」は学習した文体に合わせます。",
              "Koebumi adjusts wording to the kind of app you are typing in. “Auto” follows your learned style."),
            Group([.. Enum.GetValues<AppCategory>().Select(c => ToneRow(c, s))]));

        AddSection(T("チャット", "Chat"),
            T("「チャット」に分類したアプリ（Slack・LINE など）に入力するときの書き方です。", "How Koebumi writes in apps in the Chat category (Slack, LINE…)."),
            ChatGroup(s));

        if (s.WritesJapanese)
        {
            AddSection(T("日本語の表記", "Japanese notation"),
                T("入力する直前に、AI を使わない決まった処理でそろえます。AI の言い回しには影響しません。", "Applied right before typing by fixed rules, not by the AI, so the AI's wording is unaffected."),
                NotationGroup(s));
        }

        AddSection(T("アプリの種類", "App categories"),
            T("自動判定が合わないアプリは、ここで種類を指定できます。アプリは実行ファイルの名前（例: slack.exe）で見分けます。", "If an app is detected wrongly, set its category here. Apps are identified by their executable name (e.g. slack.exe)."),
            OverrideGroup(s));
    }

    // ---- トーン ----

    static string CategoryGlyph(AppCategory c) => c switch
    {
        AppCategory.Email => "\uE715",
        AppCategory.Chat => "\uE8BD",
        AppCategory.Document => "\uE8A5",
        AppCategory.Code => "\uE943",
        AppCategory.Ai => "\uE99A",
        _ => "\uE74C",
    };

    static string CategoryExamples(AppCategory c) => c switch
    {
        AppCategory.Email => T("Outlook・Thunderbird・Gmail（ブラウザ）など", "Outlook, Thunderbird, Gmail (in a browser)…"),
        AppCategory.Chat => T("Slack・Teams・LINE・Discord など", "Slack, Teams, LINE, Discord…"),
        AppCategory.Document => T("Word・メモ帳・Notion・Obsidian など", "Word, Notepad, Notion, Obsidian…"),
        AppCategory.Code => T("VS Code・Visual Studio・ターミナル など", "VS Code, Visual Studio, terminals…"),
        AppCategory.Ai => T("ChatGPT・Claude・Copilot など", "ChatGPT, Claude, Copilot…"),
        _ => T("上のどれにも当たらないアプリ", "Any other app"),
    };

    UIElement ToneRow(AppCategory category, AppSettings s) =>
        Row(category.Title, CategoryExamples(category),
            Combo(Enum.GetValues<StylePreset>(), s.StyleFor(category), p => p.Title,
                p => Update(x => x.SetStyle(category, p)), 190),
            CategoryGlyph(category), 56);

    // ---- チャット ----

    UIElement ChatGroup(AppSettings s)
    {
        var rows = new List<UIElement?>
        {
            Row(T("句読点", "Punctuation"),
                T("どの言語にも適用します。翻訳した文では読点を残し、文末の句点だけを付けません。「？」「！」と、1,000・3.5・a.m. のような数字と略語の「,」「.」は残します。",
                  "Applies to every language. Translations keep their commas and only drop the final period. ? and !, and the , and . in numbers and abbreviations like 1,000, 3.5 and a.m. stay."),
                Combo(Enum.GetValues<ChatPunctuation>(), s.ChatPunctuation, p => p.Title,
                    p => { Update(x => x.ChatPunctuation = p); RefreshSoon(); }, 190)),
        };
        if (s.ChatPunctuation != ChatPunctuation.Keep)
        {
            var dictation = s.DictationLanguages.Select(Languages.IsoCode).ToHashSet();
            var translation = s.TranslationTargets.Select(Languages.IsoCode).ToHashSet();
            var written = dictation.Concat(translation).ToHashSet();
            var shown = ChatSamples.Where(x => written.Contains(x.Language)).ToList();
            if (shown.Count == 0) shown = [.. ChatSamples.Where(x => x.Language == "en")];
            foreach (var sample in shown)
            {
                // 入力するときと同じく、日本語の表記ルールの後に句読点を消す。翻訳先にしか使わない言語は、翻訳した文の決まりで見せる
                bool translatedOnly = !dictation.Contains(sample.Language) && translation.Contains(sample.Language);
                var rule = translatedOnly ? s.ChatPunctuation.ForTranslation : s.ChatPunctuation;
                rows.Add(Example(Languages.Name(sample.Language), rule.Apply(JapaneseFormatter.Apply(sample.Text, s.JapaneseNotation))));
            }
        }
        return Group([.. rows]);
    }

    // ---- 日本語の表記 ----

    UIElement NotationGroup(AppSettings s) => Group(
        Row(T("句読点", "Punctuation"), null,
            Combo(Enum.GetValues<JapanesePunctuation>(), s.JapaneseNotation.Punctuation, p => p.Title,
                p => { Update(x => x.JapaneseNotation.Punctuation = p); RefreshSoon(); }, 190)),
        Row(T("英単語の前後の空白", "Spaces around English words"), null,
            Combo(Enum.GetValues<LatinSpacing>(), s.JapaneseNotation.LatinSpacing, p => p.Title,
                p => { Update(x => x.JapaneseNotation.LatinSpacing = p); RefreshSoon(); }, 190)),
        ToggleRow(T("補助動詞・形式名詞をひらがなで書く", "Write auxiliary verbs and formal nouns in hiragana"),
            T("〜して下さい → 〜してください、出来る → できる、する事 → すること。「資料を下さい」のような本来の意味の語は変えません。",
              "して下さい → してください, 出来る → できる, する事 → すること. Content words stay in kanji."),
            s.JapaneseNotation.HiraganaForms, on => { Update(x => x.JapaneseNotation.HiraganaForms = on); RefreshSoon(); }),
        ToggleRow(T("疑問文の文末を「？」にする", "End questions with ？"),
            T("〜ですか。・〜ますか。・〜でしょうか。を「？」で終えます。「今何時」のように語尾で疑問とわからない文は、AI の整形に任せます。",
              "〜ですか。, 〜ますか。 and 〜でしょうか。 end with ？. Questions without such endings are left to AI cleanup."),
            s.JapaneseNotation.QuestionMark, on => { Update(x => x.JapaneseNotation.QuestionMark = on); RefreshSoon(); }),
        Example(T("例", "Example"), JapaneseFormatter.Apply(NotationSample, s.JapaneseNotation)));

    // ---- アプリの種類の上書き ----

    UIElement OverrideGroup(AppSettings s)
    {
        var rows = new List<UIElement?> { AddOverrideRow() };
        var overrides = s.AppCategoryOverrides.OrderBy(p => p.Key, StringComparer.Ordinal).ToList();
        if (overrides.Count == 0)
        {
            var none = Label(T("指定したアプリはありません。上の欄に実行ファイルの名前を入れるか、起動中のアプリから選んで追加してください。",
                               "No apps assigned yet. Enter an executable name above, or pick a running app."), 12.5, K.TextSecondary);
            rows.Add(Content(none));
        }
        foreach (var (exe, category) in overrides)
        {
            string key = exe;
            var right = new StackPanel { Orientation = Orientation.Horizontal };
            right.Children.Add(Combo(Enum.GetValues<AppCategory>(), category, c => c.Title,
                c => Update(x => x.AppCategoryOverrides[key] = c), 170));
            var remove = IconBtn("\uE711", T("削除", "Remove"), () => { Update(x => x.AppCategoryOverrides.Remove(key)); RefreshSoon(); });
            remove.Margin = new Thickness(4, 0, 0, 0);
            right.Children.Add(remove);
            rows.Add(Row(exe, CoreAppContext.Classify(exe, null) is var auto && auto != category ? T($"自動判定: {auto.Title}", $"Detected as: {auto.Title}") : null, right, minHeight: 52));
        }
        return Group([.. rows]);
    }

    /// 追加の行: 実行ファイルの名前、種類、追加、起動中のアプリから選ぶ
    UIElement AddOverrideRow()
    {
        var box = new TextBox { Text = newExe, Width = 170, VerticalContentAlignment = VerticalAlignment.Center };
        var hint = Label("slack.exe", 14, K.TextTertiary, wrap: false);
        hint.IsHitTestVisible = false;
        hint.Margin = new Thickness(11, 0, 8, 0);
        hint.VerticalAlignment = VerticalAlignment.Center;
        hint.Visibility = newExe.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        var field = new Grid { Width = 170 };
        field.Children.Add(box);
        field.Children.Add(hint);
        box.TextChanged += (_, _) =>
        {
            newExe = box.Text;
            hint.Visibility = box.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        };

        void AddNow()
        {
            if (CoreAppContext.NormalizeExeName(box.Text) is not { } exe) return;
            var category = newCategory;
            newExe = "";
            Update(x => x.AppCategoryOverrides[exe] = category);
            RefreshSoon();
        }
        box.KeyDown += (_, e) => { if (e.Key == System.Windows.Input.Key.Enter) AddNow(); };

        var pick = Btn(T("起動中のアプリ…", "Running apps…"), () => { });
        pick.Click += (_, _) => ShowRunningApps(pick, name => { box.Text = name; box.Focus(); box.CaretIndex = box.Text.Length; });

        var panel = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(16, 12, 16, 12) };
        panel.Children.Add(field);
        var combo = Combo(Enum.GetValues<AppCategory>(), newCategory, c => c.Title, c => newCategory = c, 150);
        combo.Margin = new Thickness(8, 0, 0, 0);
        panel.Children.Add(combo);
        var add = Btn(T("追加", "Add"), AddNow);
        add.Margin = new Thickness(8, 0, 0, 0);
        panel.Children.Add(add);
        pick.Margin = new Thickness(8, 0, 0, 0);
        panel.Children.Add(pick);
        return panel;
    }

    /// ウィンドウのある起動中のアプリを、実行ファイルの名前（小文字）で一覧にして、選んだ名前を返す
    void ShowRunningApps(Button anchor, Action<string> chosen)
    {
        var assigned = S.AppCategoryOverrides.Keys.ToHashSet();
        var names = new SortedSet<string>(StringComparer.Ordinal);
        foreach (var process in Process.GetProcesses())
        {
            try
            {
                if (process.Id == Environment.ProcessId || process.MainWindowHandle == IntPtr.Zero) continue;
                if (CoreAppContext.NormalizeExeName(process.ProcessName) is { } exe && !assigned.Contains(exe)) names.Add(exe);
            }
            catch (Exception)
            {
                // 終わったばかりのプロセスなど。読めないものは飛ばす
            }
            finally { process.Dispose(); }
        }
        var menu = new ContextMenu { PlacementTarget = anchor, Placement = System.Windows.Controls.Primitives.PlacementMode.Bottom, MaxHeight = 360 };
        if (names.Count == 0) menu.Items.Add(new MenuItem { Header = T("追加できるアプリはありません", "No apps to add"), IsEnabled = false });
        foreach (var name in names)
        {
            var item = new MenuItem { Header = name };
            item.Click += (_, _) => chosen(name);
            menu.Items.Add(item);
        }
        menu.IsOpen = true;
    }
}
