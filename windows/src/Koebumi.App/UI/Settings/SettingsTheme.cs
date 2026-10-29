using System.Windows;
using System.Windows.Media;
using Microsoft.Win32;

namespace Koebumi.App;

/// 設定の画面の色のキー（DynamicResource で引く）
internal static class K
{
    public const string Shell = "K.Shell", Panel = "K.Panel", PanelBorder = "K.PanelBorder";
    public const string Card = "K.Card", Divider = "K.Divider";
    public const string Control = "K.Control", ControlBorder = "K.ControlBorder";
    public const string Hover = "K.Hover", Selection = "K.Selection";
    public const string Text = "K.Text", TextSecondary = "K.TextSecondary", TextTertiary = "K.TextTertiary", SidebarText = "K.SidebarText";
    public const string Inverse = "K.Inverse", InverseText = "K.InverseText";
    public const string SwitchOff = "K.SwitchOff";
    public const string Danger = "K.Danger";
}

/// 色と部品の見た目。色は Mac 版の Theme.swift の Palette（ライトとダーク）を写し、
/// ボタン・入力欄・ドロップダウンなどの部品は .NET の Fluent テーマ（ThemeMode）に任せる。
/// 色は窓の中身の根（Attach した要素）の Resources に置くので、ThemeMode が窓の Resources を組み替えても消えない
internal static class SettingsTheme
{
    // キー、ライト、ダーク、（透明度の指定があるものは ライトの透明度、ダークの透明度）
    static readonly (string Key, uint Light, uint Dark, double LightAlpha, double DarkAlpha)[] Colors =
    [
        (K.Shell, 0xf5f6f8, 0x151618, 1, 1),
        (K.Panel, 0xffffff, 0x1b1c1f, 1, 1),
        (K.PanelBorder, 0xe3e5e9, 0x2a2c31, 1, 1),
        (K.Card, 0xf5f6f8, 0x232428, 1, 1),
        (K.Divider, 0xe9ebee, 0x2d2f34, 1, 1),
        (K.Control, 0xffffff, 0x2a2b2f, 1, 1),
        (K.ControlBorder, 0xdde0e5, 0x3a3c42, 1, 1),
        (K.Hover, 0x0b0f19, 0xffffff, 0.045, 0.055),
        (K.Selection, 0x0b0f19, 0xffffff, 0.075, 0.1),
        (K.Text, 0x202428, 0xeceef0, 1, 1),
        (K.TextSecondary, 0x626970, 0xa0a5ad, 1, 1),
        (K.TextTertiary, 0x9aa1a9, 0x6c717a, 1, 1),
        (K.SidebarText, 0x41464c, 0xc9ccd2, 1, 1),
        // アクセントは色を使わず、白黒を反転させる（Mac 版と同じ）
        (K.Inverse, 0x171717, 0xf4f4f5, 1, 1),
        (K.InverseText, 0xfafafa, 0x171717, 1, 1),
        (K.SwitchOff, 0xd3d7dd, 0x3a3d43, 1, 1),
        (K.Danger, 0xdc2626, 0xf87171, 1, 1),
    ];

    static ResourceDictionary Palette(bool dark)
    {
        var dict = new ResourceDictionary();
        foreach (var (key, light, darkHex, la, da) in Colors)
        {
            dict[key] = Solid(dark ? darkHex : light, dark ? da : la);
        }
        return dict;
    }

    /// 0xRRGGBB と透明度（0〜1）から、固定した単色のブラシを作る
    public static SolidColorBrush Solid(uint rgb, double alpha = 1)
    {
        var brush = new SolidColorBrush(Color.FromArgb((byte)Math.Round(alpha * 255), (byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb));
        brush.Freeze();
        return brush;
    }

    static ResourceDictionary Styles() =>
        new() { Source = new Uri("/Koebumi.App;component/UI/Settings/SettingsStyles.xaml", UriKind.Relative) };

    /// 窓（ダイアログ）の中身の根に、部品の見た目と色を付ける
    public static void Attach(FrameworkElement root, bool dark)
    {
        root.Resources.MergedDictionaries.Add(Styles());
        root.Resources.MergedDictionaries.Add(Palette(dark));
    }

    /// ライトとダークを切り替える（色だけを差し替える。DynamicResource の参照が自動で変わる）
    public static void SetDark(FrameworkElement root, bool dark)
    {
        var merged = root.Resources.MergedDictionaries;
        merged[^1] = Palette(dark);
    }

    /// Windows のアプリの配色がダークか
    public static bool SystemIsDark()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            return key?.GetValue("AppsUseLightTheme") is int light && light == 0;
        }
        catch (Exception)
        {
            return false;
        }
    }
}
