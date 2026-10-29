using Koebumi.Core;

namespace Koebumi.App;

/// ショートカットを登録できる操作
internal enum ShortcutAction { Dictate, Translate, Ask, PasteLast, RevertLast }

/// ショートカットの操作ごとの設定と、登録してよいかの検査。
/// Mac 版は、同じ操作に同じキーを足さないことだけを見ている。Windows 版は、Windows の標準のキーや文字入力を飲み込んでしまわないよう、
/// 修飾キーなしの文字キー・修飾キー 1 つ + 文字キー・左の Ctrl や Shift だけ、も断る
internal static class ShortcutRules
{
    public static readonly ShortcutAction[] All = [.. Enum.GetValues<ShortcutAction>()];

    public static string Title(ShortcutAction a) => a switch
    {
        ShortcutAction.Dictate => Mode.Dictate.Title,
        ShortcutAction.Translate => Mode.Translate.Title,
        ShortcutAction.Ask => Mode.Ask.Title,
        ShortcutAction.PasteLast => T("最後の結果を貼り付け", "Paste last result"),
        _ => T("AI の整形を元に戻す", "Revert AI cleanup"),
    };

    public static string Description(ShortcutAction a) => a switch
    {
        ShortcutAction.Dictate => T("話した内容を整えて入力", "Polish what you say and type it"),
        ShortcutAction.Translate => T("話した内容を翻訳して入力", "Translate what you say and type it"),
        ShortcutAction.Ask => T("選択テキストの書き換えや質問", "Rewrite a selection or ask a question"),
        ShortcutAction.PasteLast => T("直前の結果を、もう一度カーソル位置に入力します", "Type the most recent result again at the cursor"),
        _ => T("直前に入力した文を、AI で整える前の文に置き換えます。もう一度押すと、AI で整えた文に戻ります",
               "Replace the text you just dictated with the version before AI cleanup. Press again to restore it"),
    };

    /// 設定アイコン（Segoe Fluent Icons）
    public static string Glyph(ShortcutAction a) => a switch
    {
        ShortcutAction.Dictate => "\uE720",
        ShortcutAction.Translate => "\uE775",
        ShortcutAction.Ask => "\uE897",
        ShortcutAction.PasteLast => "\uE77F",
        _ => "\uE7A7",
    };

    public static List<Shortcut> Get(AppSettings s, ShortcutAction a) => a switch
    {
        ShortcutAction.Dictate => s.DictateShortcuts,
        ShortcutAction.Translate => s.TranslateShortcuts,
        ShortcutAction.Ask => s.AskShortcuts,
        ShortcutAction.PasteLast => s.PasteLastShortcuts,
        _ => s.RevertLastShortcuts,
    };

    public static void Set(AppSettings s, ShortcutAction a, List<Shortcut> list)
    {
        switch (a)
        {
            case ShortcutAction.Dictate: s.DictateShortcuts = list; break;
            case ShortcutAction.Translate: s.TranslateShortcuts = list; break;
            case ShortcutAction.Ask: s.AskShortcuts = list; break;
            case ShortcutAction.PasteLast: s.PasteLastShortcuts = list; break;
            default: s.RevertLastShortcuts = list; break;
        }
    }

    public static Shortcut Default(ShortcutAction a) => a switch
    {
        ShortcutAction.Dictate => Shortcut.CtrlWin,
        ShortcutAction.Translate => Shortcut.CtrlWinShift,
        ShortcutAction.Ask => Shortcut.CtrlWinSpace,
        ShortcutAction.PasteLast => Shortcut.CtrlAltV,
        _ => Shortcut.CtrlAltZ,
    };

    /// 録音の操作は 1 つ残す。貼り付けと取り消しは、すべて消して使わないようにできる（Mac 版と同じ）
    public static bool CanBeEmpty(ShortcutAction a) => a is ShortcutAction.PasteLast or ShortcutAction.RevertLast;

    /// 修飾キーなしで登録できるキー: ファンクションキーと、変換・無変換・かななどの IME のキー。文字のキーは入力に使うので断る
    public static bool IsStandaloneKey(int vk) =>
        vk is >= 0x70 and <= 0x87 or 0x13 or 0x2C or 0x91 or 0x15 or 0x16 or 0x19 or 0x1A or 0x1C or 0x1D or >= 0xF0 and <= 0xF4;

    /// 登録できないとき、その理由。登録してよければ null。replacing は置き換える元のショートカット（同じ操作の中で重なっても構わない）
    public static string? Validate(AppSettings settings, ShortcutAction target, Shortcut shortcut, Shortcut? replacing)
    {
        if (shortcut.Key == KeyNames.Escape)
            return T("Esc はキャンセルに使うので、ショートカットにできません。", "Esc is used to cancel, so it can't be a shortcut.");

        var groups = shortcut.Mods.Select(m => m.AnySide).Distinct().ToList();
        if (shortcut.Key is { } key)
        {
            if (!IsStandaloneKey(key) && groups.Count < 2)
                return T("文字や数字のキーは、修飾キーを 2 つ以上（例: Ctrl + Alt + V）と組み合わせてください。普段の入力と重なるためです。",
                         "Combine letter and number keys with at least two modifiers (e.g. Ctrl + Alt + V), so they don't clash with normal typing.");
        }
        else if (groups.Count == 1)
        {
            // 1 つだけの修飾キーは、それを飲み込む。左の Ctrl や Shift を飲み込むと、ほかのキーの組み合わせが使えなくなる
            if (shortcut.Mods.Min is not (ModKey.RightControl or ModKey.RightAlt or ModKey.RightWin))
                return T("修飾キー 1 つだけのときは、右の Ctrl・Alt・Win だけ使えます。左側と Shift は、ほかのキーとの組み合わせに使うためです。",
                         "A single modifier must be the right Ctrl, Alt or Win key. The left keys and Shift are needed for other key combinations.");
        }

        foreach (var action in All)
        {
            foreach (var other in Get(settings, action))
            {
                if (action == target && replacing != null && other.Equals(replacing)) continue;
                if (!Overlaps(shortcut, other)) continue;
                return action == target
                    ? T("このショートカットはもう登録してあります。", "This shortcut is already registered.")
                    : T($"このショートカットは「{Title(action)}」で使っています。", $"This shortcut is already used by “{Title(action)}”.");
            }
        }
        return null;
    }

    /// 同じ押し方で、両方が成り立つか（左右を問わない Ctrl と、左の Ctrl は重なる）
    public static bool Overlaps(Shortcut a, Shortcut b)
    {
        if (a.Key != b.Key) return false;
        return a.Mods.All(m => b.Mods.Any(n => Compatible(m, n))) && b.Mods.All(n => a.Mods.Any(m => Compatible(m, n)));
    }

    static bool Compatible(ModKey a, ModKey b) => a == b || (!a.IsSided && b.AnySide == a) || (!b.IsSided && a.AnySide == b);
}
