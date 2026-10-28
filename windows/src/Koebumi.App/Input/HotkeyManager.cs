using System.Windows.Threading;
using Koebumi.Core;

namespace Koebumi.App;

/// キーボードフックの結果を HotkeyEngine（ショートカットの判定）に渡し、コマンドを UI スレッドへ送る。Mac 版の HotkeyManager に当たる。
///
/// フックのスレッドは、UI スレッドが応えるのを待たずに、判定の直後に次の状態を自分で決める
/// （Begin・SwitchMode は録音中、Finish は処理中、Cancel・Abort は待機中）。そうしないと、UI スレッドが忙しいあいだに
/// 届いた次のキーを、古い状態で判定してしまう。UI スレッドは、コントローラの本当の状態が変わるたびに SetState で写しを直す
public sealed class HotkeyManager : IDisposable
{
    readonly Dispatcher dispatcher;
    readonly HotkeyEngine engine = new();
    readonly KeyboardHookThread hook;
    readonly object gate = new();
    // ↓ gate で守る
    EngineState mirrored = EngineState.Idle;
    EngineState? deferred;
    int inFlight;
    // ↑

    /// UI スレッドで、届いた順に呼ばれる
    public event Action<HotkeyCommand>? CommandReceived;

    /// コントローラの本当の状態。コマンドを処理し終えるたびに読んで、フックの写しを直す
    /// （コマンドを断った＝状態が変わらなかったときに、フックが先に決めた状態が残らないように）。使わなければ SetState だけで直す
    public Func<EngineState>? StateProvider { get; set; }

    /// コールバックにかかった時間の最大（ミリ秒）
    public double MaxCallbackMs => hook.MaxCallbackMs;

    public bool IsRunning => hook.IsRunning;

    /// UI スレッドで作る（コマンドを届けるスレッドになる）
    public HotkeyManager(Dispatcher dispatcher)
    {
        this.dispatcher = dispatcher;
        hook = new KeyboardHookThread(OnKey);
    }

    public void UpdateBindings(AppSettings settings)
    {
        lock (gate) engine.UpdateBindings(settings);
    }

    /// フックを付ける。付けられなければ false（もう付いていれば true）
    public bool Start()
    {
        Reset();
        return hook.Start();
    }

    public void Stop() => hook.Stop();

    /// フックを付け直す（キーを取りこぼしたかもしれないとき）
    public bool Restart()
    {
        hook.Stop();
        return Start();
    }

    /// 押しているキーの記録を捨てる。前面の窓が変わったときに呼ぶ（管理者として動くアプリが前面のあいだは、キーの離しが届かない）
    public void Reset()
    {
        lock (gate) engine.Reset();
    }

    /// コントローラの状態が変わったら UI スレッドから呼ぶ。コマンドが処理されている途中の呼び出しは、
    /// 処理が終わるまで待たせる（古い状態で、フックが決めた新しい状態を上書きしないため）
    public void SetState(EngineState state)
    {
        lock (gate)
        {
            if (inFlight > 0) deferred = state;
            else mirrored = state;
        }
    }

    /// 1 つのキーイベントの判定。フックのスレッドから呼ばれる（フックを付けずに、判定の経路だけを試すときは直接呼ぶ）
    internal HookDecision OnKey(RawKeyEvent e)
    {
        HotkeyResult result;
        HotkeyCommand[] commands;
        lock (gate)
        {
            result = engine.Handle(e.IsDown ? HotkeyEvent.KeyDown(e.Vk) : HotkeyEvent.KeyUp(e.Vk), mirrored);
            commands = [.. result.Commands];
            foreach (var command in commands)
            {
                switch (command.Kind)
                {
                    case HotkeyCommandKind.Begin or HotkeyCommandKind.SwitchMode: mirrored = EngineState.Recording(command.Mode); break;
                    case HotkeyCommandKind.Finish: mirrored = EngineState.Busy; break;
                    case HotkeyCommandKind.Cancel or HotkeyCommandKind.Abort: mirrored = EngineState.Idle; break;
                }
            }
            if (commands.Length > 0)
            {
                inFlight++;
                deferred = null;
            }
        }
        if (commands.Length > 0) dispatcher.BeginInvoke(() => Deliver(commands));
        // MaskBeforeRelease のとき Swallow は false。離しは飲み込んで、KeyboardHookThread が送り直す
        return result.MaskBeforeRelease ? HookDecision.MaskAndReinject : result.Swallow ? HookDecision.Swallow : HookDecision.Pass;
    }

    void Deliver(HotkeyCommand[] commands)
    {
        try
        {
            foreach (var command in commands) CommandReceived?.Invoke(command);
        }
        finally
        {
            lock (gate)
            {
                inFlight--;
                if (inFlight == 0 && deferred is { } state)
                {
                    mirrored = state;
                    deferred = null;
                }
            }
            if (StateProvider is { } provider) SetState(provider());
        }
    }

    public void Dispose() => hook.Dispose();
}
