#pragma warning disable WPF0001 // ThemeMode は試験的な API
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using Koebumi.Core;
using Microsoft.Win32;
using static Koebumi.App.SettingsUi;

namespace Koebumi.App;

/// 設定の画面。左の一覧で 7 つのページ（一般・ショートカット・音声認識・整形（AI）・スタイル・辞書・定型文）を切り替える。
/// 変えた設定はすぐに保存する（保存ボタンはない）。窓は 1 つだけ持ち、閉じても隠すだけなので、何度でも Show できる
/// （表示中なら前面に出す）。アプリを終えるときは Shutdown を呼ぶ
public sealed class SettingsWindow : Window
{
    readonly List<SettingsPage> pages;
    readonly Grid root = new();
    readonly ListBox nav = new();
    readonly TextBlock brand;
    readonly Border pane;
    SettingsPage? current;
    bool selfChange;
    bool allowClose;
    bool building;
    bool dark;

    internal AppServices Services { get; }
    internal HotkeyManager Hotkeys { get; }
    internal bool IsDark => dark;

    public SettingsWindow(AppServices services, HotkeyManager hotkeys)
    {
        Services = services;
        Hotkeys = hotkeys;
        Width = 900;
        Height = 640;
        MinWidth = 720;
        MinHeight = 480;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        UseLayoutRounding = true;
        SnapsToDevicePixels = true;

        pages = [new GeneralPage(this), new ShortcutsPage(this), new SpeechPage(this), new PolishPage(this), new StylePage(this), new DictionaryPage(this), new SnippetsPage(this)];

        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(224) });
        root.ColumnDefinitions.Add(new ColumnDefinition());
        root.SetResourceReference(Panel.BackgroundProperty, K.Shell);

        // 左: 名前と、ページの一覧
        var side = new DockPanel { Margin = new Thickness(12, 18, 6, 12) };
        brand = Label("Koebumi", 17, K.Text, FontWeights.SemiBold, wrap: false);
        brand.Margin = new Thickness(10, 0, 0, 14);
        DockPanel.SetDock(brand, Dock.Top);
        side.Children.Add(brand);
        nav.SetResourceReference(StyleProperty, "K.NavList");
        nav.SelectionChanged += (_, _) => { if (!building && nav.SelectedIndex >= 0) ShowPage(pages[nav.SelectedIndex]); };
        side.Children.Add(nav);
        root.Children.Add(side);

        // 右: ページ
        pane = new Border { CornerRadius = new CornerRadius(8), BorderThickness = new Thickness(1), Margin = new Thickness(0, 8, 8, 8), ClipToBounds = true };
        pane.SetResourceReference(Border.BackgroundProperty, K.Panel);
        pane.SetResourceReference(Border.BorderBrushProperty, K.PanelBorder);
        Grid.SetColumn(pane, 1);
        root.Children.Add(pane);
        Content = root;

        ThemeMode = ThemeMode.System;
        SettingsTheme.Attach(root, SettingsTheme.SystemIsDark());
        ApplyTheme(ThemeMode.System);
        RebuildNav();
        Title = WindowTitle();

        services.Settings.Changed += OnSettingsChanged;
        SystemEvents.UserPreferenceChanged += OnUserPreferenceChanged;
        Deactivated += (_, _) => { FlushPending(); Hotkeys.CancelCapture(); };
        IsVisibleChanged += (_, _) =>
        {
            if (IsVisible) return;
            FlushPending();
            Hotkeys.CancelCapture();
        };
        SourceInitialized += (_, _) => SettingsNative.SetDarkTitleBar(new WindowInteropHelper(this).Handle, dark);
    }

    /// 設定を開く。もう開いていれば、最小化を戻して前面に出す
    public new void Show()
    {
        if (!IsVisible)
        {
            base.Show();
            current?.Refresh();
        }
        if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal;
        Activate();
    }

    /// アプリを終えるとき。閉じる操作は窓を隠すだけなので、本当に閉じるにはこれを呼ぶ
    public void Shutdown()
    {
        allowClose = true;
        Close();
    }

    protected override void OnClosing(CancelEventArgs e)
    {
        if (!allowClose)
        {
            e.Cancel = true;
            Hide();
            return;
        }
        base.OnClosing(e);
    }

    protected override void OnClosed(EventArgs e)
    {
        Services.Settings.Changed -= OnSettingsChanged;
        SystemEvents.UserPreferenceChanged -= OnUserPreferenceChanged;
        Hotkeys.CancelCapture();
        base.OnClosed(e);
    }

    static string WindowTitle() => "Koebumi " + T("設定", "Settings");

    // ---- ページの切り替え ----

    /// 左の一覧を作り直す（表示言語を変えたときも）
    void RebuildNav()
    {
        building = true;
        int selected = current is { } page ? pages.IndexOf(page) : 0;
        nav.Items.Clear();
        foreach (var p in pages)
        {
            var row = new StackPanel { Orientation = Orientation.Horizontal };
            var icon = Icon(p.Glyph, 16, K.TextSecondary);
            icon.Width = 22;
            icon.TextAlignment = TextAlignment.Left;
            row.Children.Add(icon);
            var title = Label(p.Title, 14, K.Text, wrap: false);
            title.Margin = new Thickness(8, 0, 0, 0);
            // 選んだ行では文字の色を変えるので、色は行の指定に任せる
            title.ClearValue(TextBlock.ForegroundProperty);
            icon.ClearValue(TextBlock.ForegroundProperty);
            row.Children.Add(title);
            nav.Items.Add(new ListBoxItem { Content = row });
        }
        nav.SelectedIndex = selected;
        building = false;
        if (current == null) ShowPage(pages[selected]);
    }

    internal void ShowPage(SettingsPage page)
    {
        current?.FlushPending();
        Hotkeys.CancelCapture();
        current = page;
        page.Refresh();
        pane.Child = page.View;
        int index = pages.IndexOf(page);
        if (nav.SelectedIndex != index)
        {
            building = true;
            nav.SelectedIndex = index;
            building = false;
        }
        page.View.ScrollToTop();
    }

    internal void ShowPage(int index) => ShowPage(pages[index]);

    internal int PageCount => pages.Count;

    /// そのページを見せているか（ほかの場所から変わったデータを、見えているページだけ組み立て直すため）
    internal bool IsShowing(SettingsPage page) => IsVisible && current == page;

    void FlushPending() => current?.FlushPending();

    // ---- 設定 ----

    /// 設定を書き換えて保存する。表示言語が変わったら、画面全体の文字を入れ替える
    internal void Change(Action<AppSettings> change)
    {
        var before = L10n.Current;
        selfChange = true;
        try { Services.Settings.Update(change); }
        finally { selfChange = false; }
        if (L10n.Current != before) RebuildAll();
    }

    /// 自分の変更ではない（別の場所から設定が変わった）ときは、見えているページを組み立て直す
    void OnSettingsChanged(AppSettings _)
    {
        if (selfChange) return;
        RebuildAll();
    }

    void RebuildAll()
    {
        Title = WindowTitle();
        RebuildNav();
        current?.Refresh();
    }

    // ---- 外観 ----

    /// Fluent のテーマ（ライト・ダーク・システム）を選ぶ。色もそれに合わせる
    internal void ApplyTheme(ThemeMode mode)
    {
        ThemeMode = mode;
        dark = mode == ThemeMode.Dark || (mode != ThemeMode.Light && SettingsTheme.SystemIsDark());
        SettingsTheme.SetDark(root, dark);
        if (new WindowInteropHelper(this).Handle is var handle && handle != IntPtr.Zero) SettingsNative.SetDarkTitleBar(handle, dark);
    }

    void OnUserPreferenceChanged(object? sender, UserPreferenceChangedEventArgs e)
    {
        if (e.Category is not (UserPreferenceCategory.General or UserPreferenceCategory.Color or UserPreferenceCategory.VisualStyle)) return;
        Dispatcher.BeginInvoke(() =>
        {
            if (ThemeMode == ThemeMode.System) ApplyTheme(ThemeMode.System);
        });
    }
}

/// 設定の画面だけで使う Win32
internal static class SettingsNative
{
    const int DwmUseImmersiveDarkMode = 20;

    [DllImport("dwmapi.dll")]
    static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);

    /// タイトルバーをダークにする（Windows 10 の 2004 以降と Windows 11）。使えなければ何もしない
    public static void SetDarkTitleBar(IntPtr hwnd, bool dark)
    {
        if (hwnd == IntPtr.Zero) return;
        int value = dark ? 1 : 0;
        try { DwmSetWindowAttribute(hwnd, DwmUseImmersiveDarkMode, ref value, sizeof(int)); }
        catch (Exception) { }
    }
}
