using System.Diagnostics;
using System.Runtime.InteropServices;
using static Koebumi.App.Native;

namespace Koebumi.App;

/// vk は仮想キーコード（修飾キーは左右を区別したもの）。Injected は、ほかのプログラム（リモート デスクトップなど）が SendInput で送ったキー
public readonly record struct RawKeyEvent(int Vk, bool IsDown, bool Injected);

public enum HookDecision
{
    /// 入力先のアプリに届ける
    Pass,
    /// 入力先のアプリに届けない
    Swallow,
    /// このキー（Win・Alt の離し）を飲み込み、割り当てのないキーを挟んでから離しを送り直す
    MaskAndReinject,
}

/// 低レベルのキーボードフック（WH_KEYBOARD_LL）。専用のスレッドでメッセージを回す。
/// コールバックが遅いとシステム全体のキー入力が止まり、長すぎるとフックが外されるので、handler では判定だけを行う。
/// 自分の SendInput（KeySender の印つき）のキーは handler に渡さず素通しする。handler はフックのスレッドで同期的に呼ばれる
public sealed class KeyboardHookThread : IDisposable
{
    readonly Func<RawKeyEvent, HookDecision> handler;
    readonly Stopwatch clock = Stopwatch.StartNew();
    LowLevelKeyboardProc? proc;
    IntPtr hook;
    Thread? thread;
    uint threadId;
    long maxTicks;

    public KeyboardHookThread(Func<RawKeyEvent, HookDecision> handler) => this.handler = handler;

    public bool IsRunning => thread is { IsAlive: true };

    /// handler にかかった時間の最大（ミリ秒）。ResetMaxCallbackMs で 0 に戻す
    public double MaxCallbackMs => Interlocked.Read(ref maxTicks) * 1000.0 / Stopwatch.Frequency;

    public void ResetMaxCallbackMs() => Interlocked.Exchange(ref maxTicks, 0);

    /// フックを付ける。付けられなければ false
    public bool Start()
    {
        if (IsRunning) return true;
        using var ready = new ManualResetEventSlim();
        bool ok = false;
        var t = new Thread(() =>
        {
            threadId = GetCurrentThreadId();
            proc = Callback;
            hook = SetWindowsHookEx(WH_KEYBOARD_LL, proc, GetModuleHandle(null), 0);
            ok = hook != IntPtr.Zero;
            // メッセージのキューを先に作る（Stop が WM_QUIT を送るときに、まだなくて失敗しないように）
            PeekMessage(out _, IntPtr.Zero, 0, 0, PM_NOREMOVE);
            ready.Set();
            if (!ok) return;
            while (GetMessage(out var msg, IntPtr.Zero, 0, 0) > 0)
            {
                TranslateMessage(ref msg);
                DispatchMessage(ref msg);
            }
            UnhookWindowsHookEx(hook);
            hook = IntPtr.Zero;
        })
        { IsBackground = true, Name = "keyboard-hook", Priority = ThreadPriority.Highest };
        t.Start();
        ready.Wait();
        if (!ok) { t.Join(1000); return false; }
        thread = t;
        return true;
    }

    public void Stop()
    {
        var t = thread;
        if (t == null) return;
        PostThreadMessage(threadId, WM_QUIT, IntPtr.Zero, IntPtr.Zero);
        t.Join(2000);
        thread = null;
    }

    public void Dispose() => Stop();

    IntPtr Callback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode < 0) return CallNextHookEx(hook, nCode, wParam, lParam);
        var t0 = Stopwatch.GetTimestamp();
        var decision = HookDecision.Pass;
        uint vk = 0;
        try
        {
            var k = Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(lParam);
            vk = k.vkCode;
            if (k.dwExtraInfo != KeySender.Marker)
            {
                int msg = (int)wParam;
                bool down = msg is WM_KEYDOWN or WM_SYSKEYDOWN;
                decision = handler(new RawKeyEvent((int)k.vkCode, down, (k.flags & LLKHF_INJECTED) != 0));
                // 送れなかったら離しを通す（飲み込むと Win が押されたままに見える）
                if (decision == HookDecision.MaskAndReinject && !KeySender.MaskAndRelease((ushort)vk))
                    decision = HookDecision.Pass;
            }
        }
        catch
        {
            // ネイティブのコールバックから例外を出すとプロセスが落ちる。判定に失敗したキーは通す
            decision = HookDecision.Pass;
        }
        var elapsed = Stopwatch.GetTimestamp() - t0;
        long seen;
        while (elapsed > (seen = Interlocked.Read(ref maxTicks)) && Interlocked.CompareExchange(ref maxTicks, elapsed, seen) != seen) { }
        return decision == HookDecision.Pass ? CallNextHookEx(hook, nCode, wParam, lParam) : 1;
    }
}
