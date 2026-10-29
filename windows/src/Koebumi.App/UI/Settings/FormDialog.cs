#pragma warning disable WPF0001 // ThemeMode は試験的な API
using System.Windows;
using System.Windows.Controls;
using static Koebumi.App.SettingsUi;

namespace Koebumi.App;

/// 設定の画面から開く入力用の小さな窓（辞書の単語・定型文の追加と編集）。Mac 版のシートに当たる。
/// 本文は Body に並べ、OK を押せるかは CanOk で決める（入力のたびに Revalidate を呼ぶ）
internal sealed class FormDialog : Window
{
    readonly Button ok;
    readonly StackPanel extra = new() { Orientation = Orientation.Horizontal };

    public StackPanel Body { get; } = new();
    public Func<bool>? CanOk { get; set; }
    /// OK を押したときに呼ぶ。false を返すと窓を閉じない
    public Func<bool>? Accept { get; set; }

    public FormDialog(SettingsWindow owner, string title, string? subtitle, string okText, double width = 480)
    {
        Owner = owner;
        ThemeMode = owner.ThemeMode;
        Title = title;
        Width = width;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        UseLayoutRounding = true;

        var layout = new StackPanel { Margin = new Thickness(26) };
        var heading = Label(title, 20, K.Text, FontWeights.SemiBold);
        layout.Children.Add(heading);
        if (subtitle != null)
        {
            var sub = Label(subtitle, 13, K.TextSecondary);
            sub.Margin = new Thickness(0, 8, 0, 0);
            layout.Children.Add(sub);
        }
        Body.Margin = new Thickness(0, 18, 0, 0);
        layout.Children.Add(Body);

        ok = PrimaryBtn(okText, OnAccept);
        ok.IsDefault = true;
        var cancel = Btn(T("キャンセル", "Cancel"), Close);
        cancel.IsCancel = true;
        cancel.Margin = new Thickness(0, 0, 8, 0);
        var buttons = new DockPanel { Margin = new Thickness(0, 10, 0, 0), LastChildFill = false };
        DockPanel.SetDock(extra, Dock.Left);
        buttons.Children.Add(extra);
        var right = new StackPanel { Orientation = Orientation.Horizontal };
        right.Children.Add(cancel);
        right.Children.Add(ok);
        DockPanel.SetDock(right, Dock.Right);
        buttons.Children.Add(right);
        layout.Children.Add(buttons);

        var root = new Grid();
        root.SetResourceReference(Panel.BackgroundProperty, K.Panel);
        root.Children.Add(layout);
        Content = root;
        SettingsTheme.Attach(root, owner.IsDark);
        SourceInitialized += (_, _) => SettingsNative.SetDarkTitleBar(new System.Windows.Interop.WindowInteropHelper(this).Handle, owner.IsDark);
        Loaded += (_, _) => Revalidate();
    }

    /// 左下に置くボタン（CSV を取り込む、など）
    public void AddLeftButton(Button button) => extra.Children.Add(button);

    /// 入力が変わったら呼ぶ。OK を押せるかを確かめ直す
    public void Revalidate() => ok.IsEnabled = CanOk?.Invoke() ?? true;

    void OnAccept()
    {
        if (Accept?.Invoke() ?? true) Close();
    }

    /// ラベル付きの入力欄 1 つ
    public static StackPanel Labeled(string label, UIElement input, string? note = null)
    {
        var stack = new StackPanel { Margin = new Thickness(0, 0, 0, 14) };
        var name = Label(label, 12.5, K.TextSecondary, FontWeights.Medium);
        name.Margin = new Thickness(0, 0, 0, 6);
        stack.Children.Add(name);
        stack.Children.Add(input);
        if (note != null)
        {
            var text = Label(note, 12, K.TextTertiary);
            text.Margin = new Thickness(0, 6, 0, 0);
            stack.Children.Add(text);
        }
        return stack;
    }
}
