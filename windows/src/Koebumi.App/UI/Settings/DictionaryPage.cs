using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using Koebumi.Core;
using Microsoft.Win32;
using static Koebumi.App.SettingsUi;

namespace Koebumi.App;

/// 辞書: 単語（と、音声認識での聞き取られ方）の一覧、追加・編集・削除、検索、CSV の取り込みと書き出し。
/// 登録した語は、音声認識のヒントと、整形のときの綴りの指定に使う
internal sealed class DictionaryPage : SettingsPage
{
    /// 一度に並べる行の数の上限（多い辞書でも画面が重くならないよう、検索で絞り込んでもらう）
    const int MaxRows = 300;

    string search = "";
    string? notice;

    public DictionaryPage(SettingsWindow host) : base(host)
    {
        // 辞書は、別のプロセス（コマンド）や別のスレッドからも変わる。見えているときだけ、UI スレッドで組み立て直す
        host.Services.Dictionary.Changed += (_, _) => host.Dispatcher.BeginInvoke(() =>
        {
            if (host.IsShowing(this)) Refresh();
        });
    }

    public override string Title => T("辞書", "Dictionary");
    public override string Glyph => "\uE82D";

    protected override void Build()
    {
        var all = Services.Dictionary.Entries;

        var buttons = new StackPanel { Orientation = Orientation.Horizontal };
        var more = new Button { Content = Icon("\uE712", 14, K.Text), Width = 34, Height = 32, Padding = new Thickness(0), ToolTip = T("その他", "More"), Margin = new Thickness(0, 0, 8, 0) };
        more.Click += (_, _) => ShowMenu(more, all.Count > 0);
        buttons.Children.Add(more);
        buttons.Children.Add(PrimaryBtn("＋ " + T("新しい単語", "New word"), () => ShowAddDialog()));
        AddHeader(T("人名・略語・専門用語を登録すると、認識と表記が正確になります。", "Add names, acronyms and jargon so they are recognized and spelled correctly."), buttons);

        if (notice != null)
        {
            Add(Callout("\uE73E", notice, IconBtn("\uE711", T("閉じる", "Dismiss"), () => { notice = null; RefreshSoon(); }, size: 28)), 18);
        }

        // 検索。打っているあいだは、入力欄を作り直さずに、下の一覧だけを入れ替える
        var (host, box) = TextInput(search, T("単語・聞き取られ方を検索", "Search words"), width: 280);
        host.HorizontalAlignment = HorizontalAlignment.Left;
        box.TextChanged += (_, _) =>
        {
            search = box.Text;
            FillResults();
        };
        Add(host, 18);
        results = new StackPanel();
        Add(results, 0);
        FillResults();
    }

    StackPanel results = new();

    /// 件数と一覧（検索に合うもの）を results に並べる
    void FillResults()
    {
        results.Children.Clear();
        var all = Services.Dictionary.Entries;
        var entries = all.Where(Matches).ToList();
        if (entries.Count == 0)
        {
            var empty = all.Count == 0
                ? EmptyState("\uE82D", T("単語がありません", "No words yet"), T("「新しい単語」から追加できます。", "Add words with “New word”."))
                : EmptyState("\uE721", T("見つかりませんでした", "No results"), T("検索語を変えてみてください。", "Try a different search."));
            if (empty is FrameworkElement fe) fe.Margin = new Thickness(0, 14, 0, 0);
            results.Children.Add(empty);
            return;
        }

        var count = Label(entries.Count > MaxRows
            ? T($"{entries.Count} 語（先頭の {MaxRows} 語を表示。検索で絞り込めます）", $"{entries.Count} words (showing the first {MaxRows}; search to narrow down)")
            : T($"{entries.Count} 語", $"{entries.Count} words"), 12, K.TextTertiary);
        count.Margin = new Thickness(4, 14, 0, 8);
        results.Children.Add(count);
        results.Children.Add(Group([.. entries.Take(MaxRows).Select(EntryRow)]));
    }

    bool Matches(DictionaryEntry e) =>
        search.Length == 0
        || e.Term.Contains(search, StringComparison.CurrentCultureIgnoreCase)
        || (e.Replaced ?? "").Contains(search, StringComparison.CurrentCultureIgnoreCase);

    UIElement EntryRow(DictionaryEntry entry)
    {
        var grid = new Grid { MinHeight = 52 };
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(16, 9, 8, 9) };
        text.Children.Add(Label(entry.Term, 14, K.Text, FontWeights.Medium));
        if (!string.IsNullOrEmpty(entry.Replaced))
        {
            var line = new TextBlock { TextWrapping = TextWrapping.Wrap, FontSize = 12, Margin = new Thickness(0, 3, 0, 0) };
            line.SetResourceReference(TextBlock.ForegroundProperty, K.TextTertiary);
            line.Inlines.Add(new Run(entry.Replaced) { TextDecorations = TextDecorations.Strikethrough });
            line.Inlines.Add(new Run("   →   "));
            line.Inlines.Add(new Run(entry.Term));
            text.Children.Add(line);
        }
        grid.Children.Add(text);

        var right = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 10, 0) };
        right.Children.Add(Badge(entry.Source == DictionarySource.Auto ? T("自動", "Auto") : T("手動", "Manual")));
        var edit = IconBtn("\uE70F", T("編集", "Edit"), () => ShowEditDialog(entry));
        edit.Margin = new Thickness(8, 0, 0, 0);
        right.Children.Add(edit);
        right.Children.Add(IconBtn("\uE74D", T("削除", "Delete"), () => Services.Dictionary.Delete(entry)));
        Grid.SetColumn(right, 1);
        grid.Children.Add(right);
        return grid;
    }

    // ---- メニューと CSV ----

    void ShowMenu(Button anchor, bool canExport)
    {
        var menu = new ContextMenu { PlacementTarget = anchor, Placement = System.Windows.Controls.Primitives.PlacementMode.Bottom };
        var import = new MenuItem { Header = T("CSV を取り込む…", "Import CSV…") };
        import.Click += (_, _) => ImportCsv();
        var export = new MenuItem { Header = T("CSV を書き出す…", "Export CSV…"), IsEnabled = canExport };
        export.Click += (_, _) => ExportCsv();
        menu.Items.Add(import);
        menu.Items.Add(export);
        menu.IsOpen = true;
    }

    /// 取り込んだ語の数を知らせる。取り込めたかどうかは、辞書の Changed で一覧に出る
    bool ImportCsv(Window? owner = null)
    {
        var dialog = new OpenFileDialog
        {
            Filter = T("CSV・テキスト (*.csv;*.txt)|*.csv;*.txt|すべてのファイル (*.*)|*.*", "CSV or text (*.csv;*.txt)|*.csv;*.txt|All files (*.*)|*.*"),
        };
        if (dialog.ShowDialog(owner ?? Host) != true) return false;
        try
        {
            int count = Services.Dictionary.ImportCsv(File.ReadAllText(dialog.FileName, Encoding.UTF8));
            notice = T($"{count} 語を取り込みました", $"Imported {count} words");
        }
        catch (Exception e)
        {
            notice = T("取り込めませんでした: ", "Could not import: ") + e.Message;
        }
        RefreshSoon();
        return true;
    }

    void ExportCsv()
    {
        var dialog = new SaveFileDialog
        {
            Filter = "CSV (*.csv)|*.csv",
            FileName = "koebumi-dictionary.csv",
            DefaultExt = ".csv",
        };
        if (dialog.ShowDialog(Host) != true) return;
        try
        {
            File.WriteAllText(dialog.FileName, Services.Dictionary.ExportCsv(), new UTF8Encoding(false));
            notice = T("書き出しました: ", "Exported to ") + dialog.FileName;
        }
        catch (Exception e)
        {
            notice = T("書き出せませんでした: ", "Could not export: ") + e.Message;
        }
        RefreshSoon();
    }

    // ---- 追加と編集 ----

    void ShowAddDialog()
    {
        var dialog = new FormDialog(Host, T("新しい単語", "New word"), T("人名・製品名・略語など、正しく書いてほしい語を登録します。", "Add names, products or acronyms you want spelled exactly."), T("追加", "Add"));
        var (termHost, term) = TextInput("", T("単語またはフレーズ", "Word or phrase"));
        var (heardHost, heard) = TextInput("", T("例: クロードコード", "e.g. cloud code"));
        var warning = Label("", 12.5, K.Danger);
        warning.Visibility = Visibility.Collapsed;
        dialog.Body.Children.Add(FormDialog.Labeled(T("単語", "Word"), termHost));
        dialog.Body.Children.Add(FormDialog.Labeled(T("聞き取られ方（任意）", "Heard as (optional)"), heardHost,
            T("認識結果にこの表記が出てきたら、上の単語に置き換えます。カンマで区切って複数書けます。音声認識のヒントにも使います。",
              "When the transcript contains this, Koebumi replaces it with the word above. Separate several with commas. It is also given to speech recognition as a hint.")));
        dialog.Body.Children.Add(warning);
        dialog.Body.Children.Add(Label(T("CSV は 1 列目を単語、3 列目を聞き取られ方として読み込みます。", "CSV import reads the word from the first column and “heard as” from the third."), 12, K.TextTertiary));
        dialog.AddLeftButton(GhostBtn(T("CSV を取り込む…", "Import CSV…"), () =>
        {
            if (ImportCsv(dialog)) dialog.Close();
        }));
        dialog.CanOk = () => term.Text.Trim().Length > 0;
        term.TextChanged += (_, _) => dialog.Revalidate();
        dialog.Accept = () =>
        {
            var result = Services.Dictionary.Register(term.Text, [heard.Text]);
            switch (result.Kind)
            {
                case DictionaryStore.AddKind.Invalid:
                    warning.Text = T("単語は 1 文字以上、80 文字までです。", "A word must be 1 to 80 characters long.");
                    warning.Visibility = Visibility.Visible;
                    return false;
                case DictionaryStore.AddKind.Unchanged:
                    warning.Text = T("この単語と聞き取られ方は、もう登録してあります。", "This word and its “heard as” are already in the dictionary.");
                    warning.Visibility = Visibility.Visible;
                    return false;
                case DictionaryStore.AddKind.AddedHeard:
                    notice = T($"「{term.Text.Trim()}」はもう登録してあったので、聞き取られ方を足しました: {string.Join("、", result.Heard)}",
                               $"“{term.Text.Trim()}” was already in the dictionary. Added: {string.Join(", ", result.Heard)}");
                    break;
            }
            return true;
        };
        dialog.ContentRendered += (_, _) => term.Focus();
        dialog.ShowDialog();
    }

    void ShowEditDialog(DictionaryEntry entry)
    {
        var dialog = new FormDialog(Host, T("単語を編集", "Edit word"), null, T("保存", "Save"));
        var (termHost, term) = TextInput(entry.Term, T("単語またはフレーズ", "Word or phrase"));
        var (heardHost, heard) = TextInput(entry.Replaced ?? "", T("例: クロードコード", "e.g. cloud code"));
        dialog.Body.Children.Add(FormDialog.Labeled(T("単語", "Word"), termHost));
        dialog.Body.Children.Add(FormDialog.Labeled(T("聞き取られ方（任意）", "Heard as (optional)"), heardHost,
            T("認識結果にこの表記が出てきたら、上の単語に置き換えます。カンマで区切って複数書けます。",
              "When the transcript contains this, Koebumi replaces it with the word above. Separate several with commas.")));
        dialog.CanOk = () => term.Text.Trim().Length > 0;
        term.TextChanged += (_, _) => dialog.Revalidate();
        dialog.Accept = () =>
        {
            Services.Dictionary.Update(entry, term.Text, heard.Text);
            return true;
        };
        dialog.ContentRendered += (_, _) => { term.Focus(); term.SelectAll(); };
        dialog.ShowDialog();
    }
}
