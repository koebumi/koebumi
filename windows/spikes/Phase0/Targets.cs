using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using Interop.UIAutomationClient;
using static Koebumi.Phase0.Native;

namespace Koebumi.Phase0;

/// 試験に使うアプリを開き、終わったら閉じる。ふだん使っているデータには触れない
static class Targets
{
    public static readonly string Dir = Path.Combine(Path.GetTempPath(), "koebumi-phase0");

    static Targets() => Directory.CreateDirectory(Dir);

    public static string PagePath => Path.Combine(AppContext.BaseDirectory, "testpage.html");
}

interface ITarget : IDisposable
{
    string Name { get; }
    IntPtr Hwnd { get; }
    /// 入力欄の UI Automation の要素
    IUIAutomationElement? Field(Uia uia);
}

/// メモ帳。一時ファイルを開き、終わったら保存せずにタブを閉じる。
/// メモ帳の窓は閉じない（閉じて開き直したとき、読めないファイルのタブが前回のセッションから消えたことがあった）
sealed class NotepadTarget : ITarget
{
    public string Name => "メモ帳";
    public IntPtr Hwnd { get; }
    readonly string path;

    public NotepadTarget(string content)
    {
        path = Path.Combine(Targets.Dir, $"notepad-{DateTime.Now:HHmmssfff}.txt");
        File.WriteAllText(path, content);
        Process.Start(new ProcessStartInfo("notepad.exe", $"\"{path}\"") { UseShellExecute = true });
        var file = Path.GetFileName(path);
        Hwnd = Desktop.WaitForWindow(w => w.Process.Equals("Notepad.exe", StringComparison.OrdinalIgnoreCase) && w.Title.Contains(Path.GetFileNameWithoutExtension(file)), 8000);
        Thread.Sleep(600);
    }

    public IUIAutomationElement? Field(Uia uia) => Hwnd == IntPtr.Zero ? null :
        uia.Find(Hwnd, e => e.CurrentControlType is UIA_ControlTypeIds.UIA_DocumentControlTypeId or UIA_ControlTypeIds.UIA_EditControlTypeId
                            && e.GetCurrentPattern(UIA_PatternIds.UIA_TextPatternId) != null);

    public void Dispose()
    {
        if (Hwnd == IntPtr.Zero) return;
        // タブの「閉じる」を押す。変更があると保存の確認が出るので、試験の後は元の内容に戻してから閉じる
        try
        {
            var uia = new Uia();
            var name = Path.GetFileNameWithoutExtension(path);
            var tab = uia.Find(Hwnd, e => e.CurrentControlType == UIA_ControlTypeIds.UIA_TabItemControlTypeId && e.CurrentName.Contains(name));
            var close = tab?.FindFirst(TreeScope.TreeScope_Descendants, uia.A.CreatePropertyCondition(UIA_PropertyIds.UIA_ControlTypePropertyId, UIA_ControlTypeIds.UIA_ButtonControlTypeId));
            if (close?.GetCurrentPattern(UIA_PatternIds.UIA_InvokePatternId) is IUIAutomationInvokePattern invoke) invoke.Invoke();
            Thread.Sleep(500);
            // 保存の確認が出たら「保存しない」
            var dontSave = uia.Find(Hwnd, e => e.CurrentControlType == UIA_ControlTypeIds.UIA_ButtonControlTypeId && (e.CurrentName.Contains("保存しない") || e.CurrentName.Contains("Don't save")));
            if (dontSave?.GetCurrentPattern(UIA_PatternIds.UIA_InvokePatternId) is IUIAutomationInvokePattern no) no.Invoke();
        }
        catch { }
        try { File.Delete(path); } catch { }
    }
}

/// Word。COM で新しい文書を作り、終わったら保存せずに閉じる
sealed class WordTarget : ITarget
{
    public string Name => "Word";
    public IntPtr Hwnd { get; private set; }
    readonly dynamic? app;
    readonly dynamic? doc;
    readonly bool startedApp;

    public WordTarget(string content, int caret)
    {
        startedApp = Process.GetProcessesByName("WINWORD").Length == 0;
        var type = Type.GetTypeFromProgID("Word.Application") ?? throw new InvalidOperationException("Word がない");
        app = Activator.CreateInstance(type)!;
        app.Visible = true;
        doc = app.Documents.Add();
        doc.Content.Text = content;
        doc.Range(caret, caret).Select();
        doc.Activate();
        try { Hwnd = new IntPtr((int)app.ActiveWindow.Hwnd); } catch { }
        if (Hwnd == IntPtr.Zero) Hwnd = Desktop.WaitForWindow(w => w.Process.Equals("WINWORD.EXE", StringComparison.OrdinalIgnoreCase), 8000);
        Thread.Sleep(800);
    }

    public string Text
    {
        get => (string)doc!.Content.Text;
        set => doc!.Content.Text = value;
    }

    public IUIAutomationElement? Field(Uia uia) => Hwnd == IntPtr.Zero ? null :
        uia.Find(Hwnd, e => e.CurrentControlType == UIA_ControlTypeIds.UIA_DocumentControlTypeId && e.GetCurrentPattern(UIA_PatternIds.UIA_TextPatternId) != null);

    public void Dispose()
    {
        try { doc?.Close(0 /* wdDoNotSaveChanges */); } catch { }
        try { if (startedApp) app?.Quit(0); } catch { }
    }
}

/// Chrome・Edge。一時のプロファイルで試験用のページを開き、終わったらそのブラウザーだけを終わらせる
sealed class BrowserTarget : ITarget
{
    public string Name { get; }
    public IntPtr Hwnd { get; }
    readonly Process? process;
    readonly string exe;

    public static readonly string ChromePath = @"C:\Program Files\Google\Chrome\Application\chrome.exe";
    public static readonly string EdgePath = @"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe";

    public BrowserTarget(string name, string path, string query)
    {
        Name = name;
        exe = Path.GetFileName(path);
        var profile = Path.Combine(Targets.Dir, $"{name.ToLowerInvariant()}-profile");
        var url = new Uri(Targets.PagePath).AbsoluteUri + "?" + query;
        var args = $"--user-data-dir=\"{profile}\" --no-first-run --no-default-browser-check --disable-sync --new-window \"{url}\"";
        process = Process.Start(new ProcessStartInfo(path, args) { UseShellExecute = false });
        Hwnd = Desktop.WaitForWindow(w => w.Process.Equals(exe, StringComparison.OrdinalIgnoreCase) && w.Title.Contains("Koebumi phase0"), 15000);
        Thread.Sleep(1200);
    }

    /// Chromium は UI Automation のクライアントが来てからアクセシビリティの木を作るので、見つかるまで少し待つ
    public IUIAutomationElement? Field(Uia uia)
    {
        if (Hwnd == IntPtr.Zero) return null;
        var sw = Stopwatch.StartNew();
        while (sw.ElapsedMilliseconds < 5000)
        {
            var e = uia.Find(Hwnd, e => e.CurrentAutomationId == "box" || e.CurrentName is "message" or "compose");
            if (e != null) { FieldWaitMs = sw.Elapsed.TotalMilliseconds; return e; }
            Thread.Sleep(200);
        }
        return null;
    }

    public double FieldWaitMs;

    public void Dispose()
    {
        // 一時のプロファイルで起動したので、起動したプロセスがそのブラウザーの本体になる（ふだんのブラウザーは別のプロセス）
        try { process?.Kill(entireProcessTree: true); } catch { }
        Thread.Sleep(300);
        var left = Desktop.FindWindow(w => w.Process.Equals(exe, StringComparison.OrdinalIgnoreCase) && w.Title.Contains("Koebumi phase0"));
        if (left != IntPtr.Zero) PostMessage(left, WM_CLOSE, IntPtr.Zero, IntPtr.Zero);
    }
}

/// 自分の窓。届いたキーをすべて記録する（フックで飲み込んだキーが、入力先のアプリに届いていないかを見る）
sealed class KeyLogWindow : Window
{
    public readonly List<(double Ms, int Msg, int Vk)> Received = [];
    public readonly TextBox Box = new() { FontSize = 16, AcceptsReturn = true };
    readonly Stopwatch clock;

    public KeyLogWindow(Stopwatch clock)
    {
        this.clock = clock;
        Title = "Koebumi phase0 key log";
        Width = 520;
        Height = 260;
        Content = Box;
        SourceInitialized += (_, _) => HwndSource.FromHwnd(Handle)?.AddHook(Hook);
        Loaded += (_, _) => Box.Focus();
    }

    public IntPtr Handle => new WindowInteropHelper(this).Handle;

    IntPtr Hook(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg is WM_KEYDOWN or WM_KEYUP or WM_SYSKEYDOWN or WM_SYSKEYUP) Received.Add((clock.Elapsed.TotalMilliseconds, msg, (int)wParam));
        return IntPtr.Zero;
    }
}
