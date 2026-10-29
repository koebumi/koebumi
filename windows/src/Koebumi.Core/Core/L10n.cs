using System.Globalization;

namespace Koebumi.Core;

public enum UILanguage { Ja, En }

/// UI 文字列を現在のインターフェース言語で返す。
/// 呼び出し側は日本語と英語を並べて書く: `T("履歴", "History")`（`using static Koebumi.Core.L10n;`）
public static class L10n
{
    public static UILanguage Current { get; set; } = SystemDefault;

    public static UILanguage SystemDefault =>
        CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "ja" ? UILanguage.Ja : UILanguage.En;

    public static string T(string ja, string en) => Current == UILanguage.En ? en : ja;

    extension(UILanguage language)
    {
        public string DisplayName => language == UILanguage.Ja ? "日本語" : "English";
    }
}
