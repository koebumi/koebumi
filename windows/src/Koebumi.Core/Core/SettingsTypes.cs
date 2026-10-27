using System.Text.Json.Serialization;

namespace Koebumi.Core;

// 設定（AppSettings）に入る型。処理は各機能のファイルに書く（JapaneseFormatter・ChatPunctuationRules・SnippetExpander など）

/// 日本語の句読点の組み合わせ
public enum JapanesePunctuation
{
    /// 、。
    Standard,
    /// ，。
    CommaMaru,
    /// ，．
    CommaPeriod,
}

/// 日本語の文中にある英単語の前後の空白
public enum LatinSpacing { Keep, Remove, Insert }

/// 日本語の表記ルール。AI の出力を決まった処理でそろえる（AI に指示すると小さいモデルの言い回しが崩れるため、指示はしない）。
[JsonConverter(typeof(TolerantConverter<JapaneseNotation>))]
public sealed record JapaneseNotation
{
    public JapanesePunctuation Punctuation { get; set; } = JapanesePunctuation.Standard;
    public LatinSpacing LatinSpacing { get; set; } = LatinSpacing.Keep;
    /// 補助動詞・形式名詞などをひらがなで書く（〜して下さい → 〜してください）
    public bool HiraganaForms { get; set; } = true;
    /// 疑問文の文末を「？」にする（〜ですか。 → 〜ですか？）
    public bool QuestionMark { get; set; } = true;
}

/// 「チャット」に分類したアプリでの句読点。話す言語にかかわらず使う
public enum ChatPunctuation
{
    /// そのまま
    Keep,
    /// 行の終わりの句点を付けない
    NoFinalPeriod,
    /// 読点も句点も付けない
    NoPunctuation,
}

/// 画面の文脈をどこまで使うか
public enum ContextAwareness
{
    Off,
    /// この PC で処理するときだけ
    LocalOnly,
    /// クラウドの AI にも送る
    Always,
}

/// 定型文（署名・挨拶など）。呼び出す言葉だけを 1 つの文として話すと、登録した文を AI に通さずにそのまま入力する
public sealed record Snippet
{
    public Guid Id { get; init; } = Guid.NewGuid();
    /// 呼び出す言葉（署名）
    public string Trigger { get; init; } = "";
    /// 入力する文。{宛名} と {挨拶} は返信先のメールに合わせて置き換える
    public string Text { get; init; } = "";
}

/// 修飾キー。左右を問わないもの（Control・Shift・Alt・Win）と、左右を区別するものがある。
/// Ctrl+Win はどちらの Ctrl・Win で押してもよい（リモート デスクトップでは Ctrl が右 Ctrl として届くことがある）
public enum ModKey
{
    Control, LeftControl, RightControl,
    Shift, LeftShift, RightShift,
    Alt, LeftAlt, RightAlt,
    Win, LeftWin, RightWin,
}

/// 修飾キーのみ（例: Ctrl+Win）、修飾キー + 通常キー（例: Ctrl+Win+Space）、または修飾キーでないキーだけ（例: 無変換）のショートカット。
/// Key は Windows の仮想キーコード
public sealed class Shortcut : IEquatable<Shortcut>
{
    public SortedSet<ModKey> Mods { get; init; } = [];
    public int? Key { get; init; }

    public Shortcut() { }

    public Shortcut(IEnumerable<ModKey> mods, int? key = null)
    {
        Mods = new SortedSet<ModKey>(mods);
        Key = key;
    }

    [JsonIgnore] public bool IsEmpty => Mods.Count == 0 && Key == null;

    public bool Equals(Shortcut? other) => other != null && Key == other.Key && Mods.SetEquals(other.Mods);
    public override bool Equals(object? obj) => Equals(obj as Shortcut);
    public override int GetHashCode() => HashCode.Combine(Key, string.Join(",", Mods));

    public const int VkSpace = 0x20, VkV = 0x56, VkZ = 0x5A, VkNonConvert = 0x1D;

    public static Shortcut CtrlWin => new([ModKey.Control, ModKey.Win]);
    public static Shortcut CtrlWinShift => new([ModKey.Control, ModKey.Win, ModKey.Shift]);
    public static Shortcut CtrlWinSpace => new([ModKey.Control, ModKey.Win], VkSpace);
    public static Shortcut CtrlAltV => new([ModKey.Control, ModKey.Alt], VkV);
    public static Shortcut CtrlAltZ => new([ModKey.Control, ModKey.Alt], VkZ);
}
