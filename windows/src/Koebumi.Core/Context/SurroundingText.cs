namespace Koebumi.Core;

/// 入力欄のカーソル前後の文字列と、同じウィンドウに表示されている文字列。
/// 人名・用語の表記を画面に合わせることと、書きかけの文の続きとして自然につなぐことに使う。どこにも保存しない。
/// 読み取りはアプリ（UI Automation）、使い方は Core（ScreenNameFixer・ContextJoiner・プロンプト）
public sealed record SurroundingText
{
    /// 入力欄のカーソル（選択範囲）より前
    public string Before { get; init; } = "";
    /// 入力欄のカーソル（選択範囲）より後
    public string After { get; init; } = "";
    /// 入力欄の外でウィンドウに表示されている文字列のうち、入力欄より前にあるもの（チャットの流れや Gmail のスレッド。入力欄に近いものを優先）
    public string Screen { get; init; } = "";
    /// 入力欄より後ろにあるもの（Spark が作成欄の下に出す返信の引用など。入力欄に近いものを優先）
    public string ScreenAfter { get; init; } = "";

    public const int MaxBefore = 300;
    /// メールアプリは返信の引用（差出人・宛名・挨拶）を、カーソルと自分の署名より後ろに出す。長い署名があっても引用まで届く長さにする
    public const int MaxAfter = 1000;
    public const int MaxScreen = 700;
    /// 作成欄の下の引用も、自分の署名の後ろにある
    public const int MaxScreenAfter = 1000;

    public bool IsEmpty => Before.Length == 0 && After.Length == 0 && Screen.Length == 0 && ScreenAfter.Length == 0;
}

/// 日本語の文を語に分け、読みを付ける。Mac 版は macOS の日本語解析（CFStringTokenizer）、
/// Windows 版はアプリが Windows.Globalization.JapanesePhoneticAnalyzer で実装する。テストでは偽の実装を使う
public interface IJapaneseReader
{
    IReadOnlyList<ReadingToken> Tokenize(string text);
}

/// Surface: 文の中の表記。Reading: 読み（ひらがな。読めない語は空）。Start: 文の中の位置（UTF-16 の位置）
public readonly record struct ReadingToken(string Surface, string Reading, int Start);
