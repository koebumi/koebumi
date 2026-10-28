using System.Windows;
using System.Windows.Controls;
using Koebumi.Core;
using Shapes = System.Windows.Shapes;
using static Koebumi.App.SettingsUi;

namespace Koebumi.App;

/// ショートカット: 操作ごとのショートカットの一覧、追加（キーを押して記録）、削除、既定に戻す
internal sealed class ShortcutsPage : SettingsPage
{
    /// 記録中の操作と、置き換える位置（null は追加）
    (ShortcutAction Action, int? Index)? capturing;
    /// 記録を始めるたびに増やす。古い記録の結果が、新しい記録の表示を消さないようにする
    int token;
    (ShortcutAction Action, string Text)? message;

    public ShortcutsPage(SettingsWindow host) : base(host) { }

    public override string Title => T("ショートカット", "Shortcuts");
    public override string Glyph => "\uE765";

    protected override void Build()
    {
        AddHeader(T("ショートカットをクリックすると変更できます。1 つの操作に複数のショートカットを登録できます。", "Click a shortcut to change it. Each action can have several shortcuts."));

        if (!Host.Hotkeys.IsRunning)
        {
            Add(Callout("\uE783", T("ショートカットを使えません（キーボードのフックを付けられませんでした）", "Shortcuts are unavailable (the keyboard hook could not be installed)"),
                Btn(T("再試行", "Retry"), () => { Host.Hotkeys.Restart(); RefreshSoon(); })), 20);
        }

        Add(Group([.. ShortcutRules.All.Select(ActionBlock)]), 20);

        var esc = new Shortcut([], KeyNames.Escape);
        Add(Group(
            Row(T("キャンセル", "Cancel"), T("録音・処理を止めます", "Stops recording or processing"), KeyCaps(esc), "\uE711"),
            Row(T("ハンズフリーとプッシュトゥトーク", "Hands-free and push-to-talk"),
                T("ディクテーションのキーは、短く押すとハンズフリー（もう一度押して確定）、押し続けると離したときに確定します。押し続けている途中で Shift や Space を足すと翻訳・Ask に切り替わります。",
                  "Tap the Dictate key for hands-free (press again to finish), or hold it and release to finish. While holding, add Shift or Space to switch to Translate or Ask."),
                null, "\uE7C9")), 18);
    }

    /// 1 つの操作の行: タイトルと説明、ショートカットの札、追加、既定に戻す
    UIElement ActionBlock(ShortcutAction action)
    {
        var list = ShortcutRules.Get(S, action);
        var grid = new Grid { Margin = new Thickness(0, 0, 0, 0) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(40) });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var icon = Icon(ShortcutRules.Glyph(action));
        icon.VerticalAlignment = VerticalAlignment.Top;
        icon.Margin = new Thickness(16, 16, 0, 0);
        grid.Children.Add(icon);

        var column = new StackPanel { Margin = new Thickness(8, 12, 8, 14) };
        column.Children.Add(Label(ShortcutRules.Title(action), 14, K.Text, FontWeights.Medium));
        var description = Label(ShortcutRules.Description(action), 12.5, K.TextSecondary);
        description.Margin = new Thickness(0, 3, 0, 0);
        column.Children.Add(description);

        var chips = new WrapPanel { Margin = new Thickness(0, 10, 0, 0) };
        for (int i = 0; i < list.Count; i++)
        {
            int index = i;
            chips.Children.Add(capturing is { } c && c.Action == action && c.Index == index
                ? RecordingChip()
                : Chip(list[i], () => StartCapture(action, index), CanRemove(action, list.Count) ? () => Remove(action, index) : null));
        }
        if (capturing is { } adding && adding.Action == action && adding.Index == null) chips.Children.Add(RecordingChip());
        else
        {
            var add = Btn("＋ " + T("追加", "Add"), () => StartCapture(action, null));
            add.MinHeight = 30;
            add.Margin = new Thickness(list.Count == 0 ? -8 : 0, 0, 0, 6);
            add.SetResourceReference(FrameworkElement.StyleProperty, "K.GhostButton");
            chips.Children.Add(add);
        }
        column.Children.Add(chips);

        if (capturing is { } active && active.Action == action)
        {
            column.Children.Add(Label(T("キーを押してください。押したキーをすべて離すと登録します。Esc だけを押すと取り消します。",
                "Press the keys. They are registered when you release them all. Press Esc alone to cancel."), 12.5, K.TextSecondary));
        }
        if (message is { } m && m.Action == action)
        {
            var text = Label(m.Text, 12.5, K.Danger);
            text.Margin = new Thickness(0, 2, 0, 0);
            column.Children.Add(text);
        }
        Grid.SetColumn(column, 1);
        grid.Children.Add(column);

        bool isDefault = list.Count == 1 && list[0].Equals(ShortcutRules.Default(action));
        var reset = IconBtn("\uE777", T("既定に戻す", "Reset to default"), () => Reset(action), enabled: !isDefault);
        reset.VerticalAlignment = VerticalAlignment.Top;
        reset.Margin = new Thickness(0, 10, 12, 0);
        Grid.SetColumn(reset, 2);
        grid.Children.Add(reset);
        return grid;
    }

    /// 録音の操作は 1 つ残す。貼り付けと取り消しは、すべて消して使わないようにできる
    static bool CanRemove(ShortcutAction action, int count) => count > 1 || ShortcutRules.CanBeEmpty(action);

    /// 登録済みのショートカットの札。押すと録り直し、右の「×」で消す
    UIElement Chip(Shortcut shortcut, Action change, Action? remove)
    {
        var inner = new StackPanel { Orientation = Orientation.Horizontal };
        var button = new Button { Content = KeyCaps(shortcut), Padding = new Thickness(6, 0, 2, 0), MinHeight = 30, ToolTip = T("クリックして変更", "Click to change") };
        button.SetResourceReference(FrameworkElement.StyleProperty, "K.GhostButton");
        button.Click += (_, _) => change();
        inner.Children.Add(button);
        if (remove != null)
        {
            var x = IconBtn("\uE711", T("削除", "Remove"), remove, size: 24);
            x.Margin = new Thickness(0, 0, 2, 0);
            inner.Children.Add(x);
        }
        return new Border { CornerRadius = new CornerRadius(6), BorderThickness = new Thickness(1), Margin = new Thickness(0, 0, 8, 6), Child = inner }
            .Brush(Border.BorderBrushProperty, K.ControlBorder);
    }

    UIElement RecordingChip()
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        var dot = new Shapes.Ellipse { Width = 8, Height = 8, Margin = new Thickness(0, 0, 8, 0), VerticalAlignment = VerticalAlignment.Center }.Brush(Shapes.Shape.FillProperty, K.Inverse);
        row.Children.Add(dot);
        row.Children.Add(Label(T("キーを押す…", "Press keys…"), 13, K.Text, FontWeights.Medium, wrap: false));
        return new Border { CornerRadius = new CornerRadius(6), BorderThickness = new Thickness(1), Height = 32, Padding = new Thickness(12, 0, 14, 0), Margin = new Thickness(0, 0, 8, 6), Child = row }
            .Brush(Border.BackgroundProperty, K.Hover).Brush(Border.BorderBrushProperty, K.Inverse);
    }

    // ---- 操作 ----

    void StartCapture(ShortcutAction action, int? index)
    {
        int mine = ++token;
        capturing = (action, index);
        message = null;
        Host.Hotkeys.CaptureNext(shortcut =>
        {
            if (mine != token) return;
            capturing = null;
            if (shortcut != null) Register(action, index, shortcut);
            RefreshSoon();
        });
        RefreshSoon();
    }

    /// 記録したキーを検査して、よければ登録する
    internal void Register(ShortcutAction action, int? index, Shortcut shortcut)
    {
        var list = ShortcutRules.Get(S, action);
        Shortcut? replacing = index is { } i && i < list.Count ? list[i] : null;
        if (ShortcutRules.Validate(S, action, shortcut, replacing) is { } error)
        {
            message = (action, error);
            return;
        }
        message = null;
        Update(x =>
        {
            var target = ShortcutRules.Get(x, action);
            if (replacing != null && index is { } at && at < target.Count) target[at] = shortcut;
            else target.Add(shortcut);
        });
    }

    void Remove(ShortcutAction action, int index)
    {
        message = null;
        Update(x =>
        {
            var target = ShortcutRules.Get(x, action);
            if (index < target.Count) target.RemoveAt(index);
        });
        RefreshSoon();
    }

    void Reset(ShortcutAction action)
    {
        var standard = ShortcutRules.Default(action);
        // ほかの操作が、既定と同じキーを使っていたら戻せない
        var others = new AppSettings();
        foreach (var a in ShortcutRules.All) ShortcutRules.Set(others, a, a == action ? [] : [.. ShortcutRules.Get(S, a)]);
        if (ShortcutRules.Validate(others, action, standard, null) is { } error)
        {
            message = (action, error);
            RefreshSoon();
            return;
        }
        message = null;
        Update(x => ShortcutRules.Set(x, action, [standard]));
        RefreshSoon();
    }
}
