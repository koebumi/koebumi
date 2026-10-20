import Combine
import Foundation

struct DictionaryEntry: Codable, Identifiable, Equatable {
    enum Source: String, Codable { case manual, auto }

    var id = UUID()
    var term: String
    var source: Source
    var createdAt = Date()
    /// 音声認識での聞き取られ方（自動追加では直される前の語）。カンマか読点で区切って複数書ける。
    var replaced: String?

    var aliases: [String] {
        (replaced ?? "").split(whereSeparator: { ",、，".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != term }
    }
}

enum DictionaryFilter: String, CaseIterable, Identifiable {
    case all, auto, manual
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return t("すべて", "All")
        case .auto: return t("自動追加", "Auto-added")
        case .manual: return t("手動追加", "Manually added")
        }
    }
}

/// 個人辞書。音声認識のヒント（contextual strings / prompt）と整形時の綴り指定に使う。
@MainActor
final class DictionaryStore: ObservableObject {
    static let shared = DictionaryStore()
    private static let fileName = "dictionary.json"

    @Published private(set) var entries: [DictionaryEntry] = []

    private init() {
        entries = Storage.load([DictionaryEntry].self, from: Self.fileName) ?? []
    }

    var terms: [String] { entries.map(\.term) }

    /// 聞き取られ方 → 正しい表記（認識結果の置き換えに使う）
    var aliases: [String: String] {
        var map: [String: String] = [:]
        for e in entries.reversed() {
            for a in e.aliases { map[a] = e.term }
        }
        return map
    }

    @discardableResult
    func add(_ term: String, source: DictionaryEntry.Source, replaced: String? = nil) -> Bool {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 80 else { return false }
        let r = replaced?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let i = entries.firstIndex(where: { $0.term == trimmed }) {
            // 既にある語なら、新しい聞き取られ方だけを足す
            guard let r, !r.isEmpty, !entries[i].aliases.contains(r) else { return false }
            entries[i].replaced = (entries[i].aliases + [r]).joined(separator: ", ")
            save()
            return false
        }
        entries.insert(DictionaryEntry(term: trimmed, source: source, replaced: r?.isEmpty == true ? nil : r), at: 0)
        save()
        return true
    }

    func update(_ entry: DictionaryEntry, term: String, replaced: String? = nil) {
        guard let i = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        entries[i].term = trimmed
        if let replaced {
            let r = replaced.trimmingCharacters(in: .whitespacesAndNewlines)
            entries[i].replaced = r.isEmpty ? nil : r
        }
        save()
    }

    func delete(_ entry: DictionaryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    /// CSV を取り込む。1 列目を単語として扱い、見出し行（"word" / "term" / "単語"）は飛ばす。
    @discardableResult
    func importCSV(_ text: String) -> Int {
        var count = 0
        for term in Self.parseCSV(text) where add(term, source: .manual) {
            count += 1
        }
        return count
    }

    func exportCSV() -> String {
        "term,source\n" + entries.map { "\(Self.csvEscape($0.term)),\($0.source.rawValue)" }.joined(separator: "\n") + "\n"
    }

    nonisolated static func parseCSV(_ text: String) -> [String] {
        var result: [String] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            var first: String
            if trimmed.hasPrefix("\"") {
                var value = ""
                var i = trimmed.index(after: trimmed.startIndex)
                while i < trimmed.endIndex {
                    let c = trimmed[i]
                    if c == "\"" {
                        let next = trimmed.index(after: i)
                        if next < trimmed.endIndex, trimmed[next] == "\"" {
                            value.append("\"")
                            i = trimmed.index(after: next)
                            continue
                        }
                        break
                    }
                    value.append(c)
                    i = trimmed.index(after: i)
                }
                first = value
            } else {
                first = String(trimmed.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
            }
            first = first.trimmingCharacters(in: .whitespaces)
            if ["word", "term", "単語", "words", "terms"].contains(first.lowercased()) { continue }
            if !first.isEmpty { result.append(first) }
        }
        return result
    }

    nonisolated private static func csvEscape(_ s: String) -> String {
        s.contains(",") || s.contains("\"") ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }

    private func save() {
        Storage.save(entries, to: Self.fileName)
    }
}
