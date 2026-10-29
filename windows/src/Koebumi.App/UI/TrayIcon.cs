using Drawing = System.Drawing;
using Forms = System.Windows.Forms;

namespace Koebumi.App;

/// タスクトレイのアイコン。右クリックのメニューは「設定…」と「終了」。UI スレッドで作る。
/// WPF にトレイのアイコンはないので、WinForms の NotifyIcon を使う（WinForms の型はこのファイルに閉じ込める）
public sealed class TrayIcon : IDisposable
{
    readonly Forms.NotifyIcon notifyIcon;
    readonly Forms.ContextMenuStrip menu;
    readonly Drawing.Icon image;

    public event Action? SettingsRequested;
    public event Action? ExitRequested;

    public TrayIcon()
    {
        image = Render(Forms.SystemInformation.SmallIconSize.Width);
        menu = new Forms.ContextMenuStrip { Font = Drawing.SystemFonts.MenuFont };
        menu.Items.Add("設定…", null, (_, _) => SettingsRequested?.Invoke());
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("終了", null, (_, _) => ExitRequested?.Invoke());
        notifyIcon = new Forms.NotifyIcon { Icon = image, Text = "Koebumi", ContextMenuStrip = menu, Visible = true };
        notifyIcon.DoubleClick += (_, _) => SettingsRequested?.Invoke();
    }

    /// 吹き出しで知らせる（ショートカットを使えないときなど）
    public void ShowNotification(string title, string message) =>
        notifyIcon.ShowBalloonTip(5000, title, message, Forms.ToolTipIcon.Info);

    public void Dispose()
    {
        notifyIcon.Visible = false;
        notifyIcon.Dispose();
        menu.Dispose();
        image.Dispose();
    }

    /// 暗い角丸の四角に、白いマイク。size は 16〜32 くらいのピクセル数
    static Drawing.Icon Render(int size)
    {
        size = Math.Max(size, 16);
        using var bitmap = new Drawing.Bitmap(size, size, Drawing.Imaging.PixelFormat.Format32bppArgb);
        using (var g = Drawing.Graphics.FromImage(bitmap))
        {
            g.SmoothingMode = Drawing.Drawing2D.SmoothingMode.AntiAlias;
            g.Clear(Drawing.Color.Transparent);
            float u = size / 32f;

            using (var background = new Drawing.SolidBrush(Drawing.Color.FromArgb(0x1F, 0x23, 0x2A)))
            using (var square = RoundedRectangle(0, 0, size, size, 7 * u))
                g.FillPath(background, square);

            var white = Drawing.Color.FromArgb(0xF2, 0xF4, 0xF7);
            using (var fill = new Drawing.SolidBrush(white))
            using (var body = RoundedRectangle(12 * u, 5 * u, 8 * u, 13 * u, 4 * u))
                g.FillPath(fill, body);

            using var pen = new Drawing.Pen(white, Math.Max(1.5f * u, 1f)) { StartCap = Drawing.Drawing2D.LineCap.Round, EndCap = Drawing.Drawing2D.LineCap.Round };
            // 本体を抱える U 字と、脚、台
            g.DrawArc(pen, 8.5f * u, 9f * u, 15f * u, 14f * u, 0, 180);
            g.DrawLine(pen, 16 * u, 23 * u, 16 * u, 26.5f * u);
            g.DrawLine(pen, 11.5f * u, 26.5f * u, 20.5f * u, 26.5f * u);
        }
        var handle = bitmap.GetHicon();
        try
        {
            // GetHicon のハンドルは自分で壊す。Icon には複製を持たせる
            using var temporary = Drawing.Icon.FromHandle(handle);
            return (Drawing.Icon)temporary.Clone();
        }
        finally { Native.DestroyIcon(handle); }
    }

    static Drawing.Drawing2D.GraphicsPath RoundedRectangle(float x, float y, float width, float height, float radius)
    {
        float d = Math.Min(radius * 2, Math.Min(width, height));
        var path = new Drawing.Drawing2D.GraphicsPath();
        path.AddArc(x, y, d, d, 180, 90);
        path.AddArc(x + width - d, y, d, d, 270, 90);
        path.AddArc(x + width - d, y + height - d, d, d, 0, 90);
        path.AddArc(x, y + height - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }
}
