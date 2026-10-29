using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using Koebumi.Core;
using Shapes = System.Windows.Shapes;

namespace Koebumi.App;

/// 設定の画面の部品を組み立てる関数。Mac 版の Theme.swift の Page・SettingsGroup・SettingRow などに当たる
internal static class SettingsUi
{
    public static readonly FontFamily IconFont = new("Segoe Fluent Icons, Segoe MDL2 Assets");

    // ---- 文字・色 ----

    public static T Brush<T>(this T element, DependencyProperty property, string key) where T : FrameworkElement
    {
        element.SetResourceReference(property, key);
        return element;
    }

    public static TextBlock Label(string text, double size = 14, string foreground = K.Text, FontWeight? weight = null, bool wrap = true)
    {
        var block = new TextBlock { Text = text, FontSize = size, TextWrapping = wrap ? TextWrapping.Wrap : TextWrapping.NoWrap };
        if (weight != null) block.FontWeight = weight.Value;
        block.SetResourceReference(TextBlock.ForegroundProperty, foreground);
        return block;
    }

    public static TextBlock Icon(string glyph, double size = 16, string foreground = K.TextSecondary)
    {
        var block = new TextBlock { Text = glyph, FontFamily = IconFont, FontSize = size, VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center };
        block.SetResourceReference(TextBlock.ForegroundProperty, foreground);
        return block;
    }

    // ---- 見出し・カード ----

    public static UIElement Header(string title, string? subtitle = null, UIElement? trailing = null)
    {
        var stack = new StackPanel();
        var line = new Grid();
        line.ColumnDefinitions.Add(new ColumnDefinition());
        line.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        line.Children.Add(Label(title, 28, K.Text, FontWeights.SemiBold, wrap: false));
        if (trailing != null)
        {
            Grid.SetColumn(trailing, 1);
            if (trailing is FrameworkElement fe) fe.VerticalAlignment = VerticalAlignment.Center;
            line.Children.Add(trailing);
        }
        stack.Children.Add(line);
        if (subtitle != null)
        {
            var sub = Label(subtitle, 14, K.TextSecondary);
            sub.Margin = new Thickness(0, 8, 0, 0);
            sub.LineHeight = 21;
            stack.Children.Add(sub);
        }
        return stack;
    }

    /// カードの外に置く小見出し（Mac 版の SectionLabel）
    public static UIElement Section(string title, string? subtitle = null, UIElement? trailing = null)
    {
        var grid = new Grid { Margin = new Thickness(4, 0, 0, 0) };
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var left = new StackPanel { VerticalAlignment = VerticalAlignment.Bottom };
        left.Children.Add(Label(title, 15, K.TextSecondary, FontWeights.SemiBold));
        if (subtitle != null)
        {
            var sub = Label(subtitle, 12.5, K.TextTertiary);
            sub.Margin = new Thickness(0, 4, 0, 0);
            left.Children.Add(sub);
        }
        grid.Children.Add(left);
        if (trailing != null)
        {
            Grid.SetColumn(trailing, 1);
            if (trailing is FrameworkElement fe) { fe.VerticalAlignment = VerticalAlignment.Bottom; fe.Margin = new Thickness(12, 0, 0, 0); }
            grid.Children.Add(trailing);
        }
        return grid;
    }

    /// 行を区切り線でつなげたもの（背景なし）
    public static StackPanel DividedStack(params UIElement?[] rows)
    {
        var stack = new StackPanel();
        foreach (var row in rows)
        {
            if (row == null) continue;
            if (stack.Children.Count > 0)
            {
                var line = new Border { Height = 1 }.Brush(Border.BackgroundProperty, K.Divider);
                stack.Children.Add(line);
            }
            stack.Children.Add(row);
        }
        return stack;
    }

    /// 行を区切り線でつなげた角丸のカード（Mac 版の SettingsGroup）
    public static Border Group(params UIElement?[] rows) =>
        new Border { CornerRadius = new CornerRadius(8), Child = DividedStack(rows), ClipToBounds = true }.Brush(Border.BackgroundProperty, K.Card);

    /// 設定の 1 行。左にタイトルと説明、右に操作
    public static Grid Row(string title, string? subtitle = null, UIElement? trailing = null, string? glyph = null, double minHeight = 56)
    {
        var grid = new Grid { MinHeight = minHeight };
        int column = 0;
        if (glyph != null)
        {
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(40) });
            var icon = Icon(glyph);
            icon.Margin = new Thickness(16, 0, 0, 0);
            grid.Children.Add(icon);
            column = 1;
        }
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(glyph == null ? 16 : 8, 12, 14, 12) };
        text.Children.Add(Label(title, 14, K.Text, FontWeights.Medium));
        if (subtitle != null)
        {
            var sub = Label(subtitle, 12.5, K.TextSecondary);
            sub.Margin = new Thickness(0, 3, 0, 0);
            text.Children.Add(sub);
        }
        Grid.SetColumn(text, column);
        grid.Children.Add(text);
        if (trailing != null)
        {
            Grid.SetColumn(trailing, column + 1);
            if (trailing is FrameworkElement fe)
            {
                fe.VerticalAlignment = VerticalAlignment.Center;
                fe.Margin = new Thickness(0, 8, 16, 8);
                if (fe is ComboBox && string.IsNullOrEmpty(System.Windows.Automation.AutomationProperties.GetName(fe)))
                    System.Windows.Automation.AutomationProperties.SetName(fe, title);
            }
            grid.Children.Add(trailing);
        }
        return grid;
    }

    /// 自由な中身を、行と同じ余白で置く
    public static Border Content(UIElement child) => new() { Child = child, Padding = new Thickness(16, 13, 16, 13) };

    /// カードの外に置く注記
    public static UIElement Footnote(string text, string? glyph = null)
    {
        var grid = new Grid { Margin = new Thickness(4, 0, 0, 0) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        if (glyph != null)
        {
            var icon = Icon(glyph, 12, K.TextTertiary);
            icon.Margin = new Thickness(0, 2, 8, 0);
            icon.VerticalAlignment = VerticalAlignment.Top;
            grid.Children.Add(icon);
        }
        var label = Label(text, 12, K.TextTertiary);
        label.LineHeight = 18;
        Grid.SetColumn(label, 1);
        grid.Children.Add(label);
        return grid;
    }

    /// 案内や警告を出す帯。色は使わず、左の丸に記号を置く（Mac 版の Callout）
    public static Border Callout(string glyph, string text, UIElement? trailing = null)
    {
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var badge = SymbolBadge(glyph, 22);
        badge.VerticalAlignment = VerticalAlignment.Center;
        grid.Children.Add(badge);
        var label = Label(text, 13.5, K.Text);
        label.Margin = new Thickness(10, 0, 10, 0);
        label.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(label, 1);
        grid.Children.Add(label);
        if (trailing != null)
        {
            Grid.SetColumn(trailing, 2);
            grid.Children.Add(trailing);
        }
        return new Border { CornerRadius = new CornerRadius(8), Padding = new Thickness(12, 10, 14, 10), Child = grid }.Brush(Border.BackgroundProperty, K.Card);
    }

    /// 白黒の丸に記号を置いた印
    public static Border SymbolBadge(string glyph, double size = 20)
    {
        var icon = Icon(glyph, size * 0.5, K.InverseText);
        return new Border { Width = size, Height = size, CornerRadius = new CornerRadius(size / 2), Child = icon }.Brush(Border.BackgroundProperty, K.Inverse);
    }

    public static UIElement EmptyState(string glyph, string title, string message)
    {
        var stack = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center, MaxWidth = 360, Margin = new Thickness(0, 40, 0, 40) };
        var tile = new Border { Width = 44, Height = 44, CornerRadius = new CornerRadius(10), HorizontalAlignment = HorizontalAlignment.Center, Child = Icon(glyph, 20) }.Brush(Border.BackgroundProperty, K.Hover);
        stack.Children.Add(tile);
        var heading = Label(title, 15, K.Text, FontWeights.Medium);
        heading.Margin = new Thickness(0, 12, 0, 0);
        heading.HorizontalAlignment = HorizontalAlignment.Center;
        stack.Children.Add(heading);
        var body = Label(message, 13, K.TextSecondary);
        body.Margin = new Thickness(0, 6, 0, 0);
        body.TextAlignment = TextAlignment.Center;
        stack.Children.Add(body);
        return new Border { CornerRadius = new CornerRadius(8), BorderThickness = new Thickness(1), Child = stack }.Brush(Border.BorderBrushProperty, K.Divider);
    }

    public static Border Badge(string text, string foreground = K.TextSecondary)
    {
        var label = Label(text, 11.5, foreground, FontWeights.Medium, wrap: false);
        return new Border { CornerRadius = new CornerRadius(4), Padding = new Thickness(7, 2, 7, 3), Child = label, VerticalAlignment = VerticalAlignment.Center }
            .Brush(Border.BackgroundProperty, K.Hover);
    }

    /// 例を見せる行（Mac 版の ExampleRow）
    public static Border Example(string label, string text)
    {
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(96) });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        var name = Label(label, 12, K.TextTertiary, FontWeights.Medium);
        name.VerticalAlignment = VerticalAlignment.Top;
        name.Margin = new Thickness(0, 1, 8, 0);
        grid.Children.Add(name);
        var value = Label(text, 13.5, K.Text);
        Grid.SetColumn(value, 1);
        grid.Children.Add(value);
        return Content(grid);
    }

    // ---- 部品 ----

    public static CheckBox Switch(bool isOn, Action<bool> changed, bool enabled = true)
    {
        var box = new CheckBox { IsChecked = isOn, IsEnabled = enabled };
        box.SetResourceReference(FrameworkElement.StyleProperty, "K.Switch");
        box.Checked += (_, _) => changed(true);
        box.Unchecked += (_, _) => changed(false);
        return box;
    }

    public static Grid ToggleRow(string title, string? subtitle, bool isOn, Action<bool> changed, bool enabled = true)
    {
        var toggle = Switch(isOn, changed, enabled);
        System.Windows.Automation.AutomationProperties.SetName(toggle, title);
        return Row(title, subtitle, toggle);
    }

    /// 選択肢のドロップダウン。選んだら changed を呼ぶ（最初の選択では呼ばない）
    public static ComboBox Combo<T>(IReadOnlyList<T> items, T selected, Func<T, string> title, Action<T> changed, double minWidth = 160)
    {
        var box = new ComboBox { MinWidth = minWidth, HorizontalContentAlignment = HorizontalAlignment.Left };
        foreach (var item in items) box.Items.Add(title(item));
        int index = -1;
        for (int i = 0; i < items.Count; i++)
        {
            if (EqualityComparer<T>.Default.Equals(items[i], selected)) { index = i; break; }
        }
        box.SelectedIndex = index;
        box.SelectionChanged += (_, _) =>
        {
            if (box.SelectedIndex >= 0 && box.SelectedIndex < items.Count) changed(items[box.SelectedIndex]);
        };
        return box;
    }

    public static Button Btn(string text, Action click, string? style = null, bool enabled = true)
    {
        var button = new Button { Content = text, MinHeight = 32, Padding = new Thickness(14, 0, 14, 0), IsEnabled = enabled };
        if (style != null) button.SetResourceReference(FrameworkElement.StyleProperty, style);
        button.Click += (_, _) => click();
        return button;
    }

    public static Button PrimaryBtn(string text, Action click, bool enabled = true) => Btn(text, click, "K.PrimaryButton", enabled);

    public static Button GhostBtn(string text, Action click, bool danger = false)
    {
        var button = Btn(text, click, "K.GhostButton");
        if (danger) button.SetResourceReference(Control.ForegroundProperty, K.Danger);
        return button;
    }

    public static Button IconBtn(string glyph, string tooltip, Action click, bool enabled = true, double size = 30)
    {
        var button = new Button { Content = Icon(glyph, 14, K.TextSecondary), Width = size, Height = size, MinHeight = 0, Padding = new Thickness(0), ToolTip = tooltip, IsEnabled = enabled };
        button.SetResourceReference(FrameworkElement.StyleProperty, "K.GhostButton");
        button.Click += (_, _) => click();
        System.Windows.Automation.AutomationProperties.SetName(button, tooltip);
        return button;
    }

    /// ヒント（入力欄が空のときに出る薄い文字）付きの入力欄。複数行にもできる
    public static (Grid Host, TextBox Box) TextInput(string text, string placeholder, bool multiline = false, double? width = null)
    {
        var box = new TextBox { Text = text };
        var hint = Label(placeholder, 14, K.TextTertiary, wrap: false);
        hint.IsHitTestVisible = false;
        hint.Margin = new Thickness(11, multiline ? 7 : 0, 8, 0);
        hint.VerticalAlignment = multiline ? VerticalAlignment.Top : VerticalAlignment.Center;
        hint.Visibility = text.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        if (multiline)
        {
            box.AcceptsReturn = true;
            box.TextWrapping = TextWrapping.Wrap;
            box.MinHeight = 140;
            box.VerticalScrollBarVisibility = ScrollBarVisibility.Auto;
            box.VerticalContentAlignment = VerticalAlignment.Top;
            box.Padding = new Thickness(8, 6, 8, 6);
        }
        else box.VerticalContentAlignment = VerticalAlignment.Center;
        box.TextChanged += (_, _) => hint.Visibility = box.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        var host = new Grid();
        if (width != null) host.Width = width.Value;
        host.Children.Add(box);
        host.Children.Add(hint);
        return (host, box);
    }

    /// キーの札（Mac 版の KeyCap）を並べたもの
    public static UIElement KeyCaps(Shortcut shortcut)
    {
        var panel = new StackPanel { Orientation = Orientation.Horizontal };
        foreach (var part in shortcut.Display.Split(" + "))
        {
            var cap = new Border
            {
                CornerRadius = new CornerRadius(4),
                BorderThickness = new Thickness(1),
                MinWidth = 24,
                Height = 24,
                Padding = new Thickness(7, 0, 7, 0),
                Margin = new Thickness(0, 0, 4, 0),
                Child = Label(part, 12, K.TextSecondary, FontWeights.Medium, wrap: false).Also(l => { l.VerticalAlignment = VerticalAlignment.Center; l.HorizontalAlignment = HorizontalAlignment.Center; }),
            }.Brush(Border.BackgroundProperty, K.Control).Brush(Border.BorderBrushProperty, K.ControlBorder);
            panel.Children.Add(cap);
        }
        return panel;
    }

    /// 選択の丸（Mac 版の RadioMark）
    public static UIElement RadioMark(bool on)
    {
        var grid = new Grid { Width = 18, Height = 18, VerticalAlignment = VerticalAlignment.Center };
        var ring = new Shapes.Ellipse { StrokeThickness = on ? 5 : 1.5, Margin = new Thickness(on ? 2.5 : 0.75) }
            .Brush(Shapes.Shape.StrokeProperty, on ? K.Inverse : K.ControlBorder);
        grid.Children.Add(ring);
        return grid;
    }

    /// 内容を差し替えずにそのまま返して、その場で設定を足す
    public static T Also<T>(this T value, Action<T> action)
    {
        action(value);
        return value;
    }

    /// マウスを重ねると薄く色が付く行にする
    public static Border Hoverable(UIElement child, Action? click = null)
    {
        var border = new Border { Child = child, Background = Brushes.Transparent, Cursor = click == null ? Cursors.Arrow : Cursors.Hand };
        border.MouseEnter += (_, _) => border.SetResourceReference(Border.BackgroundProperty, K.Hover);
        border.MouseLeave += (_, _) => border.Background = Brushes.Transparent;
        if (click != null)
        {
            border.MouseLeftButtonUp += (_, e) =>
            {
                if (e.OriginalSource is DependencyObject source && FindAncestor<System.Windows.Controls.Primitives.ButtonBase>(source) != null) return;
                click();
            };
        }
        return border;
    }

    public static T? FindAncestor<T>(DependencyObject? start) where T : DependencyObject
    {
        for (var d = start; d != null; d = d is Visual or System.Windows.Media.Media3D.Visual3D ? VisualTreeHelper.GetParent(d) : LogicalTreeHelper.GetParent(d))
        {
            if (d is T found) return found;
        }
        return default;
    }

}
