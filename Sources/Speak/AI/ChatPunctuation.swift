import Foundation

/// 「チャット」に分類したアプリでの句読点。話す言語にかかわらず使う（日本語・中国語の「、」「。」、英語などの「,」「.」）。
/// 「？」「！」と、数字の「1,000」「3.5」、箇条書きの番号「1.」、略語の「a.m.」「e.g.」は残す。
enum ChatPunctuation: String, Codable, CaseIterable, Identifiable {
    case keep  // そのまま
    case noFinalPeriod  // 行の終わりの句点を付けない
    case noPunctuation  // 読点も句点も付けない
    var id: String { rawValue }

    var title: String {
        switch self {
        case .keep: return t("そのまま", "Leave as is")
        case .noFinalPeriod: return t("文末の句点を付けない", "No period at the end")
        case .noPunctuation: return t("句読点を付けない", "No commas or periods")
        }
    }

    /// 入力する直前に、AI を使わない決まった処理で句読点を消す
    func apply(_ text: String) -> String {
        guard self != .keep else { return text }
        var t = text.replacingOccurrences(of: Self.finalPeriod, with: "", options: .regularExpression)
        guard self == .noPunctuation else { return t }
        t = t.replacingOccurrences(of: Self.comma, with: "", options: .regularExpression)
        // 日本語・中国語: 閉じかっこの前は詰める（「了解です。」と → 「了解です」と）。それ以外の文の切れ目は空白にする（了解です。明日 → 了解です 明日）
        t = t.replacingOccurrences(of: #"[。．]+(?=[」』）)】])"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"[。．]+[ \t]*"#, with: " ", options: .regularExpression)
        // 空白で区切る言語: 後ろの空白を残して句点だけ消す（Sounds good. See you → Sounds good See you）
        return t.replacingOccurrences(of: Self.spacedPeriod, with: "", options: .regularExpression)
    }

    /// 句点・読点の後ろに付いてよい閉じかっこと閉じ引用符
    private static let closers = #"[」』）)】\]"'”’»]*"#
    /// 空白で区切る言語の句点（英語などの「.」、ヒンディー語の「।」）。「...」と、略語（a.m.・e.g.）の最後の「.」は除く
    private static let latinPeriod = #"(?:।|(?<!\.)(?<!\.\p{L})\.)"#
    /// 行の終わりの句点
    private static let finalPeriod = #"(?m)(?:[。．]+|\#(latinPeriod))(?=\#(closers)[ \t]*$)"#
    /// 文の途中の、後ろに空白がある句点。箇条書きの番号（「1. 資料作成」）の「.」は除く
    private static let spacedPeriod = #"(?m)(?<!^[ \t]{0,8}[0-9]{1,3})\#(latinPeriod)(?=\#(closers)[ \t])"#
    /// 読点。「、」「，」、アラビア語の「،」と、後ろに空白がある「,」（「1,000」は残す）
    private static let comma = #"(?m)[、，،]|,(?=\#(closers)(?:[ \t]|$))"#
}
