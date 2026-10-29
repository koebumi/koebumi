using System.Runtime.InteropServices;
using Koebumi.Core;
using static Koebumi.App.Native;

namespace Koebumi.App;

/// SendInput でキーを送る。送ったキーには印（dwExtraInfo）を付け、キーボードフックが自分のキーと見分けて素通しする。
/// UIPI で止められたとき（管理者として動くアプリが前面）も、SendInput は送った数を返してキーを捨てる
public static class KeySender
{
    /// "KOEB"
    public static readonly IntPtr Marker = new(0x4B4F4542);

    static readonly int InputSize = Marshal.SizeOf<INPUT>();

    /// 左右のある修飾キーと、矢印などは拡張キーとして送る
    static bool IsExtended(ushort vk) => vk is VK_RCONTROL or VK_RMENU or VK_LWIN or VK_RWIN or VK_LEFT or VK_RIGHT
        or VK_HOME or VK_END or VK_DELETE or 0x21 or 0x22 or KeyNames.UpArrow or KeyNames.DownArrow or 0x2D;

    /// scan・extended を渡さなければ、vk から決める
    static INPUT Key(ushort vk, bool down, ushort? scan = null, bool? extended = null) => new()
    {
        type = INPUT_KEYBOARD,
        u = new InputUnion
        {
            ki = new KEYBDINPUT
            {
                wVk = vk,
                wScan = scan ?? (ushort)MapVirtualKey(vk, 0),
                dwFlags = (down ? 0 : KEYEVENTF_KEYUP) | ((extended ?? IsExtended(vk)) ? KEYEVENTF_EXTENDEDKEY : 0),
                dwExtraInfo = Marker,
            },
        },
    };

    /// 送れた INPUT の数（入力を受けるデスクトップがないと 0）
    static uint Send(params INPUT[] inputs) => inputs.Length == 0 ? 0 : SendInput((uint)inputs.Length, inputs, InputSize);

    public static bool Tap(ushort vk) => Send(Key(vk, true), Key(vk, false)) == 2;

    /// 修飾キーなどを順に押し、逆順に離す（Ctrl+V なら Chord(0x11, 0x56)）。1 回の SendInput で送るので、間にほかの入力が割り込まない
    public static bool Chord(params ushort[] keys)
    {
        var inputs = new INPUT[keys.Length * 2];
        for (int i = 0; i < keys.Length; i++)
        {
            inputs[i] = Key(keys[i], true);
            inputs[inputs.Length - 1 - i] = Key(keys[i], false);
        }
        return Send(inputs) == inputs.Length;
    }

    /// 入力先に通してしまった Win（または Alt）を離す前に、割り当てのないキー（HotkeyResult.MaskKey）を押して離し、
    /// そのあとで vk の離しを送り直す。スタートメニューやメニューバーが開かないようにする（飲み込んだ離しの代わり）
    public static bool MaskAndRelease(ushort vk) => Send(Key((ushort)HotkeyResult.MaskKey, true), Key((ushort)HotkeyResult.MaskKey, false), Key(vk, false)) == 3;

    /// 飲み込んでいた修飾キーの押下 replay を順に送り、続けて今のキー e のイベントを送り直す（飲み込んだ e の代わり）。
    /// 1 回の SendInput で送るので、順番が入れ替わらず、間にほかの入力が割り込まない。
    /// ショートカット以外のキー（Ctrl+Win+← の ←）の前に Win の押下を届けて、入力先に Ctrl+Win+← として見せる
    public static bool ReplayThenSend(IReadOnlyList<int> replay, RawKeyEvent e)
    {
        var inputs = ReplayInputs(replay, e);
        return Send(inputs) == inputs.Length;
    }

    /// ReplayThenSend が送る入力（送らずに中身を確かめられるよう分けてある）。今のキーは、フックが届けたスキャンコードと
    /// 拡張キーの印をそのまま使う（← とテンキーの 4 を取り違えないように）。スキャンコードが不明なら vk から決める
    internal static INPUT[] ReplayInputs(IReadOnlyList<int> replay, RawKeyEvent e)
    {
        var inputs = new INPUT[replay.Count + 1];
        for (int i = 0; i < replay.Count; i++) inputs[i] = Key((ushort)replay[i], true);
        inputs[^1] = e.Scan != 0 ? Key((ushort)e.Vk, e.IsDown, (ushort)e.Scan, e.Extended) : Key((ushort)e.Vk, e.IsDown);
        return inputs;
    }
}
