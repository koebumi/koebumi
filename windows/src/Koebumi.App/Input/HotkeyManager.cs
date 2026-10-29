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
    ShortcutCapture? capture;
    Action<Shortcut?>? captureDone;
    int captureGeneration;
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

    /// 記録の途中でキーが来なくなったときに、フックがキーを飲み込み続けないよう、自動で取り消すまでの時間
    internal TimeSpan CaptureTimeout { get; set; } = TimeSpan.FromSeconds(30);

    public bool IsCapturing
    {
        get { lock (gate) return capture != null; }
    }

    /// 次に押されたキーの組み合わせを記録する（設定の画面でショートカットを登録するとき）。
    /// 記録中は、フックがすべてのキーの押下と離しを飲み込む（スタートメニューやほかのショートカットが動かないように）。
    /// 押しているキーをすべて離したところで、押された修飾キー（左右を区別したもの）と通常キー 1 つの組み合わせを done に渡す。
    /// Esc だけを押したときは取り消しで、done(null)。done は UI スレッドで呼ぶ。記録の途中でもう一度呼ぶと、前の done には null を渡す。
    /// 判定は、記録を始めるときと終えるときに Reset する（記録中のキーを、判定が押したままと思い込まないように）
    public void CaptureNext(Action<Shortcut?> done)
    {
        Action<Shortcut?>? replaced;
        int generation;
        lock (gate)
        {
            replaced = captureDone;
            capture = new ShortcutCapture();
            captureDone = done;
            generation = ++captureGeneration;
            engine.Reset();
        }
        if (replaced != null) dispatcher.BeginInvoke(() => replaced(null));
        // 離しを取りこぼしたときに、キーボードが戻らなくならないよう、一定時間で取り消す
        _ = Task.Delay(CaptureTimeout).ContinueWith(_ => CancelCapture(generation), TaskScheduler.Default);
    }

    /// 記録を取り消す。記録していなければ何もしない。記録していたときは done(null) を UI スレッドで呼ぶ
    public void CancelCapture() => CancelCapture(null);

    void CancelCapture(int? generation)
    {
        Action<Shortcut?>? done;
        lock (gate)
        {
            if (capture == null || (generation != null && generation != captureGeneration)) return;
            done = captureDone;
            capture = null;
            captureDone = null;
            engine.Reset();
        }
        if (done != null) dispatcher.BeginInvoke(() => done(null));
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
    internal HookVerdict OnKey(RawKeyEvent e)
    {
        if (OnCaptureKey(e) is { } captureDecision) return captureDecision;
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
        // Replay・MaskBeforeRelease のとき Swallow は false。このキーは飲み込んで、KeyboardHookThread が送り直す
        // （Replay は押下、MaskBeforeRelease は修飾キーの離しのイベントなので、同時には起きない）
        if (result.Replay.Count > 0) return new HookVerdict(HookDecision.ReplayThenReinject, result.Replay);
        return result.MaskBeforeRelease ? HookDecision.MaskAndReinject : result.Swallow ? HookDecision.Swallow : HookDecision.Pass;
    }

    /// 記録中ならそのキーを記録に使い、判定を返す（記録中でなければ null）。終わったら done を UI スレッドへ送る
    HookDecision? OnCaptureKey(RawKeyEvent e)
    {
        Action<Shortcut?>? done = null;
        Shortcut? shortcut = null;
        HookDecision decision;
        lock (gate)
        {
            if (capture == null) return null;
            var step = capture.Handle(e);
            decision = step.Decision;
            if (step.Done)
            {
                done = captureDone;
                shortcut = step.Shortcut;
                capture = null;
                captureDone = null;
                engine.Reset();
            }
        }
        if (done != null) dispatcher.BeginInvoke(() => done(shortcut));
        return decision;
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

    public void Dispose()
    {
        CancelCapture();
        hook.Dispose();
    }
}

/// ショートカットの記録の状態機械（HotkeyManager のロックの中で使う）。キーボードフックを付けずに、合成したキーで試せる。
///
/// 記録中に押下を見たキーは、押下も離しも飲み込み、すべて離したところで 1 つのショートカットにする
/// （修飾キーは左右を区別したもの + 通常キーは最後に押した 1 つ）。記録を始める前から押していたキーの離しは通す
/// （飲み込むと、入力先のアプリでそのキーが押されたままになる）。Esc だけを押したときは取り消し。
internal sealed class ShortcutCapture
{
    internal readonly record struct Step(HookDecision Decision, bool Done, Shortcut? Shortcut);

    readonly HashSet<int> down = [];
    readonly SortedSet<ModKey> mods = [];
    int? key;
    bool cancelled;

    public Step Handle(RawKeyEvent e)
    {
        if (e.IsDown)
        {
            if (ModKeys.FromVirtualKey(e.Vk) is { } mod) mods.Add(mod);
            else if (e.Vk == KeyNames.Escape && mods.Count == 0 && key == null) cancelled = true;
            else key = e.Vk;
            down.Add(e.Vk);
            return new Step(HookDecision.Swallow, false, null);
        }
        // 記録を始める前から押していたキーの離し
        if (!down.Remove(e.Vk)) return new Step(HookDecision.Pass, false, null);
        if (down.Count > 0) return new Step(HookDecision.Swallow, false, null);
        bool empty = cancelled || (mods.Count == 0 && key == null);
        return new Step(HookDecision.Swallow, true, empty ? null : new Shortcut(mods, key));
    }
}
