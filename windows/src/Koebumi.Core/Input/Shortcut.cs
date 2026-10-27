namespace Koebumi.Core;

// ModKey と Shortcut の型は Core/SettingsTypes.cs にある（設定に保存する形）。ここには判定と表示を置く

/// 修飾キーと Windows の仮想キーコードの対応
public static class ModKeys
{
    /// 仮想キーコードの修飾キー（左右を区別したもの）。修飾キーでなければ null。
    /// 低レベルのキーボードフックには左右を区別したコードが届く。左右を区別しないコード（VK_CONTROL など）が来たら左として扱う
    public static ModKey? FromVirtualKey(int vk) => vk switch
    {
        0xA2 or 0x11 => ModKey.LeftControl,
        0xA3 => ModKey.RightControl,
        0xA0 or 0x10 => ModKey.LeftShift,
        0xA1 => ModKey.RightShift,
        0xA4 or 0x12 => ModKey.LeftAlt,
        0xA5 => ModKey.RightAlt,
        0x5B => ModKey.LeftWin,
        0x5C => ModKey.RightWin,
        _ => null,
    };

    public static bool IsModifierKey(int vk) => FromVirtualKey(vk) != null;

    extension(ModKey key)
    {
        /// 左右を区別する修飾キーか（LeftControl など）。Control・Shift・Alt・Win は左右を問わない
        public bool IsSided => key is not (ModKey.Control or ModKey.Shift or ModKey.Alt or ModKey.Win);

        /// 左右を問わない修飾キー（LeftControl → Control）
        public ModKey AnySide => key switch
        {
            ModKey.LeftControl or ModKey.RightControl => ModKey.Control,
            ModKey.LeftShift or ModKey.RightShift => ModKey.Shift,
            ModKey.LeftAlt or ModKey.RightAlt => ModKey.Alt,
            ModKey.LeftWin or ModKey.RightWin => ModKey.Win,
            _ => key,
        };

        /// 左右を区別した修飾キーの仮想キーコード。左右を問わないものは null
        public int? VirtualKey => key switch
        {
            ModKey.LeftControl => 0xA2,
            ModKey.RightControl => 0xA3,
            ModKey.LeftShift => 0xA0,
            ModKey.RightShift => 0xA1,
            ModKey.LeftAlt => 0xA4,
            ModKey.RightAlt => 0xA5,
            ModKey.LeftWin => 0x5B,
            ModKey.RightWin => 0x5C,
            _ => null,
        };

        /// 押している修飾キー held（左右を区別したもの）が、ショートカットのこの修飾キーに当たるか。
        /// Control は左右どちらの Ctrl でもよく、RightControl は右の Ctrl だけ
        public bool IsSatisfiedBy(ModKey held) => key == held || (!key.IsSided && held.AnySide == key);

        public string Label => key switch
        {
            ModKey.Control => "Ctrl",
            ModKey.LeftControl => "Left Ctrl",
            ModKey.RightControl => "Right Ctrl",
            ModKey.Shift => "Shift",
            ModKey.LeftShift => "Left Shift",
            ModKey.RightShift => "Right Shift",
            ModKey.Alt => "Alt",
            ModKey.LeftAlt => "Left Alt",
            ModKey.RightAlt => "Right Alt",
            ModKey.Win => "Win",
            ModKey.LeftWin => "Left Win",
            _ => "Right Win",
        };
    }
}

public static class ShortcutExtensions
{
    extension(Shortcut shortcut)
    {
        /// 表示名（例: Ctrl + Win + Space、Right Ctrl、無変換）
        public string Display
        {
            get
            {
                var parts = shortcut.Mods.Select(m => m.Label).ToList();
                if (shortcut.Key is { } key) parts.Add(KeyNames.Name(key));
                return string.Join(" + ", parts);
            }
        }

        /// 押している修飾キー held（左右を区別したもの）とキー key で、このショートカットが成り立つか。
        /// ショートカットにない修飾キーを押していたら成り立たない（Mac 版で修飾キーの集合が等しいことを求めたのと同じ）
        public bool Matches(IReadOnlySet<ModKey> held, int? key)
        {
            if (shortcut.IsEmpty || shortcut.Key != key) return false;
            foreach (var m in shortcut.Mods)
            {
                if (!held.Any(h => m.IsSatisfiedBy(h))) return false;
            }
            foreach (var h in held)
            {
                if (!shortcut.Mods.Any(m => m.IsSatisfiedBy(h))) return false;
            }
            return true;
        }
    }
}
