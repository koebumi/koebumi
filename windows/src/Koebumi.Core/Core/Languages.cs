using System.Globalization;
using System.Text;

namespace Koebumi.Core;

public static class Languages
{
    /// クラウド音声認識向けの主な言語・地域バリアント
    public static readonly string[] Dictation =
    [
        "ja-JP", "en-US", "en-GB", "en-AU", "en-CA", "en-IN",
        "zh-CN", "zh-TW", "zh-HK", "yue-CN", "ko-KR",
        "es-ES", "es-MX", "es-US", "fr-FR", "fr-CA", "de-DE", "it-IT",
        "pt-BR", "pt-PT", "nl-NL", "sv-SE", "da-DK", "nb-NO", "fi-FI",
        "pl-PL", "cs-CZ", "ru-RU", "uk-UA", "tr-TR", "el-GR", "he-IL",
        "ar-SA", "hi-IN", "bn-IN", "ta-IN", "th-TH", "vi-VN", "id-ID",
        "ms-MY", "fil-PH", "hu-HU", "ro-RO",
    ];

    /// 翻訳先として選べる言語
    public static readonly string[] TranslationTargets =
    [
        "en-US", "en-GB", "ja-JP", "zh-CN", "zh-TW", "ko-KR",
        "es-ES", "es-MX", "fr-FR", "de-DE", "it-IT", "pt-BR", "pt-PT",
        "nl-NL", "sv-SE", "pl-PL", "ru-RU", "uk-UA", "tr-TR",
        "ar-SA", "hi-IN", "th-TH", "vi-VN", "id-ID", "ms-MY", "fil-PH",
    ];

    static CultureInfo? Culture(string id)
    {
        try { return CultureInfo.GetCultureInfo(id); }
        catch (CultureNotFoundException) { return null; }
    }

    /// 画面に出す言語名。英語の画面では英語名、日本語の画面では OS の表示言語での名前
    public static string Name(string id)
    {
        var c = Culture(id);
        if (c == null) return id;
        return L10n.Current == UILanguage.En ? c.EnglishName : c.DisplayName;
    }

    /// 音声バーに出す短い言語名（例: "JA"）。同じ言語の地域違いが並ぶときは地域も付ける（"EN-US" と "EN-GB"）。
    public static string ShortName(string id, IEnumerable<string> among)
    {
        var code = IsoCode(id);
        var parts = id.Split('-');
        if (among.Count(x => IsoCode(x) == code) <= 1 || parts.Length < 2) return code.ToUpperInvariant();
        return $"{code}-{parts[^1]}".ToUpperInvariant();
    }

    /// プロンプトに渡す英語の言語名（例: "Japanese (Japan)"）
    public static string EnglishName(string id) => Culture(id)?.EnglishName ?? id;

    /// 空白で単語を区切らない言語か
    public static bool IsUnspaced(string id) => IsoCode(id) is "ja" or "zh" or "yue" or "th" or "lo" or "km" or "my";

    /// ISO-639 の言語コード（Whisper の language パラメータ用）
    public static string IsoCode(string id) => id.Split('-')[0].ToLowerInvariant();

    /// 文章がその言語の文字で書かれているか（翻訳が訳されずに元の言語のまま返ってきていないかを見る）。
    /// 文字で判定できない言語は true を返す。
    public static bool IsWritten(string text, string id)
    {
        var letters = text.EnumerateRunes().Where(Rune.IsLetter).Select(r => r.Value).ToList();
        if (letters.Count == 0) return false;
        double Share(params (int Lo, int Hi)[] ranges) =>
            (double)letters.Count(v => ranges.Any(r => v >= r.Lo && v <= r.Hi)) / letters.Count;
        (int, int)[] kana = [(0x3040, 0x30FF)];
        (int, int)[] han = [(0x4E00, 0x9FFF), (0x3400, 0x4DBF)];
        (int, int)[] hangul = [(0xAC00, 0xD7AF), (0x1100, 0x11FF), (0x3130, 0x318F)];
        (int, int)[] latin = [(0x41, 0x5A), (0x61, 0x7A), (0xC0, 0x24F), (0x1E00, 0x1EFF)];
        return IsoCode(id) switch
        {
            "ja" => Share(kana) > 0.05 || (Share(han) > 0.5 && Share(latin) < 0.5),
            "zh" or "yue" => Share(han) > 0.5 && Share(kana) == 0,
            "ko" => Share(hangul) > 0.5,
            "ru" or "uk" => Share((0x400, 0x4FF)) > 0.5,
            "el" => Share((0x370, 0x3FF)) > 0.5,
            "he" => Share((0x590, 0x5FF)) > 0.5,
            "ar" => Share((0x600, 0x6FF)) > 0.5,
            "hi" => Share((0x900, 0x97F)) > 0.5,
            "bn" => Share((0x980, 0x9FF)) > 0.5,
            "ta" => Share((0xB80, 0xBFF)) > 0.5,
            "th" => Share((0xE00, 0xE7F)) > 0.5,
            "en" or "es" or "fr" or "de" or "it" or "pt" or "nl" or "sv" or "da" or "nb" or "fi" or "pl" or "cs" or "tr" or "vi" or "id" or "ms" or "fil" or "hu" or "ro"
                => Share(latin) > 0.7,
            _ => true,
        };
    }
}
