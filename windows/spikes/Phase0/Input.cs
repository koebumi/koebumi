using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using static Koebumi.Phase0.Native;

namespace Koebumi.Phase0;

/// SendInput でキーとマウスを送る。自分で送ったものには印（dwExtraInfo）を付け、フックで見分ける
static class KeySender
{
    public static readonly IntPtr Marker = new(0x4B4F4542); // "KOEB"

    static readonly int InputSize = Marshal.SizeOf<INPUT>();

    /// 左右のある修飾キーと矢印などは拡張キーとして送る
    static bool IsExtended(ushort vk) => vk is VK_RCONTROL or VK_RMENU or VK_LWIN or VK_RWIN or VK_LEFT or VK_RIGHT
        or VK_HOME or VK_END or VK_DELETE or 0x21 or 0x22 or 0x26 or 0x28 or 0x2D;

    public static INPUT Key(ushort vk, bool down, bool marked = true) => new()
    {
        type = INPUT_KEYBOARD,
        u = new InputUnion
        {
            ki = new KEYBDINPUT
            {
                wVk = vk,
                wScan = (ushort)MapVirtualKey(vk, 0),
                dwFlags = (down ? 0 : KEYEVENTF_KEYUP) | (IsExtended(vk) ? KEYEVENTF_EXTENDEDKEY : 0),
                dwExtraInfo = marked ? Marker : IntPtr.Zero,
            },
        },
    };

    static INPUT Unicode(char c, bool down) => new()
    {
        type = INPUT_KEYBOARD,
        u = new InputUnion { ki = new KEYBDINPUT { wScan = c, dwFlags = KEYEVENTF_UNICODE | (down ? 0 : KEYEVENTF_KEYUP), dwExtraInfo = Marker } },
    };

    /// 送れた数。UIPI で止められても数は減らないことがある（ドキュメントのとおり）
    public static uint Send(params INPUT[] inputs)
    {
        if (inputs.Length == 0) return 0;
        return SendInput((uint)inputs.Length, inputs, InputSize);
    }

    public static uint Tap(ushort vk, bool marked = true) => Send(Key(vk, true, marked), Key(vk, false, marked));

    public static uint Chord(ushort modifier, ushort vk) => Send(Key(modifier, true), Key(vk, true), Key(vk, false), Key(modifier, false));

    /// 文字をそのまま送る（日本語入力を通さない）
    public static uint TypeUnicode(string text)
    {
        var list = new List<INPUT>();
        foreach (var c in text)
        {
            list.Add(Unicode(c, true));
            list.Add(Unicode(c, false));
        }
        return Send(list.ToArray());
    }

    /// ローマ字をキーとして打つ（日本語入力がオンなら変換中の文字になる）
    public static uint TypeKeys(string ascii)
    {
        var list = new List<INPUT>();
        foreach (var c in ascii.ToUpperInvariant())
        {
            list.Add(Key(c, true));
            list.Add(Key(c, false));
        }
        return Send(list.ToArray());
    }

    public static void Click(int x, int y)
    {
        SetCursorPos(x, y);
        Thread.Sleep(30);
        var down = new INPUT { type = INPUT_MOUSE, u = new InputUnion { mi = new MOUSEINPUT { dwFlags = MOUSEEVENTF_LEFTDOWN, dwExtraInfo = Marker } } };
        var up = new INPUT { type = INPUT_MOUSE, u = new InputUnion { mi = new MOUSEINPUT { dwFlags = MOUSEEVENTF_LEFTUP, dwExtraInfo = Marker } } };
        SendInput(2, [down, up], InputSize);
    }
}

/// 最前面の窓と、そのプロセス
static class Desktop
{
    public record Info(IntPtr Hwnd, uint Pid, string Process, string Title, string Class);

    public static Info Describe(IntPtr hwnd)
    {
        GetWindowThreadProcessId(hwnd, out var pid);
        return new Info(hwnd, pid, ProcessName(pid), WindowText(hwnd), ClassName(hwnd));
    }

    public static Info Foreground() => Describe(GetForegroundWindow());

    public static string ProcessName(uint pid)
    {
        var h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
        if (h == IntPtr.Zero) return "";
        try
        {
            var sb = new StringBuilder(1024);
            int size = sb.Capacity;
            return QueryFullProcessImageName(h, 0, sb, ref size) ? Path.GetFileName(sb.ToString()) : "";
        }
        finally { CloseHandle(h); }
    }

    /// スタートメニュー・検索が開いているか（最前面がその窓か）
    public static bool StartMenuIsForeground()
    {
        var p = Foreground().Process.ToLowerInvariant();
        return p is "startmenuexperiencehost.exe" or "searchhost.exe" or "searchapp.exe" or "shellexperiencehost.exe";
    }

    /// 窓を最前面にする。ほかのプロセスが前面にあると SetForegroundWindow だけでは失敗するので、前面のスレッドに入力をつないでから呼ぶ
    public static bool Activate(IntPtr hwnd, int timeoutMs = 1500)
    {
        if (IsIconic(hwnd)) ShowWindow(hwnd, 9 /* SW_RESTORE */);
        var sw = Stopwatch.StartNew();
        while (sw.ElapsedMilliseconds < timeoutMs)
        {
            if (GetForegroundWindow() == hwnd) return true;
            var fg = GetForegroundWindow();
            var fgThread = GetWindowThreadProcessId(fg, out _);
            var me = GetCurrentThreadId();
            bool attached = fgThread != 0 && fgThread != me && AttachThreadInput(me, fgThread, true);
            BringWindowToTop(hwnd);
            SetForegroundWindow(hwnd);
            if (attached) AttachThreadInput(me, fgThread, false);
            if (GetForegroundWindow() == hwnd) return true;
            Thread.Sleep(80);
        }
        return GetForegroundWindow() == hwnd;
    }

    /// プロセスのトップレベルの見える窓を探す
    public static IntPtr FindWindow(Func<Info, bool> match)
    {
        IntPtr found = IntPtr.Zero;
        EnumWindows((h, _) =>
        {
            if (!IsWindowVisible(h)) return true;
            var info = Describe(h);
            if (match(info)) { found = h; return false; }
            return true;
        }, IntPtr.Zero);
        return found;
    }

    public static IntPtr WaitForWindow(Func<Info, bool> match, int timeoutMs)
    {
        var sw = Stopwatch.StartNew();
        while (sw.ElapsedMilliseconds < timeoutMs)
        {
            var h = FindWindow(match);
            if (h != IntPtr.Zero) return h;
            Thread.Sleep(150);
        }
        return IntPtr.Zero;
    }
}

/// プロセスが管理者として動いているか（UIPI で入力が届かない相手か）
static class Elevation
{
    public record Level(bool Known, bool Elevated, int Integrity, string Error);

    public static Level Of(uint pid)
    {
        var h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
        if (h == IntPtr.Zero) return new Level(false, false, 0, $"OpenProcess {Marshal.GetLastWin32Error()}");
        try
        {
            if (!OpenProcessToken(h, TOKEN_QUERY, out var token)) return new Level(false, false, 0, $"OpenProcessToken {Marshal.GetLastWin32Error()}");
            try
            {
                var buf = Marshal.AllocHGlobal(256);
                try
                {
                    bool gotElevation = GetTokenInformation(token, TokenElevation, buf, 4, out _);
                    var error = gotElevation ? "" : $"TokenElevation {Marshal.GetLastWin32Error()}";
                    bool elevated = gotElevation && Marshal.ReadInt32(buf) != 0;
                    int integrity = 0;
                    if (GetTokenInformation(token, TokenIntegrityLevel, buf, 256, out _))
                    {
                        var sid = Marshal.ReadIntPtr(buf);
                        int count = Marshal.ReadByte(GetSidSubAuthorityCount(sid));
                        integrity = Marshal.ReadInt32(GetSidSubAuthority(sid, (uint)(count - 1)));
                    }
                    return new Level(true, elevated, integrity, error);
                }
                finally { Marshal.FreeHGlobal(buf); }
            }
            finally { CloseHandle(token); }
        }
        finally { CloseHandle(h); }
    }

    public static Level Self() => Of((uint)Environment.ProcessId);

    /// 自分より高い整合性レベル（管理者として動くアプリは 0x3000）か
    public static bool IsAboveSelf(uint pid)
    {
        var other = Of(pid);
        return other.Known && other.Integrity > Self().Integrity;
    }

    public static string Name(int integrity) => integrity switch
    {
        >= 0x4000 => "System",
        >= 0x3000 => "High",
        >= 0x2000 => "Medium",
        >= 0x1000 => "Low",
        _ => "Untrusted",
    };
}

/// 日本語入力のオン・オフ（IMM の既定の IME 窓に問い合わせる）
static class Ime
{
    public static bool? IsOpen(IntPtr hwnd)
    {
        var ime = ImmGetDefaultIMEWnd(hwnd);
        if (ime == IntPtr.Zero) return null;
        if (SendMessageTimeout(ime, WM_IME_CONTROL, IMC_GETOPENSTATUS, IntPtr.Zero, 0x0002 /* SMTO_ABORTIFHUNG */, 300, out var r) == IntPtr.Zero) return null;
        return r != IntPtr.Zero;
    }

    /// フォーカスのある子窓（Word の本文など）を返す。取れなければ最前面の窓
    public static IntPtr FocusWindow(IntPtr top)
    {
        var thread = GetWindowThreadProcessId(top, out _);
        var info = new GUITHREADINFO { cbSize = Marshal.SizeOf<GUITHREADINFO>() };
        return GetGUIThreadInfo(thread, ref info) && info.hwndFocus != IntPtr.Zero ? info.hwndFocus : top;
    }

    public static bool? IsOpenForeground() => IsOpen(FocusWindow(GetForegroundWindow()));

    /// VK_IME_ON・VK_IME_OFF を送る（Windows 10 以降の Microsoft IME が受け付ける）
    public static bool? Set(bool on)
    {
        KeySender.Tap(on ? VK_IME_ON : VK_IME_OFF);
        Thread.Sleep(250);
        return IsOpenForeground();
    }
}
