using System.Collections.Concurrent;
using System.Diagnostics;
using System.Runtime.InteropServices;
using static Koebumi.Phase0.Native;

namespace Koebumi.Phase0;

enum ShortcutKind { CtrlWin, RightCtrl, NonConvert }

/// Ctrl+Win の Win キーをどう扱うか
enum WinStrategy
{
    /// Ctrl を先に押したら Win を飲み込む。Win を先に押したら Win は通し、離す前に割り当てのないキーを送ってスタートメニューを止める
    Auto,
    /// 飲み込まずに、離す前に割り当てのないキーを送るだけ
    MaskOnly,
    /// 何もしない（比べるため）
    None,
}

record HookEvent(double Ms, ushort Vk, bool Down, uint Flags, bool Marked, bool Swallowed, string Note)
{
    public bool Injected => (Flags & LLKHF_INJECTED) != 0;
    public override string ToString() =>
        $"{Ms,8:F1}ms {KeyName(Vk),-10} {(Down ? "down" : "up  ")}{(Injected ? " injected" : "")}{(Marked ? " (own)" : "")}{(Swallowed ? " SWALLOWED" : "")} {Note}";

    public static string KeyName(ushort vk) => vk switch
    {
        VK_LCONTROL => "LCtrl", VK_RCONTROL => "RCtrl", VK_LWIN => "LWin", VK_RWIN => "RWin", VK_LSHIFT => "LShift", VK_RSHIFT => "RShift",
        VK_LMENU => "LAlt", VK_RMENU => "RAlt", VK_NONCONVERT => "NonConvert", VK_CONVERT => "Convert", VK_MASK => "Mask(E8)",
        VK_IME_ON => "IME_ON", VK_IME_OFF => "IME_OFF", VK_KANJI => "Kanji", VK_ESCAPE => "Esc", VK_SPACE => "Space", 0x56 => "V",
        0xFF => "FF",
        _ => $"0x{vk:X2}",
    };
}

/// 低レベルのキーボードフック（WH_KEYBOARD_LL）。専用のスレッドでメッセージを回す。
/// コールバックが遅いとシステム全体のキー入力が止まり、長すぎるとフックが外されるので、判定だけをここで行う。
sealed class KeyboardHook : IDisposable
{
    public ShortcutKind Kind = ShortcutKind.CtrlWin;
    public WinStrategy Strategy = WinStrategy.Auto;
    /// true で押した、false で離した。フックのスレッドから呼ばれる
    public event Action<bool, double>? ShortcutChanged;
    public readonly ConcurrentQueue<HookEvent> Events = new();
    /// コールバックにかかった時間の最大（ミリ秒）
    public double MaxCallbackMs { get; private set; }

    readonly Stopwatch clock = Stopwatch.StartNew();
    LowLevelKeyboardProc? proc;
    IntPtr hook;
    Thread? thread;
    uint threadId;

    // ↓ フックのスレッドだけが触る
    bool ctrlDown, winDown, active;
    readonly HashSet<ushort> swallowedDown = [];
    readonly HashSet<ushort> passedDown = [];
    bool needMask;
    // ↑

    public double Now => clock.Elapsed.TotalMilliseconds;

    public bool Start()
    {
        var ready = new ManualResetEventSlim();
        bool ok = false;
        thread = new Thread(() =>
        {
            threadId = GetCurrentThreadId();
            proc = Callback;
            hook = SetWindowsHookEx(WH_KEYBOARD_LL, proc, GetModuleHandle(null), 0);
            ok = hook != IntPtr.Zero;
            ready.Set();
            if (!ok) return;
            while (GetMessage(out var msg, IntPtr.Zero, 0, 0) > 0)
            {
                TranslateMessage(ref msg);
                DispatchMessage(ref msg);
            }
            UnhookWindowsHookEx(hook);
        }) { IsBackground = true, Name = "keyboard-hook" };
        thread.Start();
        ready.Wait();
        return ok;
    }

    public void Dispose()
    {
        if (threadId != 0) PostThreadMessage(threadId, WM_QUIT, IntPtr.Zero, IntPtr.Zero);
        thread?.Join(1000);
    }

    public void ResetState()
    {
        ctrlDown = winDown = active = needMask = false;
        swallowedDown.Clear();
        passedDown.Clear();
        while (Events.TryDequeue(out _)) { }
    }

    IntPtr Callback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode < 0) return CallNextHookEx(hook, nCode, wParam, lParam);
        var t0 = clock.Elapsed.TotalMilliseconds;
        var k = Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(lParam);
        int msg = (int)wParam;
        bool down = msg is WM_KEYDOWN or WM_SYSKEYDOWN;
        bool marked = k.dwExtraInfo == KeySender.Marker;
        var vk = (ushort)k.vkCode;

        string note = "";
        bool swallow = false;
        if (!marked)
        {
            (swallow, note) = Kind switch
            {
                ShortcutKind.CtrlWin => HandleCtrlWin(vk, down, t0),
                ShortcutKind.RightCtrl => HandleSingle(vk, down, VK_RCONTROL, t0),
                _ => HandleSingle(vk, down, VK_NONCONVERT, t0),
            };
        }
        Events.Enqueue(new HookEvent(t0, vk, down, k.flags, marked, swallow, note));
        MaxCallbackMs = Math.Max(MaxCallbackMs, clock.Elapsed.TotalMilliseconds - t0);
        return swallow ? 1 : CallNextHookEx(hook, nCode, wParam, lParam);
    }

    static bool IsCtrl(ushort vk) => vk is VK_LCONTROL or VK_RCONTROL;
    static bool IsWin(ushort vk) => vk is VK_LWIN or VK_RWIN;

    (bool, string) HandleCtrlWin(ushort vk, bool down, double t)
    {
        if (IsCtrl(vk))
        {
            if (down)
            {
                bool repeat = ctrlDown;
                ctrlDown = true;
                if (!repeat && winDown && !active)
                {
                    active = true;
                    // Win は先に通してしまったので、離すときにスタートメニューを止める
                    if (Strategy != WinStrategy.None) needMask = true;
                    ShortcutChanged?.Invoke(true, t);
                    return (false, "shortcut on (Win first)");
                }
                return (false, "");
            }
            ctrlDown = false;
            if (active)
            {
                active = false;
                ShortcutChanged?.Invoke(false, t);
                return (false, "shortcut off");
            }
            return (false, "");
        }

        if (IsWin(vk))
        {
            if (down)
            {
                if (swallowedDown.Contains(vk)) return (true, "repeat");
                if (passedDown.Contains(vk)) return (false, "repeat");
                winDown = true;
                if (ctrlDown && !active)
                {
                    active = true;
                    ShortcutChanged?.Invoke(true, t);
                    if (Strategy == WinStrategy.Auto)
                    {
                        swallowedDown.Add(vk);
                        return (true, "shortcut on (Ctrl first)");
                    }
                    passedDown.Add(vk);
                    if (Strategy == WinStrategy.MaskOnly) needMask = true;
                    return (false, "shortcut on (Ctrl first)");
                }
                passedDown.Add(vk);
                return (false, "");
            }

            winDown = false;
            string note = "";
            if (active)
            {
                active = false;
                ShortcutChanged?.Invoke(false, t);
                note = "shortcut off";
            }
            if (swallowedDown.Remove(vk)) return (true, note);
            passedDown.Remove(vk);
            if (needMask)
            {
                needMask = false;
                // 離す前に割り当てのないキーを挟む。いまの Win の up は飲み込み、印を付けて送り直す（順番を保つため）
                KeySender.Send(KeySender.Key(VK_MASK, true), KeySender.Key(VK_MASK, false), KeySender.Key(vk, false));
                return (true, (note + " masked").Trim());
            }
            return (false, note);
        }
        return (false, "");
    }

    (bool, string) HandleSingle(ushort vk, bool down, ushort target, double t)
    {
        if (vk != target) return (false, "");
        if (down)
        {
            if (active) return (true, "repeat");
            active = true;
            ShortcutChanged?.Invoke(true, t);
            return (true, "shortcut on");
        }
        if (!active) return (false, "");
        active = false;
        ShortcutChanged?.Invoke(false, t);
        return (true, "shortcut off");
    }
}
