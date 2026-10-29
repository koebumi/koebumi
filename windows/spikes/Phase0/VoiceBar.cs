using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Shapes;
using static Koebumi.Phase0.Native;

namespace Koebumi.Phase0;

/// 音声バーの試作。最前面に出し、入力先のアプリからフォーカスを奪わない透明な窓
sealed class VoiceBar : Window
{
    public enum BarStyle
    {
        /// ShowActivated = false と WS_EX_NOACTIVATE（案）
        NoActivate,
        /// ShowActivated = false だけ
        ShowNotActivated,
        /// WPF の既定（Show で窓をアクティブにする）
        Default,
    }

    readonly Rectangle level;
    readonly TextBlock label;
    public readonly Button CancelButton;
    public int CancelClicks;

    public VoiceBar(BarStyle style)
    {
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        Topmost = true;
        ShowInTaskbar = false;
        ResizeMode = ResizeMode.NoResize;
        ShowActivated = style == BarStyle.Default;
        Width = 280;
        Height = 52;
        Focusable = false;

        level = new Rectangle { Width = 6, Height = 18, Fill = Brushes.White, RadiusX = 3, RadiusY = 3, VerticalAlignment = VerticalAlignment.Center };
        label = new TextBlock { Text = "録音中", Foreground = Brushes.White, FontSize = 14, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(12, 0, 12, 0) };
        CancelButton = new Button { Content = "×", Width = 28, Height = 28, Focusable = false, VerticalAlignment = VerticalAlignment.Center };
        CancelButton.Click += (_, _) => CancelClicks++;
        var row = new DockPanel { Margin = new Thickness(16, 0, 10, 0), LastChildFill = false };
        row.Children.Add(level);
        row.Children.Add(label);
        DockPanel.SetDock(CancelButton, Dock.Right);
        row.Children.Add(CancelButton);
        Content = new Border
        {
            CornerRadius = new CornerRadius(14),
            Background = new SolidColorBrush(Color.FromArgb(0xE6, 0x1F, 0x23, 0x2A)),
            Child = row,
        };

        var area = SystemParameters.WorkArea;
        Left = area.Left + (area.Width - Width) / 2;
        Top = area.Bottom - Height - 24;

        if (style == BarStyle.NoActivate)
        {
            SourceInitialized += (_, _) =>
            {
                var hwnd = new WindowInteropHelper(this).Handle;
                var ex = GetWindowLongPtr(hwnd, GWL_EXSTYLE).ToInt64();
                SetWindowLongPtr(hwnd, GWL_EXSTYLE, new IntPtr(ex | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST));
            };
        }
    }

    public IntPtr Handle => new WindowInteropHelper(this).Handle;

    public void SetLevel(double v) => level.Height = 6 + 30 * Math.Clamp(v, 0, 1);

    public void SetText(string text) => label.Text = text;

    /// 画面上の「×」の中心（物理ピクセル）
    public (int X, int Y) CancelButtonCenter()
    {
        var p = CancelButton.PointToScreen(new Point(CancelButton.ActualWidth / 2, CancelButton.ActualHeight / 2));
        return ((int)p.X, (int)p.Y);
    }
}
