import Foundation

enum UILanguage: String, Codable, CaseIterable, Identifiable {
    case ja, en
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .ja: return "日本語"
        case .en: return "English"
        }
    }

    static var systemDefault: UILanguage {
        let preferred = Locale.preferredLanguages.first ?? "ja"
        return preferred.hasPrefix("ja") ? .ja : .en
    }
}

/// UI 文字列を現在のインターフェース言語で返す。
/// 呼び出し側は日本語と英語を並べて書く: `t("履歴", "History")`
func t(_ ja: String, _ en: String) -> String {
    L10n.current == .en ? en : ja
}

enum L10n {
    static var current: UILanguage = .systemDefault
}
