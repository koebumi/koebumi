using System.Diagnostics;
using System.Runtime.InteropServices;
using static Koebumi.App.Native;

namespace Koebumi.App;

/// vk は仮想キーコード（修飾キーは左右を区別したもの）。Injected は、ほかのプログラム（リモート デスクトップなど）が SendInput で送ったキー。
/// Scan・Extended は、フックが届けたスキャンコードと拡張キーの印（送り直すときに同じキーに見えるように）。Scan が 0 なら不明
public readonly record struct RawKeyEvent(int Vk, bool IsDown, bool Injected, int Scan = 0, bool Extended = false);

public enum HookDecision
{
    /// 入力先のアプリに届ける
    Pass,
    /// 入力先のアプリに届けない
    Swallow,
    /// このキー（Win・Alt の離し）を飲み込み、割り当てのないキーを挟んでから離しを送り直す
    MaskAndReinject,
    /// このキーを飲み込み、飲み込んでいた修飾キーの押下（HookVerdict.Replay）を順に送ってから、このキーを送り直す。
    /// 1 回の SendInput で送る（フックの中で送った入力は今のイベントの後ろに並ぶので、今のキーを通すと修飾キーが後になる）
    ReplayThenReinject,
}

/// handler の答え。Replay は ReplayThenReinject のときだけ使う、送り直す修飾キーの仮想キーコード（送る順）
public readonly record struct HookVerdict(HookDecision Decision, IReadOnlyList<int>? Replay = null)
{
    public static implicit operator HookVerdict(HookDecision decision) => new(decision);
}

/// 低レベルのキーボードフック（WH_KEYBOARD_LL）。専用のスレッドでメッセージを回す。
/// コールバックが遅いとシステム全体のキー入力が止まり、長すぎるとフックが外されるので、handler では判定だけを行う。
/// 自分の SendInput（KeySender の印つき）のキーは handler に渡さず素通しする。handler はフックのスレッドで同期的に呼ばれる
public sealed class KeyboardHookThread : IDisposable
{
    /// LLKHF_EXTENDED（Native.cs にない）。拡張キー（矢印・右 Ctrl・右 Alt・Win など）の印
    const uint LLKHF_EXTENDED = 0x01;

    readonly Func<RawKeyEvent, HookVerdict> handler;
    readonly Stopwatch clock = Stopwatch.StartNew();
    LowLevelKeyboardProc? proc;
    IntPtr hook;
    Thread? thread;
    uint threadId;
    long maxTicks;

    public KeyboardHookThread(Func<RawKeyEvent, HookVerdict> handler) => this.handler = handler;

    public bool IsRunning => thread is { IsAlive: true };

    /// handler にかかった時間の最大（ミリ秒）
    public double MaxCallbackMs => Interlocked.Read(ref maxTicks) * 1000.0 / Stopwatch.Frequency;

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
                var e = new RawKeyEvent((int)k.vkCode, down, (k.flags & LLKHF_INJECTED) != 0, (int)k.scanCode, (k.flags & LLKHF_EXTENDED) != 0);
                var verdict = handler(e);
                decision = verdict.Decision;
                // 送れなかったら離しを通す（飲み込むと Win が押されたままに見える）
                if (decision == HookDecision.MaskAndReinject && !KeySender.MaskAndRelease((ushort)vk))
                    decision = HookDecision.Pass;
                // 送れなかったら、このキーだけ通す（飲み込むとキーが消える）
                else if (decision == HookDecision.ReplayThenReinject && !KeySender.ReplayThenSend(verdict.Replay ?? [], e))
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
