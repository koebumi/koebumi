using System.Runtime.InteropServices;
using System.Text;
using static Koebumi.App.Native;

namespace Koebumi.App;

/// 最前面の窓と、そのプロセス。ExeName は exe のファイル名そのまま（AppContext.Describe で小文字にそろえる）。
/// IsElevatedAboveUs は、相手の整合性レベルが自分より高いこと（管理者として動くアプリ）。UIPI のため、フックも貼り付けも届かない
public sealed record ForegroundApp(IntPtr Hwnd, int ProcessId, string ExeName, string WindowTitle, bool IsElevatedAboveUs)
{
    /// いまの最前面の窓。窓がない（切り替え中・画面のロック・リモート デスクトップの切断）ときは null
    public static ForegroundApp? Current() => Describe(GetForegroundWindow());

    public static ForegroundApp? Describe(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero) return null;
        GetWindowThreadProcessId(hwnd, out var pid);
        if (pid == 0) return null;
        return new ForegroundApp(hwnd, (int)pid, ExeNameOf(pid), WindowText(hwnd), IsAboveUs(pid));
    }

    static string ExeNameOf(uint pid)
    {
        var process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
        if (process == IntPtr.Zero) return "";
        try
        {
            var sb = new StringBuilder(1024);
            int size = sb.Capacity;
            return QueryFullProcessImageName(process, 0, sb, ref size) ? Path.GetFileName(sb.ToString()) : "";
        }
        finally { CloseHandle(process); }
    }

    static readonly Lazy<int> ownIntegrity = new(() => IntegrityLevel((uint)Environment.ProcessId) ?? 0);

    /// 相手が自分より高い整合性レベル（管理者として動くアプリは 0x3000、自分は通常 0x2000）か。調べられなければ false
    static bool IsAboveUs(uint pid) => pid != Environment.ProcessId && IntegrityLevel(pid) is { } level && level > ownIntegrity.Value;

    /// プロセスのトークンの整合性レベル（SID の最後の下位権限）
    static int? IntegrityLevel(uint pid)
    {
        var process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
        if (process == IntPtr.Zero) return null;
        try
        {
            if (!OpenProcessToken(process, TOKEN_QUERY, out var token)) return null;
            try
            {
                var buffer = Marshal.AllocHGlobal(256);
                try
                {
                    if (!GetTokenInformation(token, TokenIntegrityLevel, buffer, 256, out _)) return null;
                    var sid = Marshal.ReadIntPtr(buffer);
                    int count = Marshal.ReadByte(GetSidSubAuthorityCount(sid));
                    return Marshal.ReadInt32(GetSidSubAuthority(sid, (uint)(count - 1)));
                }
                finally { Marshal.FreeHGlobal(buffer); }
            }
            finally { CloseHandle(token); }
        }
        finally { CloseHandle(process); }
    }
}

/// 最前面の窓が切り替わったことを知らせる（SetWinEventHook の EVENT_SYSTEM_FOREGROUND）。
/// UI スレッドで Start する（フックの呼び出しがそのスレッドのメッセージ ループに届く）。自分のプロセスの窓への切り替えは知らせない
public sealed class ForegroundWatcher : IDisposable
{
    WinEventProc? proc;
    IntPtr hook;
    IntPtr last;

    /// 切り替わった先。UI スレッドで呼ばれる。窓の情報を読めなかったときは呼ばない
    public event Action<ForegroundApp>? Changed;

    public bool Start()
    {
        if (hook != IntPtr.Zero) return true;
        proc = OnEvent;
        hook = SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, IntPtr.Zero, proc, 0, 0, WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);
        return hook != IntPtr.Zero;
    }

    public void Stop()
    {
        if (hook == IntPtr.Zero) return;
        UnhookWinEvent(hook);
        hook = IntPtr.Zero;
        proc = null;
    }

    public void Dispose() => Stop();

    void OnEvent(IntPtr hookHandle, uint ev, IntPtr hwnd, int idObject, int idChild, uint thread, uint time)
    {
        // 切り替えの途中は窓がない。同じ窓への通知は重ねて知らせない
        if (hwnd == IntPtr.Zero || hwnd == last) return;
        last = hwnd;
        if (ForegroundApp.Describe(hwnd) is { } app) Changed?.Invoke(app);
    }
}
