using System.Windows;
using System.Windows.Controls;
using Koebumi.Core;
using static Koebumi.App.SettingsUi;

namespace Koebumi.App;

/// 一般: 表示言語・マイク・話す言語と翻訳先・画面の文脈・結果と履歴
internal sealed class GeneralPage : SettingsPage
{
    public GeneralPage(SettingsWindow host) : base(host) { }

    public override string Title => T("一般", "General");
    public override string Glyph => "\uE713";

    protected override void Build()
    {
        var s = S;
        AddHeader();

        Add(Group(
            Row(T("表示言語", "Interface language"), T("メニューと画面の言語", "Language for menus and windows"),
                Combo<UILanguage>([UILanguage.Ja, UILanguage.En], s.UiLanguage, l => l.DisplayName, l => Update(x => x.UiLanguage = l), 140)),
            MicrophoneRow(s)), 24);

        AddSection(T("話す言語", "Languages you speak"),
            T("話す言語を登録し、使用中の言語を選びます。", "Add the languages you speak and choose the one in use."),
            LanguageGroup(translate: false), trailing: AddLanguageCombo(translate: false));

        AddSection(T("翻訳先", "Translation targets"),
            T("訳す言語を登録し、使用中の言語を選びます。", "Add the languages to translate into and choose the one in use."),
            LanguageGroup(translate: true), trailing: AddLanguageCombo(translate: true));

        AddSection(T("画面の文脈", "Screen context"), null, ContextGroup(s));

        var results = Group(
            ToggleRow(T("入力した結果をクリップボードにも残す", "Keep results in the clipboard"),
                T("貼り付けたあとも、結果をもう一度ペーストできます", "Paste the last result again after it is inserted"),
                s.KeepResultInClipboard, on => Update(x => x.KeepResultInClipboard = on)),
            ToggleRow(T("音声を保存する", "Save audio"),
                T("履歴からの再処理と音声のダウンロードに使います", "Used to retry and download recordings from History"),
                s.KeepAudio, on => Update(x => x.KeepAudio = on)),
            Row(T("履歴の保存期間", "Keep history"), T("期間を過ぎた履歴は自動で削除します", "Older history is deleted automatically"),
                Combo(Enum.GetValues<Retention>(), s.HistoryRetention, r => r.Title, ChangeRetention, 140)));
        AddSection(T("結果と履歴", "Results & history"), T("履歴・音声・辞書はすべてこの PC の中に保存され、外部に送信されません。", "History, audio and dictionary are stored only on this PC."), results);
    }

    // ---- マイク ----

    UIElement MicrophoneRow(AppSettings s)
    {
        var devices = AudioDevices.Capture();
        var names = devices.ToDictionary(d => d.Id, d => d.Name);
        var ids = new List<string?> { null };
        ids.AddRange(devices.Select(d => (string?)d.Id));
        // 外してあるマイクを選んだままのときは、選択を残す
        if (s.MicrophoneId is { } saved && !names.ContainsKey(saved)) ids.Add(saved);
        var defaultName = devices.FirstOrDefault(d => d.IsDefault)?.Name;

        string Name(string? id) => id switch
        {
            null => T("自動（既定のデバイス）", "Auto (default device)") + (defaultName != null ? $"　{defaultName}" : ""),
            _ => names.TryGetValue(id, out var n) ? n : T("接続されていないマイク", "Microphone not connected"),
        };

        var combo = Combo(ids, s.MicrophoneId, Name, id => Update(x => x.MicrophoneId = id), 220);
        var trailing = new StackPanel { Orientation = Orientation.Horizontal };
        trailing.Children.Add(combo);
        var reload = IconBtn("\uE72C", T("デバイスの一覧を更新", "Refresh the device list"), RefreshSoon);
        reload.Margin = new Thickness(4, 0, 0, 0);
        trailing.Children.Add(reload);
        return Row(T("マイク", "Microphone"), T("音声入力に使うデバイス", "The input device used for dictation"), trailing);
    }

    // ---- 言語 ----

    UIElement AddLanguageCombo(bool translate)
    {
        var list = translate ? S.TranslationTargets : S.DictationLanguages;
        var options = (translate ? Languages.TranslationTargets : Languages.Dictation).Where(l => !list.Contains(l)).ToList();
        // 先頭の「追加」は見出し。選んだ言語を足したら、すぐ見出しに戻る
        var box = new ComboBox { MinWidth = 150 };
        box.Items.Add("＋ " + T("言語を追加", "Add language"));
        foreach (var lang in options) box.Items.Add(Languages.Name(lang));
        box.SelectedIndex = 0;
        box.SelectionChanged += (_, _) =>
        {
            int i = box.SelectedIndex;
            if (i <= 0) return;
            var lang = options[i - 1];
            Update(x => (translate ? x.TranslationTargets : x.DictationLanguages).Add(lang));
            RefreshSoon();
        };
        return box;
    }

    UIElement LanguageGroup(bool translate)
    {
        var s = S;
        var list = translate ? s.TranslationTargets : s.DictationLanguages;
        var active = translate ? s.CurrentTranslationTarget : s.CurrentDictationLanguage;
        var rows = new List<UIElement?>();
        for (int i = 0; i < list.Count; i++)
        {
            int index = i;
            var lang = list[i];
            var grid = new Grid { MinHeight = 48 };
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(46) });
            grid.ColumnDefinitions.Add(new ColumnDefinition());
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var radio = RadioMark(lang == active);
            radio.SetValue(FrameworkElement.MarginProperty, new Thickness(16, 0, 0, 0));
            grid.Children.Add(radio);

            var name = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 8, 8, 8) };
            name.Children.Add(Label(Languages.Name(lang), 14, K.Text, FontWeights.Medium, wrap: false));
            var code = Label(lang, 12, K.TextTertiary, wrap: false);
            code.Margin = new Thickness(10, 1, 0, 0);
            code.VerticalAlignment = VerticalAlignment.Center;
            name.Children.Add(code);
            if (lang == active)
            {
                var badge = Badge(T("使用中", "In use"));
                badge.Margin = new Thickness(10, 0, 0, 0);
                name.Children.Add(badge);
            }
            Grid.SetColumn(name, 1);
            grid.Children.Add(name);

            var buttons = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 10, 0) };
            buttons.Children.Add(IconBtn("\uE70E", T("上へ", "Move up"), () => Move(translate, index, -1), enabled: index > 0));
            buttons.Children.Add(IconBtn("\uE70D", T("下へ", "Move down"), () => Move(translate, index, 1), enabled: index < list.Count - 1));
            buttons.Children.Add(IconBtn("\uE711", T("削除", "Remove"), () => Remove(translate, lang), enabled: list.Count > 1));
            Grid.SetColumn(buttons, 2);
            grid.Children.Add(buttons);

            rows.Add(Hoverable(grid, () =>
            {
                if (lang == active) return;
                Update(x => { if (translate) x.ActiveTranslationTarget = lang; else x.ActiveDictationLanguage = lang; });
                RefreshSoon();
            }));
        }
        return Group([.. rows]);
    }

    void Move(bool translate, int index, int delta)
    {
        Update(x =>
        {
            var list = translate ? x.TranslationTargets : x.DictationLanguages;
            int j = index + delta;
            if (j < 0 || j >= list.Count) return;
            (list[index], list[j]) = (list[j], list[index]);
        });
        RefreshSoon();
    }

    void Remove(bool translate, string lang)
    {
        Update(x =>
        {
            var list = translate ? x.TranslationTargets : x.DictationLanguages;
            if (list.Count <= 1) return;
            list.Remove(lang);
            // 使用中の言語を消したときは、先頭の言語を使う
            if (translate && x.ActiveTranslationTarget == lang) x.ActiveTranslationTarget = null;
            if (!translate && x.ActiveDictationLanguage == lang) x.ActiveDictationLanguage = null;
        });
        RefreshSoon();
    }

    // ---- 画面の文脈 ----

    UIElement ContextGroup(AppSettings s)
    {
        string ContextTitle(ContextAwareness c) => c switch
        {
            ContextAwareness.Off => T("使わない", "Off"),
            ContextAwareness.LocalOnly => T("この PC で処理するときだけ", "Only when processed on this PC"),
            _ => T("クラウドの AI にも送る", "Also send to cloud AI"),
        };

        var context = Row(T("入力欄と画面の文章を読む", "Read the text field and window"),
            T("カーソルの前後と、同じウィンドウに表示されている文章を読み、人名の表記（渡辺さん → 渡邉さん）や文のつながりを合わせます。AI に渡すのは拾った人名・用語だけで、文章そのものは渡しません。読んだ内容は保存せず、パスワード欄は読みません。",
              "Reads around the cursor and the text in the same window to spell names the way they appear and to continue your sentence. Only the names and terms it finds are given to the AI, never the text itself. Nothing is saved, and password fields are never read."),
            Combo(Enum.GetValues<ContextAwareness>(), s.ContextAwareness, ContextTitle,
                c => { Update(x => x.ContextAwareness = c); RefreshSoon(); }, 200));

        UIElement? note = null;
        if (s.ContextAwareness == ContextAwareness.LocalOnly && !s.ShareSurroundingWithLLM)
        {
            var text = Label(T("いまの文章整形エンジンはクラウドで処理するため、画面の人名・用語は送りません。人名の表記やつなぎ方の調整など、この PC の中の処理にだけ使います。",
                               "Your cleanup engine runs in the cloud, so names and terms from the screen are not sent. They are only used on this PC, for example to fix name spellings and spacing."),
                12.5, K.TextSecondary);
            note = Content(text);
        }

        bool writesJapanese = s.DictationLanguages.Concat(s.TranslationTargets).Any(l => l.StartsWith("ja", StringComparison.Ordinal));
        UIElement? mail = null;
        if (writesJapanese)
        {
            bool off = s.ContextAwareness == ContextAwareness.Off;
            mail = ToggleRow(T("返信先に合わせて、挨拶と敬称を直す", "Match greetings and honorifics to the email you reply to"),
                off
                    ? T("画面の文脈を「使わない」にしているため、今は使えません。", "Unavailable while screen context is off.")
                    : T("画面の受信メールから、相手の名前と、社外か社内かを読みます。社外の相手への「お疲れ様です」は「お世話になっております」に、社内の相手への「お世話になっております」は「お疲れ様です」に、相手の名前の「さん」は「様」に直します。直すのは話した言葉だけで、話していない挨拶は足しません。AI を使わずに、この PC の中で直します。",
                        "Koebumi reads the sender's name and whether they are outside your company from the email on screen, then fixes the opening greeting and raises さん to 様 for that person. Only words you said are changed, on this PC, without AI."),
                s.MailReplyStyle, on => Update(x => x.MailReplyStyle = on), enabled: !off);
        }
        return Group(context, note, mail);
    }

    // ---- 履歴の保存期間 ----

    void ChangeRetention(Retention retention)
    {
        if (retention == Retention.Never && Services.History.Items.Count > 0)
        {
            var answer = MessageBox.Show(Host, T("保存してある履歴をすべて削除します。よろしいですか？", "This deletes all saved history. Continue?"),
                "Koebumi", MessageBoxButton.OKCancel, MessageBoxImage.Warning);
            if (answer != MessageBoxResult.OK)
            {
                RefreshSoon();
                return;
            }
        }
        Update(x => x.HistoryRetention = retention);
        Services.History.Prune(retention);
        if (retention == Retention.Never) Services.History.DeleteAll();
    }
}
