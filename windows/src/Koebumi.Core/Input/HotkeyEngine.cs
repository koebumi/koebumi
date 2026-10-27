namespace Koebumi.Core;

/// 低レベルのキーボードフック（WH_KEYBOARD_LL）から届く、1 つのキーの押下か離し。
/// Vk は仮想キーコードで、修飾キーは左右を区別したもの（VK_LCONTROL 0xA2 など）が届く。
/// フックはオートリピートを、離しのない押下の繰り返しとして送ってくる（リピートかどうかは HotkeyEngine が見分ける）
public readonly record struct HotkeyEvent(int Vk, bool IsDown)
{
    public static HotkeyEvent KeyDown(int vk) => new(vk, true);
    public static HotkeyEvent KeyUp(int vk) => new(vk, false);
}

public enum EngineStateKind
{
    Idle,
    Recording,
    /// 認識・整形中
    Busy,
}

/// コントローラの状態。イベントごとに呼び出し側が渡す
public readonly record struct EngineState
{
    public EngineStateKind Kind { get; }
    /// 録音中の操作（Kind が Recording のときだけ意味がある）
    public Mode Mode { get; }

    private EngineState(EngineStateKind kind, Mode mode)
    {
        Kind = kind;
        Mode = mode;
    }

    public static EngineState Idle => default;
    public static EngineState Busy => new(EngineStateKind.Busy, default);
    public static EngineState Recording(Mode mode) => new(EngineStateKind.Recording, mode);

    public override string ToString() => Kind == EngineStateKind.Recording ? $"Recording({Mode})" : Kind.ToString();
}

public enum HotkeyCommandKind
{
    Begin,
    SwitchMode,
    Finish,
    /// Esc
    Cancel,
    /// Ctrl+Win + 矢印など、ショートカット以外のキーと組み合わされた誤操作
    Abort,
    /// 最後の結果を貼り付け
    PasteLast,
    /// 直前に入力した文の AI の整形を元に戻す（もう一度で AI の文に戻す）
    RevertLast,
}

public readonly record struct HotkeyCommand
{
    public HotkeyCommandKind Kind { get; }
    /// Begin・SwitchMode の操作
    public Mode Mode { get; }

    private HotkeyCommand(HotkeyCommandKind kind, Mode mode)
    {
        Kind = kind;
        Mode = mode;
    }

    public static HotkeyCommand Begin(Mode mode) => new(HotkeyCommandKind.Begin, mode);
    public static HotkeyCommand SwitchMode(Mode mode) => new(HotkeyCommandKind.SwitchMode, mode);
    public static HotkeyCommand Finish => new(HotkeyCommandKind.Finish, default);
    public static HotkeyCommand Cancel => new(HotkeyCommandKind.Cancel, default);
    public static HotkeyCommand Abort => new(HotkeyCommandKind.Abort, default);
    public static HotkeyCommand PasteLast => new(HotkeyCommandKind.PasteLast, default);
    public static HotkeyCommand RevertLast => new(HotkeyCommandKind.RevertLast, default);

    public override string ToString() =>
        Kind is HotkeyCommandKind.Begin or HotkeyCommandKind.SwitchMode ? $"{Kind}({Mode})" : Kind.ToString();
}

public sealed class HotkeyResult
{
    /// 割り当てのない仮想キー。MaskBeforeRelease のときに挟む（AutoHotkey の MenuMaskKey と同じ）
    public const int MaskKey = 0xE8;

    public IReadOnlyList<HotkeyCommand> Commands { get; internal set; } = [];
    /// このキーイベントを入力先アプリに届けない
    public bool Swallow { get; internal set; }
    /// 入力先に通してしまった Win（または Alt）の離し。このイベントは飲み込み、MaskKey の押下と離しを送ってから、
    /// 同じキーの離しを送り直す（スタートメニューやメニューバーが開かないように）。このとき Swallow は false
    public bool MaskBeforeRelease { get; internal set; }
}

/// ショートカット判定の純粋なステートマシン。キーボードフックから呼ばれ、テストからも直接動かせる。
///
/// - 待機中にショートカットを押した瞬間に録音を開始する（Ctrl+Win を押した直後から音声を逃さない）。
/// - 同じ押下の途中でキーが足されて別のショートカットになったら、録音を続けたままモードを切り替える
///   （Ctrl+Win → Ctrl+Win+Shift で翻訳、Ctrl+Win → Ctrl+Win+Space で Ask）。
/// - ディクテーションのキーを長押しして離すとプッシュトゥトーク、短く押すとハンズフリー（もう一度押して確定）。
/// - 録音中の押下は離した時点で判定する（Ctrl+Win+Shift の途中で Ctrl+Win だけが一致して確定しないように）。
/// - 最後の結果の貼り付けと、AI の整形の取り消しは、キーをすべて離してから行う（押したままの修飾キーが Ctrl+V に混ざらないように）。
///
/// Windows では修飾キーも 1 つずつキーの押下・離しとして届くので、押している修飾キーとオートリピートはここで数える。
/// 飲み込むのは、ショートカットの修飾キーでないキー（Space・V・無変換など）、Ctrl などを先に押していてショートカットを完成させた Win、
/// 右 Ctrl だけのような修飾キー 1 つのショートカットのその修飾キー、録音中・処理中の Esc。押下を飲み込んだキーは離しも飲み込む。
/// スレッドセーフではない。フックのスレッドから呼び、UpdateBindings も同じロックの中で呼ぶ
public sealed class HotkeyEngine
{
    public List<(Mode Mode, Shortcut Shortcut)> Bindings { get; set; } = [];
    public List<Shortcut> PasteBindings { get; set; } = [];
    public List<Shortcut> RevertBindings { get; set; } = [];
    public TimeSpan HoldThreshold { get; set; } = TimeSpan.FromSeconds(0.45);
    public TimeSpan ComboHoldThreshold { get; set; } = TimeSpan.FromSeconds(1.0);
    public Func<DateTime> Now { get; set; } = () => DateTime.UtcNow;

    /// 押している修飾キー（左右を区別したもの）
    private readonly HashSet<ModKey> mods = [];
    /// 押下を飲み込んだ、修飾キーでないキー
    private readonly HashSet<int> keysDown = [];
    /// 押しているすべてのキー。押したままのキーにまた押下が届いたらオートリピート
    private readonly HashSet<int> pressed = [];
    /// 押下を飲み込んだ修飾キー
    private readonly HashSet<int> swallowedMods = [];
    /// 離すときに MaskKey を挟む Win・Alt
    private readonly HashSet<int> maskOnRelease = [];
    private Gesture? gesture;

    private sealed class Gesture(DateTime start)
    {
        public DateTime Start = start;
        public bool StartedRecording;
        public Mode? Mode;
        public Mode? MaxMatch;
        public bool MaxMatchHasKey;
        public bool HadForeignKey;
        /// キーを離したときに行う、録音以外の操作（貼り付け・取り消し）
        public HotkeyCommand? Action;
    }

    /// 設定のショートカットを読み込む（空のものは除く）
    public void UpdateBindings(AppSettings settings)
    {
        var list = new List<(Mode, Shortcut)>();
        foreach (var mode in Enum.GetValues<Mode>())
        {
            foreach (var s in settings.ShortcutsFor(mode))
            {
                if (!s.IsEmpty) list.Add((mode, s));
            }
        }
        Bindings = list;
        PasteBindings = settings.PasteLastShortcuts.Where(s => !s.IsEmpty).ToList();
        RevertBindings = settings.RevertLastShortcuts.Where(s => !s.IsEmpty).ToList();
    }

    /// 押しているキーの記録を捨てる。フックが外れたときなど、離しを取りこぼしたかもしれないときに呼ぶ
    public void Reset()
    {
        mods.Clear();
        keysDown.Clear();
        pressed.Clear();
        swallowedMods.Clear();
        maskOnRelease.Clear();
        gesture = null;
    }

    public HotkeyResult Handle(HotkeyEvent e, EngineState state)
    {
        var vk = Normalize(e.Vk);
        if (ModKeys.FromVirtualKey(vk) is { } mod)
        {
            return e.IsDown ? HandleModifierDown(vk, mod, state) : HandleModifierUp(vk, mod, state);
        }
        return e.IsDown ? HandleKeyDown(vk, state) : HandleKeyUp(vk, state);
    }

    /// 左右を区別しない修飾キーのコードは左にそろえる
    private static int Normalize(int vk) => vk switch
    {
        0x10 => 0xA0,
        0x11 => 0xA2,
        0x12 => 0xA4,
        _ => vk,
    };

    private (Mode Mode, Shortcut Shortcut)? Match(int? key)
    {
        foreach (var binding in Bindings)
        {
            if (binding.Shortcut.Matches(mods, key)) return binding;
        }
        return null;
    }

    /// 録音以外の操作のショートカット
    private (HotkeyCommand Command, Shortcut Shortcut)? Action(int? key)
    {
        foreach (var s in PasteBindings)
        {
            if (s.Matches(mods, key)) return (HotkeyCommand.PasteLast, s);
        }
        foreach (var s in RevertBindings)
        {
            if (s.Matches(mods, key)) return (HotkeyCommand.RevertLast, s);
        }
        return null;
    }

    private int? FirstKeyDown()
    {
        foreach (var key in keysDown) return key;
        return null;
    }

    private HotkeyResult HandleModifierDown(int vk, ModKey mod, EngineState state)
    {
        if (!pressed.Add(vk))
        {
            return new HotkeyResult { Swallow = swallowedMods.Contains(vk) };  // オートリピート
        }
        mods.Add(mod);

        var key = FirstKeyDown();
        if (Action(key) is { } action && Request(action.Command, state) is { } result)
        {
            Completed(vk, mod, action.Shortcut, result);
            return result;
        }
        gesture ??= new Gesture(Now());
        if (Match(key) is not { } m) return new HotkeyResult();
        var matched = Matched(m.Mode, hasKey: false, state);
        Completed(vk, mod, m.Shortcut, matched);
        return matched;
    }

    private HotkeyResult HandleModifierUp(int vk, ModKey mod, EngineState state)
    {
        pressed.Remove(vk);
        mods.Remove(mod);
        var result = new HotkeyResult
        {
            Swallow = swallowedMods.Remove(vk),
            MaskBeforeRelease = maskOnRelease.Remove(vk),
        };
        if (mods.Count == 0 && keysDown.Count == 0)
        {
            result.Commands = EndGesture(state);
        }
        return result;
    }

    /// 修飾キーの押下でショートカットが成り立った
    private void Completed(int vk, ModKey mod, Shortcut shortcut, HotkeyResult result)
    {
        if (SwallowsModifier(mod, shortcut))
        {
            swallowedMods.Add(vk);
            result.Swallow = true;
        }
        MarkPassedModifiers();
    }

    /// 右 Ctrl だけのように、左右を区別した修飾キー 1 つだけのショートカットは、その修飾キーを飲み込む。
    /// Win は、Ctrl などを先に押していて Win でショートカットが完成したときに飲み込む（入力先のアプリに Win を見せない）。
    /// それ以外の Ctrl・Shift・Alt は飲み込まない（Ctrl+C などを壊さないように）
    private static bool SwallowsModifier(ModKey mod, Shortcut shortcut)
    {
        if (shortcut.Key == null && shortcut.Mods.Count == 1 && shortcut.Mods.Min == mod) return true;
        return mod.AnySide == ModKey.Win && shortcut.Mods.Any(m => m.AnySide != ModKey.Win);
    }

    /// ショートカットが成り立ったとき、すでに入力先へ通してしまった Win・Alt に、離すときに MaskKey を挟む印を付ける。
    /// Win を先に押したら取り消せないので、スタートメニューが開かないようにする。Alt も、Ctrl+Alt+V の V を飲み込むと
    /// 入力先には Alt だけを押したように見えてメニューバーが開くことがあるので、同じようにする（AutoHotkey と同じ）
    private void MarkPassedModifiers()
    {
        foreach (var vk in pressed)
        {
            if (ModKeys.FromVirtualKey(vk)?.AnySide is ModKey.Win or ModKey.Alt && !swallowedMods.Contains(vk))
            {
                maskOnRelease.Add(vk);
            }
        }
    }

    private HotkeyResult HandleKeyDown(int code, EngineState state)
    {
        if (keysDown.Contains(code))
        {
            return new HotkeyResult { Swallow = true };  // オートリピート
        }
        // 飲み込まずに通したキーのオートリピート
        var isRepeat = !pressed.Add(code);

        if (code == KeyNames.Escape && state != EngineState.Idle)
        {
            keysDown.Add(code);  // 対になる keyUp も入力先アプリに届けない
            return new HotkeyResult { Commands = [HotkeyCommand.Cancel], Swallow = true };
        }

        if (!isRepeat && Action(code) is { } action && Request(action.Command, state) is { } result)
        {
            keysDown.Add(code);
            result.Swallow = true;
            MarkPassedModifiers();
            return result;
        }

        if (!isRepeat && Match(code) is { } m)
        {
            keysDown.Add(code);
            gesture ??= new Gesture(Now());
            var matched = Matched(m.Mode, hasKey: true, state);
            matched.Swallow = true;
            MarkPassedModifiers();
            return matched;
        }

        // ショートカット以外のキー
        if (gesture is not { } g) return new HotkeyResult();
        HotkeyCommand[] commands = [];
        if (g.StartedRecording && state.Kind == EngineStateKind.Recording && !g.HadForeignKey)
        {
            commands = [HotkeyCommand.Abort];
        }
        g.HadForeignKey = true;
        return new HotkeyResult { Commands = commands };
    }

    private HotkeyResult HandleKeyUp(int code, EngineState state)
    {
        pressed.Remove(code);
        if (!keysDown.Remove(code)) return new HotkeyResult();
        var result = new HotkeyResult { Swallow = true };
        if (mods.Count == 0 && keysDown.Count == 0)
        {
            result.Commands = EndGesture(state);
        }
        return result;
    }

    private HotkeyResult Matched(Mode m, bool hasKey, EngineState state)
    {
        if (gesture is not { } g) return new HotkeyResult();
        if (!(g.MaxMatchHasKey && !hasKey))
        {
            g.MaxMatch = m;
            g.MaxMatchHasKey = hasKey;
        }
        switch (state.Kind)
        {
            case EngineStateKind.Idle:
                g.StartedRecording = true;
                g.Mode = m;
                g.Start = Now();
                return new HotkeyResult { Commands = [HotkeyCommand.Begin(m)] };
            case EngineStateKind.Recording:
                if (g.StartedRecording && m != state.Mode)
                {
                    g.Mode = m;
                    return new HotkeyResult { Commands = [HotkeyCommand.SwitchMode(m)] };
                }
                return new HotkeyResult();
            default:
                return new HotkeyResult();
        }
    }

    /// 貼り付けや取り消しを予約する。待機中か、Ctrl+Win+V のように同じ押下で録音を始めたときだけ受け付ける
    private HotkeyResult? Request(HotkeyCommand command, EngineState state)
    {
        var g = gesture ?? new Gesture(Now());
        switch (state.Kind)
        {
            case EngineStateKind.Idle:
                g.Action = command;
                gesture = g;
                return new HotkeyResult();
            case EngineStateKind.Recording when g.StartedRecording:
                // 押した瞬間に始めた録音は捨てる
                g.Action = command;
                gesture = g;
                return new HotkeyResult { Commands = [HotkeyCommand.Abort] };
            default:
                return null;
        }
    }

    private HotkeyCommand[] EndGesture(EngineState state)
    {
        if (gesture is not { } g) return [];
        gesture = null;
        if (g.HadForeignKey) return [];
        if (g.Action is { } action) return [action];
        if (state.Kind != EngineStateKind.Recording) return [];
        var current = state.Mode;

        if (g.StartedRecording)
        {
            // 長押しして離した → プッシュトゥトークとして確定
            var held = Now() - g.Start;
            var threshold = (g.Mode ?? current) == Mode.Dictate ? HoldThreshold : ComboHoldThreshold;
            return held >= threshold ? [HotkeyCommand.Finish] : [];
        }

        if (g.MaxMatch is not { } m) return [];
        if (m == Mode.Dictate || m == current) return [HotkeyCommand.Finish];
        return [HotkeyCommand.SwitchMode(m)];
    }
}
