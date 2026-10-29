namespace Koebumi.Core;

/// 文字の種類（表記の統一と辞書の置き換えで使う）
public enum CharClass { Kana, Han, CjkPunct, Latin, Digit, Space, Newline, Other }

public static class CharClasses
{
    public static CharClass Of(char c)
    {
        if (IsNewline(c)) return CharClass.Newline;
        int v = c;
        return v switch
        {
            0x20 or 0x3000 or 0x09 => CharClass.Space,
            >= 0x3040 and <= 0x309F or >= 0x30A0 and <= 0x30FF or >= 0x31F0 and <= 0x31FF or >= 0xFF66 and <= 0xFF9F => CharClass.Kana,
            // 々 も漢字として扱う
            >= 0x4E00 and <= 0x9FFF or >= 0x3400 and <= 0x4DBF or >= 0xF900 and <= 0xFAFF or 0x3005 => CharClass.Han,
            >= 0x3001 and <= 0x3004 or >= 0x3008 and <= 0x3011 or >= 0x3014 and <= 0x301F
                or >= 0xFF01 and <= 0xFF0F or >= 0xFF1A and <= 0xFF20 or >= 0xFF3B and <= 0xFF40 or >= 0xFF5B and <= 0xFF65 => CharClass.CjkPunct,
            >= 0x30 and <= 0x39 => CharClass.Digit,
            _ => char.IsLetter(c) ? CharClass.Latin : CharClass.Other,
        };
    }

    /// Swift の Character.isNewline と同じ文字
    public static bool IsNewline(char c) => (int)c is 0x0A or 0x0D or 0x0B or 0x0C or 0x85 or 0x2028 or 0x2029;

    public static bool IsKatakana(char c) => (int)c is >= 0x30A0 and <= 0x30FF or >= 0x31F0 and <= 0x31FF or >= 0xFF66 and <= 0xFF9F;

    extension(CharClass c)
    {
        /// 日本語・中国語の文字（単語を空白で区切らない）
        public bool IsCJK => c is CharClass.Kana or CharClass.Han;
    }
}
