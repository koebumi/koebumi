using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using System.Windows.Threading;
using Koebumi.Core;
using Microsoft.Win32;
using static Koebumi.App.VoiceBarNative;
using ShapePath = System.Windows.Shapes.Path;

namespace Koebumi.App;

/// 録音中・処理中・知らせを出す、画面下の小さなバー。Mac 版の VoiceBar（UI/VoiceBar.swift）に当たる。
/// 前面の窓があるモニターの作業領域（タスクバーの上）の下中央に出す。入力先のアプリからフォーカスを奪わない
/// （ShowActivated = false と WS_EX_NOACTIVATE。フェーズ 0 で確かめた）。Mac 版と同じく、押すボタンはない
/// （確定はショートカット、取り消しは Esc）。UI スレッドで作る
public sealed class VoiceBar : Window, IDisposable
{
    /// 影のために、バーのまわりに空ける透明な余白（Mac 版の VoiceBarView.margin）
    const double ShadowMargin = 12;
    /// 作業領域の下端から、バーの下端までの距離
    const double BottomOffset = 28;
    /// バーの高さ（縁の 1 px ずつを含む）
    const double BarHeight = 42;

    readonly DictationController controller;
    readonly SettingsStore settings;
    readonly Border surface;
    readonly Border highlight;
    readonly Grid content;
    readonly StackPanel recordingRow;
    readonly StackPanel messageRow;
    readonly Badge modeBadge = new();
    readonly Badge messageBadge = new();
    readonly VoiceDots dots = new();
    readonly Border chip;
    readonly TextBlock chipArrow;
    readonly TextBlock chipText;
    readonly TextBlock elapsedText;
    readonly TextBlock messageText;
    readonly UIElement frame;

    bool shown;
    int hideVersion;
    bool rendering;
    long lastFrame;
    IntPtr monitor;
    bool dark;

    public VoiceBar(DictationController controller, SettingsStore settings)
    {
        this.controller = controller;
        this.settings = settings;

        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        Topmost = true;
        ShowInTaskbar = false;
        ShowActivated = false;
        ResizeMode = ResizeMode.NoResize;
        Focusable = false;
        SizeToContent = SizeToContent.WidthAndHeight;
        UseLayoutRounding = true;
        SnapsToDevicePixels = true;
        Title = "Koebumi";

        chipArrow = new TextBlock { Text = "→", FontSize = 10, FontWeight = FontWeights.Bold, VerticalAlignment = VerticalAlignment.Center };
        chipText = new TextBlock { FontSize = 10.5, FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(3, 0, 0, 0) };
        chip = new Border
        {
            Height = 22,
            CornerRadius = new CornerRadius(7),
            Padding = new Thickness(7, 0, 8, 0),
            Margin = new Thickness(10, 0, 0, 0),
            VerticalAlignment = VerticalAlignment.Center,
            Child = new StackPanel { Orientation = Orientation.Horizontal, Children = { chipArrow, chipText } },
            Visibility = Visibility.Collapsed,
        };
        elapsedText = new TextBlock
        {
            Width = 34,
            FontSize = 12,
            Margin = new Thickness(12, 0, 0, 0),
            VerticalAlignment = VerticalAlignment.Center,
        };
        dots.Margin = new Thickness(13, 0, 0, 0);
        // 左の丸から 7 の余白。録音中のバーと、知らせのバーで左の丸の位置をそろえる
        recordingRow = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Margin = new Thickness(7, 0, 16, 0),
            VerticalAlignment = VerticalAlignment.Center,
            Children = { modeBadge, dots, chip, elapsedText },
        };
        messageText = new TextBlock
        {
            FontSize = 13,
            FontWeight = FontWeights.Medium,
            MaxWidth = 420,
            MaxHeight = 54,
            LineHeight = 18,
            LineStackingStrategy = LineStackingStrategy.BlockLineHeight,
            TextWrapping = TextWrapping.Wrap,
            TextTrimming = TextTrimming.CharacterEllipsis,
            Margin = new Thickness(12, 0, 0, 0),
            VerticalAlignment = VerticalAlignment.Center,
        };
        messageRow = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Margin = new Thickness(7, 6, 18, 6),
            VerticalAlignment = VerticalAlignment.Center,
            Children = { messageBadge, messageText },
            Visibility = Visibility.Collapsed,
        };
        highlight = new Border { IsHitTestVisible = false };
        content = new Grid { MinHeight = BarHeight - 2, Children = { recordingRow, messageRow, highlight } };
        surface = new Border
        {
            BorderThickness = new Thickness(1),
            MinHeight = BarHeight,
            Child = content,
            Effect = new DropShadowEffect { BlurRadius = 10, ShadowDepth = 2, Direction = 270, Opacity = 0.28, Color = Colors.Black },
        };
        var host = new Border { Padding = new Thickness(ShadowMargin), Child = surface };
        frame = host;
        Content = host;

        // バーの高さに合わせて角を丸める。1 行ではカプセルになり、知らせが折り返して高くなっても角だけが丸い
        surface.SizeChanged += (_, e) =>
        {
            var radius = new CornerRadius(Math.Min(BarHeight / 2, e.NewSize.Height / 2));
            surface.CornerRadius = radius;
            highlight.CornerRadius = radius;
        };
        // 大きさが変わったら、下中央に置き直す（メッセージの長さ・モニターの DPI が変わるとき）。
        // SizeChanged の時点では、窓の実体の大きさがまだ変わっていないので、WPF の大きさから置き、実体が変わった後でもう一度置く
        SizeChanged += (_, _) => RepositionNowAndAfterLayout();
        DpiChanged += (_, _) => RepositionNowAndAfterLayout();
        SourceInitialized += (_, _) => MakeNonActivating();
        // 窓の実体を先に作っておく（見えないまま。出すときに、モニターへ移してから見せる）
        new WindowInteropHelper(this).EnsureHandle();

        controller.Changed += OnControllerChanged;
    }

    IntPtr Handle => new WindowInteropHelper(this).Handle;

    /// 入力先のアプリを前面のままにする窓にする: フォーカスを奪わず（NOACTIVATE）、Alt+Tab とタスクバーに出さず（TOOLWINDOW）、最前面（TOPMOST）
    void MakeNonActivating()
    {
        var hwnd = Handle;
        var style = GetWindowLongPtr(hwnd, GWL_EXSTYLE).ToInt64();
        SetWindowLongPtr(hwnd, GWL_EXSTYLE, new IntPtr(style | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST));
    }

    // MARK: - 状態

    void OnControllerChanged()
    {
        var phase = controller.Phase;
        if (phase.Kind == PhaseKind.Idle)
        {
            HideBar();
            return;
        }
        Apply(phase);
        if (!shown) ShowBar();
    }

    /// 状態に合わせて中身を替える。消えていく間は、消える前の中身のままにする
    void Apply(DictationPhase phase)
    {
        if (phase.Kind is PhaseKind.Recording or PhaseKind.Processing)
        {
            var processing = phase.Kind == PhaseKind.Processing;
            var translate = controller.Mode == Mode.Translate;
            recordingRow.Visibility = Visibility.Visible;
            messageRow.Visibility = Visibility.Collapsed;
            modeBadge.Show(translate ? Symbol.Globe : Symbol.Mic);
            // 翻訳では、訳す先の言語を出す
            chip.Visibility = translate ? Visibility.Visible : Visibility.Collapsed;
            if (translate)
            {
                var s = settings.Current;
                chipText.Text = Languages.ShortName(s.CurrentTranslationTarget, s.TranslationTargets);
                chip.ToolTip = Languages.Name(s.CurrentTranslationTarget);
            }
            // 処理中も場所は残して、バーの幅を変えない
            elapsedText.Visibility = processing ? Visibility.Hidden : Visibility.Visible;
            var seconds = (int)controller.Elapsed.TotalSeconds;
            elapsedText.Text = $"{seconds / 60}:{seconds % 60:00}";
            AutomationProperties.SetName(dots, processing ? ProcessingLabel : T("聞いています", "Listening"));
        }
        else
        {
            recordingRow.Visibility = Visibility.Collapsed;
            messageRow.Visibility = Visibility.Visible;
            messageBadge.Show(phase.IsError ? Symbol.Alert : Symbol.Check);
            messageText.Text = phase.Text;
        }
    }

    string ProcessingLabel => controller.Mode switch
    {
        Mode.Translate => T("翻訳しています…", "Translating…"),
        Mode.Ask => T("考えています…", "Thinking…"),
        _ => T("整えています…", "Polishing…"),
    };

    // MARK: - 出す・隠す

    void ShowBar()
    {
        shown = true;
        hideVersion++;
        ApplyTheme();
        monitor = PickMonitor();
        BeginAnimation(OpacityProperty, null);
        if (Visibility != Visibility.Visible)
        {
            Opacity = 0;
            // 先に出すモニターへ移す（モニターごとに DPI が違うので、大きさの確定はその後）
            Reposition();
            Show();
            StartFrames();
        }
        UpdateLayout();
        Reposition(fromWindowRect: true);
        Fade(1, 150);
    }

    void HideBar()
    {
        if (!shown) return;
        shown = false;
        var version = ++hideVersion;
        Fade(0, 200, () =>
        {
            // 消えている途中でまた出すことになったら（shown が true なら）隠さない
            if (shown || version != hideVersion) return;
            BeginAnimation(OpacityProperty, null);
            Opacity = 0;
            StopFrames();
            Hide();
        });
    }

    void Fade(double to, int milliseconds, Action? completed = null)
    {
        // 動きを減らす設定では、フェードしない
        if (!SystemParameters.ClientAreaAnimation)
        {
            BeginAnimation(OpacityProperty, null);
            Opacity = to;
            completed?.Invoke();
            return;
        }
        var animation = new DoubleAnimation(to, TimeSpan.FromMilliseconds(milliseconds));
        if (completed is not null) animation.Completed += (_, _) => completed();
        BeginAnimation(OpacityProperty, animation);
    }

    /// 出すときの前面の窓があるモニター。前面の窓がなければ（リモート デスクトップの切断中など）メインのモニター
    static IntPtr PickMonitor()
    {
        var foreground = Native.GetForegroundWindow();
        return foreground != IntPtr.Zero
            ? MonitorFromWindow(foreground, MONITOR_DEFAULTTONEAREST)
            : MonitorFromPoint(default, MONITOR_DEFAULTTOPRIMARY);
    }

    void RepositionNowAndAfterLayout()
    {
        Reposition();
        Dispatcher.BeginInvoke(DispatcherPriority.Loaded, new Action(() => Reposition(fromWindowRect: true)));
    }

    /// そのモニターの作業領域（タスクバーを除いた範囲）の下中央に置く。大きさは変えない。
    /// 位置は物理ピクセルで決める（DIP のまま置くと、DPI の違うモニターの間で位置がずれる）。
    /// 窓の大きさは、WPF の大きさ（ActualWidth・ActualHeight）から求める。fromWindowRect なら、窓の実体の大きさを読む
    void Reposition(bool fromWindowRect = false)
    {
        var hwnd = Handle;
        if (hwnd == IntPtr.Zero || monitor == IntPtr.Zero) return;
        var info = new MONITORINFO { Size = Marshal.SizeOf<MONITORINFO>() };
        if (!GetMonitorInfo(monitor, ref info) || !GetWindowRect(hwnd, out var rect)) return;
        double scale = 1;
        if (GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, out var dpi, out _) == 0 && dpi > 0) scale = dpi / 96.0;
        int width = rect.Width, height = rect.Height;
        if (!fromWindowRect && ActualWidth > 0 && ActualHeight > 0)
        {
            var own = VisualTreeHelper.GetDpi(this);
            width = (int)Math.Round(ActualWidth * own.DpiScaleX);
            height = (int)Math.Round(ActualHeight * own.DpiScaleY);
        }
        // 窓には影の余白（ShadowMargin）が含まれるので、その分だけ下げて、バーの下端が BottomOffset になるようにする
        var gap = (int)Math.Round((BottomOffset - ShadowMargin) * scale);
        var x = info.Work.Left + (info.Work.Width - width) / 2;
        var y = info.Work.Bottom - height - gap;
        SetWindowPos(hwnd, HWND_TOPMOST, x, y, 0, 0, SWP_NOSIZE | SWP_NOACTIVATE);
    }

    // MARK: - 動き（線の動きは出ている間だけ描く）

    void StartFrames()
    {
        if (rendering) return;
        rendering = true;
        lastFrame = Stopwatch.GetTimestamp();
        CompositionTarget.Rendering += OnFrame;
    }

    void StopFrames()
    {
        if (!rendering) return;
        rendering = false;
        CompositionTarget.Rendering -= OnFrame;
    }

    void OnFrame(object? sender, EventArgs e)
    {
        var now = Stopwatch.GetTimestamp();
        var dt = (now - lastFrame) / (double)Stopwatch.Frequency;
        lastFrame = now;
        if (recordingRow.Visibility != Visibility.Visible) return;
        dots.Advance(dt, controller.Level, controller.Phase.Kind == PhaseKind.Processing, !SystemParameters.ClientAreaAnimation);
    }

    // MARK: - 色（Mac 版 Theme.swift の Palette と、音声バーの白黒反転の配色）

    /// Koebumi の外観の設定（システム・ライト・ダーク）に従う。システムのときは Windows のアプリの色の設定
    bool UsesDark() => settings.Current.Appearance switch
    {
        Appearance.Dark => true,
        Appearance.Light => false,
        _ => SystemUsesDarkApps(),
    };

    static bool SystemUsesDarkApps()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            return key?.GetValue("AppsUseLightTheme") is 0;
        }
        catch (Exception)
        {
            return false;
        }
    }

    static Brush Solid(uint rgb, double alpha = 1)
    {
        var brush = new SolidColorBrush(Color.FromArgb((byte)Math.Round(alpha * 255), (byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb));
        brush.Freeze();
        return brush;
    }

    static Brush Vertical(Color top, Color bottom, double end = 1)
    {
        var brush = new LinearGradientBrush(top, bottom, new Point(0, 0), new Point(0, end));
        brush.Freeze();
        return brush;
    }

    void ApplyTheme()
    {
        dark = UsesDark();
        // ガラスの代わりに、後ろの画面が透けすぎない色で塗る（Windows には後ろをぼかす窓がない）
        surface.Background = dark ? Solid(0x2a2d35, 0.94) : Solid(0xeef4fb, 0.94);
        // 縁の細い光: 上は明るく、下は少し暗い
        surface.BorderBrush = dark
            ? Vertical(Color.FromArgb(0x57, 255, 255, 255), Color.FromArgb(0x1A, 255, 255, 255))
            : Vertical(Color.FromArgb(0xBF, 255, 255, 255), Color.FromArgb(0x14, 0, 0, 0));
        // 上半分のつや
        highlight.Background = Vertical(Color.FromArgb(dark ? (byte)0x0F : (byte)0x2E, 255, 255, 255), Color.FromArgb(0, 255, 255, 255), 0.5);
        var text = dark ? Solid(0xeceef0) : Solid(0x202428);
        var secondary = dark ? Solid(0xa0a5ad) : Solid(0x626970);
        messageText.Foreground = text;
        elapsedText.Foreground = secondary;
        chipText.Foreground = text;
        chipArrow.Foreground = secondary;
        chip.Background = dark ? Solid(0xffffff, 0.14) : Solid(0xffffff, 0.55);
        dots.Ink = dark ? Solid(0xffffff, 0.95) : Solid(0x0b0d12);
        // 左の丸は白黒を反転する（色は使わない）
        var disc = dark ? Solid(0xf4f4f5) : Solid(0x171717);
        var glyph = dark ? Solid(0x171717) : Solid(0xfafafa);
        modeBadge.Colors(disc, glyph);
        messageBadge.Colors(disc, glyph);
    }

    // MARK: - 試験・開発用

    /// いまの見た目を画像にする。backdrop は透明な部分に敷く色（確認用）。窓を出さずに描ける
    internal BitmapSource Snapshot(Color backdrop, double dpi = 192)
    {
        ApplyTheme();
        Apply(controller.Phase);
        dots.Settle(controller.Level, controller.Phase.Kind == PhaseKind.Processing);
        frame.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        var size = frame.DesiredSize;
        frame.Arrange(new Rect(size));
        frame.UpdateLayout();
        var visual = new DrawingVisual();
        using (var dc = visual.RenderOpen())
        {
            dc.DrawRectangle(new SolidColorBrush(backdrop), null, new Rect(size));
            dc.DrawRectangle(new VisualBrush(frame), null, new Rect(size));
        }
        var bitmap = new RenderTargetBitmap((int)Math.Ceiling(size.Width * dpi / 96), (int)Math.Ceiling(size.Height * dpi / 96), dpi, dpi, PixelFormats.Pbgra32);
        bitmap.Render(visual);
        return bitmap;
    }

    /// 出ている（透明になりきっていない）か
    internal bool IsShown => shown;

    /// 窓の位置と大きさ（物理ピクセル）と、置いたモニターの作業領域
    internal (RECT Window, RECT Work, double Scale)? Placement()
    {
        var hwnd = Handle;
        var info = new MONITORINFO { Size = Marshal.SizeOf<MONITORINFO>() };
        if (hwnd == IntPtr.Zero || monitor == IntPtr.Zero || !GetMonitorInfo(monitor, ref info) || !GetWindowRect(hwnd, out var rect)) return null;
        double scale = GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, out var dpi, out _) == 0 && dpi > 0 ? dpi / 96.0 : 1;
        return (rect, info.Work, scale);
    }

    internal long ExtendedStyle => GetWindowLongPtr(Handle, GWL_EXSTYLE).ToInt64();

    public void Dispose()
    {
        controller.Changed -= OnControllerChanged;
        StopFrames();
        BeginAnimation(OpacityProperty, null);
        Close();
    }

    // MARK: - 左の丸

    enum Symbol { Mic, Globe, Check, Alert }

    /// 白黒を反転した丸に、記号だけを置いたアイコン（Mac 版の SymbolBadge）。記号は 16 × 16 の線画で描く
    sealed class Badge : Grid
    {
        const double Size = 28;
        /// 丸の大きさに対する記号の大きさ（Mac 版は 0.52）
        const double GlyphScale = 0.52 * Size / 16;

        readonly Ellipse disc = new() { Width = Size, Height = Size };
        readonly Canvas icon = new()
        {
            Width = 16,
            Height = 16,
            RenderTransformOrigin = new Point(0.5, 0.5),
            RenderTransform = new ScaleTransform(GlyphScale, GlyphScale),
        };
        Brush glyph = Brushes.White;
        Symbol? symbol;

        public Badge()
        {
            Width = Height = Size;
            VerticalAlignment = VerticalAlignment.Center;
            Children.Add(disc);
            Children.Add(icon);
        }

        public void Colors(Brush fill, Brush glyphBrush)
        {
            disc.Fill = fill;
            glyph = glyphBrush;
            Rebuild();
        }

        public void Show(Symbol value)
        {
            if (symbol == value) return;
            symbol = value;
            Rebuild();
        }

        void Rebuild()
        {
            icon.Children.Clear();
            switch (symbol)
            {
                case Symbol.Mic:
                    Fill("M5.4,3.8 a2.6,2.6 0 0 1 5.2,0 v4.2 a2.6,2.6 0 0 1 -5.2,0 z");
                    Line("M3.4,7.4 a4.6,4.6 0 0 0 9.2,0 M8,12 v2.6 M5.6,14.6 h4.8", 1.5);
                    break;
                case Symbol.Globe:
                    Line("M14.2,8 a6.2,6.2 0 1 1 -12.4,0 a6.2,6.2 0 1 1 12.4,0 M8,1.8 a2.8,6.2 0 0 0 0,12.4 a2.8,6.2 0 0 0 0,-12.4 M1.8,8 h12.4", 1.4);
                    break;
                case Symbol.Check:
                    Line("M3.4,8.6 L6.6,11.8 L12.6,4.6", 1.9);
                    break;
                case Symbol.Alert:
                    Line("M8,3.2 V9", 2);
                    Fill("M6.85,12.3 a1.15,1.15 0 1 0 2.3,0 a1.15,1.15 0 1 0 -2.3,0");
                    break;
            }
        }

        void Fill(string data) => icon.Children.Add(new ShapePath { Data = Geometry.Parse(data), Fill = glyph });

        void Line(string data, double thickness) => icon.Children.Add(new ShapePath
        {
            Data = Geometry.Parse(data),
            Stroke = glyph,
            StrokeThickness = thickness,
            StrokeStartLineCap = PenLineCap.Round,
            StrokeEndLineCap = PenLineCap.Round,
            StrokeLineJoin = PenLineJoin.Round,
        });
    }
}
