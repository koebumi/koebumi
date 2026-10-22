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

    @Published private(set) var entries: [DictionaryEntry] = []
    /// nil ならファイルに読み書きしない（テスト用）
    private let fileName: String?

    init(fileName: String? = "dictionary.json") {
        self.fileName = fileName
        entries = fileName.flatMap { Storage.load([DictionaryEntry].self, from: $0) } ?? []
    }

    var terms: [String] { entries.map(\.term) }

    /// 聞き取られ方 → 正しい表記（認識結果の置き換えに使う）。
    /// 自動追加の語は、漢字・ひらがなの聞き取られ方では置き換えない（「公園 → 講演」のような同音語の直しは文脈次第のため）。
    var aliases: [String: String] {
        allAliases.filter { alias, _ in
            entries.contains { $0.source == .manual && $0.aliases.contains(alias) } || !Self.needsContext(alias)
        }
    }

    /// 置き換えずに、AI に文脈を見て直してもらう聞き取られ方
    var aliasHints: [String: String] {
        allAliases.filter { alias, _ in aliases[alias] == nil }
    }

    private var allAliases: [String: String] {
        var map: [String: String] = [:]
        for e in entries.reversed() {
            for a in e.aliases { map[a] = e.term }
        }
        return map
    }

    /// 漢字・ひらがなを含む（同音語がありうる）
    nonisolated static func needsContext(_ alias: String) -> Bool {
        alias.contains { [.han, .kana].contains(CharClass($0)) && !CharClass.isKatakana($0) }
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

    /// 直した語を自動で追加する。辞書が変わったら true（取り消せるのは、ここで変えたものだけ）。
    /// 逆向きの直し（前に覚えた A → B を、B → A と直した）は新しい方を残す。置き換えが行ったり来たりしないように。
    @discardableResult
    func learn(_ term: String, replaced: String) -> Bool {
        if entries.contains(where: { $0.source == .manual && $0.term == replaced && $0.aliases.contains(term) }) { return false }
        let before = entries
        if removeAlias(term, from: replaced) { save() }
        add(term, source: .auto, replaced: replaced)
        return entries != before
    }

    /// 自動で追加した直しを取り消す（同じ入力の中で、その語をさらに直したか、元に戻したとき）
    func forget(_ term: String, replaced: String) {
        if removeAlias(replaced, from: term) { save() }
    }

    /// 自動で追加した語から聞き取られ方を外す。ほかに聞き取られ方がなければ語ごと消す
    private func removeAlias(_ alias: String, from term: String) -> Bool {
        guard let i = entries.firstIndex(where: { $0.term == term && $0.source == .auto }),
              entries[i].aliases.contains(alias) else { return false }
        let rest = entries[i].aliases.filter { $0 != alias }
        if rest.isEmpty {
            entries.remove(at: i)
        } else {
            entries[i].replaced = rest.joined(separator: ", ")
        }
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

    /// CSV を取り込む。1 列目を単語、3 列目を聞き取られ方として扱い、見出し行（"word" / "term" / "単語"）は飛ばす。
    @discardableResult
    func importCSV(_ text: String) -> Int {
        var count = 0
        for row in Self.parseCSVRows(text) where add(row.term, source: .manual, replaced: row.heard) {
            count += 1
        }
        return count
    }

    func exportCSV() -> String {
        "term,source,heard_as\n" + entries.map {
            "\(Self.csvEscape($0.term)),\($0.source.rawValue),\(Self.csvEscape($0.replaced ?? ""))"
        }.joined(separator: "\n") + "\n"
    }

    nonisolated static func parseCSV(_ text: String) -> [String] {
        parseCSVRows(text).map(\.term)
    }

    nonisolated static func parseCSVRows(_ text: String) -> [(term: String, heard: String?)] {
        var result: [(String, String?)] = []
        for line in text.components(separatedBy: .newlines) {
            let fields = csvFields(line.trimmingCharacters(in: .whitespaces)).map { $0.trimmingCharacters(in: .whitespaces) }
            guard let first = fields.first, !first.isEmpty else { continue }
            if ["word", "term", "単語", "words", "terms"].contains(first.lowercased()) { continue }
            let heard = fields.count >= 3 && !fields[2].isEmpty ? fields[2] : nil
            result.append((first, heard))
        }
        return result
    }

    /// 1 行をカンマで区切る（"..." で囲んだ値の中のカンマと "" に対応）
    nonisolated private static func csvFields(_ line: String) -> [String] {
        var fields: [String] = []
        var value = ""
        var quoted = false
        var chars = line.makeIterator()
        var pending: Character? = nil
        while let c = pending ?? chars.next() {
            pending = nil
            if quoted {
                if c == "\"" {
                    if let next = chars.next() {
                        if next == "\"" { value.append("\"") } else { quoted = false; pending = next }
                    } else {
                        quoted = false
                    }
                } else {
                    value.append(c)
                }
            } else if c == "\"" && value.isEmpty {
                quoted = true
            } else if c == "," {
                fields.append(value)
                value = ""
            } else {
                value.append(c)
            }
        }
        if !line.isEmpty { fields.append(value) }
        return fields
    }

    nonisolated private static func csvEscape(_ s: String) -> String {
        s.contains(",") || s.contains("\"") ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }

    private func save() {
        guard let fileName else { return }
        Storage.save(entries, to: fileName)
    }
}
