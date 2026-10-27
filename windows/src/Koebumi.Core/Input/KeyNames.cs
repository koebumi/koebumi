namespace Koebumi.Core;

/// Windows の仮想キーコードと、その表示名
public static class KeyNames
{
    public const int Space = 0x20;
    public const int ReturnKey = 0x0D;
    public const int Escape = 0x1B;
    public const int VKey = 0x56;
    public const int CKey = 0x43;
    public const int ZKey = 0x5A;
    public const int DownArrow = 0x28;
    public const int UpArrow = 0x26;
    /// 無変換（日本語キーボード）
    public const int NonConvert = 0x1D;
    /// 変換（日本語キーボード）
    public const int Convert = 0x1C;

    /// 記号のキー（0xBA〜0xE2）は US 配列の刻印。日本語キーボードでは刻印と違うことがある
    public static string Name(int vk) => vk switch
    {
        >= 0x30 and <= 0x39 or >= 0x41 and <= 0x5A => ((char)vk).ToString(),
        >= 0x60 and <= 0x69 => $"Num {vk - 0x60}",
        >= 0x70 and <= 0x87 => $"F{vk - 0x6F}",
        0x08 => "Backspace",
        0x09 => "Tab",
        0x0C => "Clear",
        0x0D => "Enter",
        0x10 => "Shift",
        0x11 => "Ctrl",
        0x12 => "Alt",
        0x13 => "Pause",
        0x14 => "Caps Lock",
        0x15 => T("かな", "Kana"),
        0x16 => T("IME オン", "IME On"),
        0x19 => T("漢字", "Kanji"),
        0x1A => T("IME オフ", "IME Off"),
        0x1B => "Esc",
        0x1C => T("変換", "Henkan"),
        0x1D => T("無変換", "Muhenkan"),
        0x20 => "Space",
        0x21 => "Page Up",
        0x22 => "Page Down",
        0x23 => "End",
        0x24 => "Home",
        0x25 => "←",
        0x26 => "↑",
        0x27 => "→",
        0x28 => "↓",
        0x2C => "Print Screen",
        0x2D => "Insert",
        0x2E => "Delete",
        0x5B => "Left Win",
        0x5C => "Right Win",
        0x5D => "Menu",
        0x6A => "Num *",
        0x6B => "Num +",
        0x6D => "Num -",
        0x6E => "Num .",
        0x6F => "Num /",
        0x90 => "Num Lock",
        0x91 => "Scroll Lock",
        0xA0 => "Left Shift",
        0xA1 => "Right Shift",
        0xA2 => "Left Ctrl",
        0xA3 => "Right Ctrl",
        0xA4 => "Left Alt",
        0xA5 => "Right Alt",
        0xBA => ";",
        0xBB => "=",
        0xBC => ",",
        0xBD => "-",
        0xBE => ".",
        0xBF => "/",
        0xC0 => "`",
        0xDB => "[",
        0xDC => "\\",
        0xDD => "]",
        0xDE => "'",
        0xE2 => "\\",
        0xF0 => T("英数", "Eisu"),
        0xF2 => T("カタカナひらがな", "Katakana/Hiragana"),
        0xF3 or 0xF4 => T("半角/全角", "Hankaku/Zenkaku"),
        _ => $"Key 0x{vk:X2}",
    };
}
