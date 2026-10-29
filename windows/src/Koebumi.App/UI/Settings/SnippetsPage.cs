using System.Windows;
using System.Windows.Controls;
using Koebumi.Core;
using static Koebumi.App.SettingsUi;

namespace Koebumi.App;

/// 定型文: 呼び出す言葉だけを 1 つの文として話すと、登録した文を AI に通さずにそのまま入力する（署名・挨拶など）
internal sealed class SnippetsPage : SettingsPage
{
    public SnippetsPage(SettingsWindow host) : base(host) { }

    public override string Title => T("定型文", "Snippets");
    public override string Glyph => "\uE8C8";

    /// 追加するときのひな形。名前や連絡先は、登録するときに書き換えてもらう
    static IReadOnlyList<(string Title, Snippet Snippet)> Templates() =>
    [
        (T("書き出し（宛名と挨拶）", "Opening (addressee and greeting)"),
            new Snippet { Trigger = T("書き出し", "opening"), Text = SnippetExpander.AddresseeToken + "\n\n" + SnippetExpander.GreetingToken + "\n" + T("〇〇の〇〇です。", "This is ___ from ___.") }),
        (T("結び", "Closing"),
            new Snippet { Trigger = T("結び", "closing"), Text = T("引き続きよろしくお願いいたします。", "Best regards,") }),
        (T("署名", "Signature"),
            new Snippet { Trigger = T("署名", "signature"), Text = T("--\n名前\n会社名・部署\n電話番号・メールアドレス", "--\nName\nCompany\nPhone / Email") }),
    ];

    protected override void Build()
    {
        var add = PrimaryBtn("＋ " + T("定型文を追加", "Add snippet"), () => { });
        add.Click += (_, _) => ShowAddMenu(add);
        AddHeader(T("呼び出す言葉だけを 1 つの文として話すと、登録した文を AI に通さずにそのまま入力します。話す内容の最初と最後で使えます（例:「資料をお送りします。署名」）。",
                    "Say a trigger as its own sentence at the start or end of what you dictate, and Koebumi types the saved text as is, without AI."), add);

        var snippets = S.Snippets;
        if (snippets.Count == 0)
        {
            Add(EmptyState("\uE8C8", T("定型文はありません", "No snippets yet"),
                T("「定型文を追加」から、署名や書き出しの挨拶を登録できます。", "Add a signature or an opening greeting with “Add snippet”.")), 22);
            return;
        }
        Add(Group([.. snippets.Select(SnippetRow)]), 22);
    }

    UIElement SnippetRow(Snippet snippet)
    {
        var grid = new Grid { MinHeight = 56 };
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var text = new StackPanel { Margin = new Thickness(16, 11, 8, 11), VerticalAlignment = VerticalAlignment.Center };
        text.Children.Add(Label($"「{snippet.Trigger}」", 14, K.Text, FontWeights.Medium));
        var body = Label(snippet.Text, 12.5, K.TextSecondary);
        body.Margin = new Thickness(0, 4, 0, 0);
        body.MaxHeight = 3 * 18;
        body.LineHeight = 18;
        body.TextTrimming = TextTrimming.CharacterEllipsis;
        text.Children.Add(body);
        grid.Children.Add(text);

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 10, 10, 0) };
        buttons.Children.Add(IconBtn("\uE70F", T("編集", "Edit"), () => ShowDialog(snippet)));
        buttons.Children.Add(IconBtn("\uE74D", T("削除", "Delete"), () =>
        {
            Update(x => x.Snippets.RemoveAll(o => o.Id == snippet.Id));
            RefreshSoon();
        }));
        Grid.SetColumn(buttons, 1);
        grid.Children.Add(buttons);
        return grid;
    }

    void ShowAddMenu(Button anchor)
    {
        var menu = new ContextMenu { PlacementTarget = anchor, Placement = System.Windows.Controls.Primitives.PlacementMode.Bottom };
        menu.Items.Add(new MenuItem { Header = T("ひな形から追加", "Start from a template"), IsEnabled = false });
        foreach (var (title, snippet) in Templates())
        {
            var item = new MenuItem { Header = title };
            var template = snippet;
            item.Click += (_, _) => ShowDialog(template);
            menu.Items.Add(item);
        }
        menu.Items.Add(new Separator());
        var blank = new MenuItem { Header = T("空の定型文", "Blank snippet") };
        blank.Click += (_, _) => ShowDialog(new Snippet());
        menu.Items.Add(blank);
        menu.IsOpen = true;
    }

    /// 追加と編集の窓。ひな形から始めたときも、ここで名前や連絡先を書き換える
    void ShowDialog(Snippet snippet)
    {
        bool isNew = !S.Snippets.Any(o => o.Id == snippet.Id);
        var dialog = new FormDialog(Host, isNew ? T("定型文を追加", "New snippet") : T("定型文を編集", "Edit snippet"),
            T("呼び出す言葉は、ほかの文と区切って話します。表記が違っても読みが同じなら呼び出せます（署名・しょめい）。", "Say the trigger as its own sentence. Words that sound the same also work."),
            isNew ? T("追加", "Add") : T("保存", "Save"), 520);

        var (triggerHost, trigger) = TextInput(snippet.Trigger, T("例: 署名", "e.g. signature"));
        var duplicate = Label("", 12, K.TextSecondary);
        duplicate.Margin = new Thickness(0, 6, 0, 0);
        duplicate.Visibility = Visibility.Collapsed;
        var triggerField = FormDialog.Labeled(T("呼び出す言葉", "Trigger"), triggerHost);
        triggerField.Children.Insert(2, duplicate);
        dialog.Body.Children.Add(triggerField);

        var (textHost, text) = TextInput(snippet.Text, T("入力する文", "Text to type"), multiline: true);
        dialog.Body.Children.Add(FormDialog.Labeled(T("入力する文", "Text to type"), textHost,
            T($"メールでは {SnippetExpander.AddresseeToken} を返信先の宛名（東海林様）に、{SnippetExpander.GreetingToken} を「お世話になっております。」（社内の相手には「お疲れ様です。」）に置き換えます。宛名がわからないときは、{SnippetExpander.AddresseeToken} だけの行を書きません。",
              $"In email, {SnippetExpander.AddresseeToken} becomes the recipient (東海林様) and {SnippetExpander.GreetingToken} the Japanese opening greeting for them.")));

        dialog.CanOk = () => trigger.Text.Trim().Length > 0 && text.Text.Trim().Length > 0;
        void Changed()
        {
            // ほかの定型文と同じ呼び出す言葉（読みが同じものも含む）。先に登録したほうが使われる
            var same = S.Snippets.FirstOrDefault(o => o.Id != snippet.Id && SnippetExpander.Matches(trigger.Text, o.Trigger));
            duplicate.Visibility = same == null ? Visibility.Collapsed : Visibility.Visible;
            if (same != null)
                duplicate.Text = T($"「{same.Trigger}」と同じ言葉です。先に登録した定型文が使われます。", $"Same as “{same.Trigger}”. The earlier snippet is used.");
            dialog.Revalidate();
        }
        trigger.TextChanged += (_, _) => Changed();
        text.TextChanged += (_, _) => dialog.Revalidate();
        dialog.Accept = () =>
        {
            var saved = snippet with { Trigger = trigger.Text.Trim(), Text = text.Text.Replace("\r\n", "\n").Trim('\n') };
            Update(x =>
            {
                int i = x.Snippets.FindIndex(o => o.Id == snippet.Id);
                if (i >= 0) x.Snippets[i] = saved;
                else x.Snippets.Add(saved);
            });
            return true;
        };
        dialog.ContentRendered += (_, _) => { trigger.Focus(); trigger.CaretIndex = trigger.Text.Length; Changed(); };
        dialog.ShowDialog();
        RefreshSoon();
    }
}
