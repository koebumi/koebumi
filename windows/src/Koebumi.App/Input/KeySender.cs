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
        or VK_HOME or VK_END or VK_DELETE or 0x21 or 0x22 or 0x26 or 0x28 or 0x2D;

    static INPUT Key(ushort vk, bool down) => new()
    {
        type = INPUT_KEYBOARD,
        u = new InputUnion
        {
            ki = new KEYBDINPUT
            {
                wVk = vk,
                wScan = (ushort)MapVirtualKey(vk, 0),
                dwFlags = (down ? 0 : KEYEVENTF_KEYUP) | (IsExtended(vk) ? KEYEVENTF_EXTENDEDKEY : 0),
                dwExtraInfo = Marker,
            },
        },
    };

    static INPUT Unicode(char c, bool down) => new()
    {
        type = INPUT_KEYBOARD,
        u = new InputUnion { ki = new KEYBDINPUT { wScan = c, dwFlags = KEYEVENTF_UNICODE | (down ? 0 : KEYEVENTF_KEYUP), dwExtraInfo = Marker } },
    };

    /// 送れた INPUT の数（入力を受けるデスクトップがないと 0）
    static uint Send(params INPUT[] inputs) => inputs.Length == 0 ? 0 : SendInput((uint)inputs.Length, inputs, InputSize);

    public static bool Down(ushort vk) => Send(Key(vk, true)) == 1;

    public static bool Up(ushort vk) => Send(Key(vk, false)) == 1;

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

    /// 文字をそのまま送る（日本語入力を通さない）
    public static bool TypeUnicode(string text)
    {
        var inputs = new List<INPUT>(text.Length * 2);
        foreach (var c in text)
        {
            inputs.Add(Unicode(c, true));
            inputs.Add(Unicode(c, false));
        }
        return Send([.. inputs]) == inputs.Count;
    }
}
