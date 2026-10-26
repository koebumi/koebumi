import Foundation

/// エージェント（Claude Code など）が辞書を読み書きするためのコマンド。メニューバーアプリを起動せずに動く。
/// 例: Koebumi --dictionary add "DictationController=ディクテーションコントローラー" "Koebumi=コエブミ|声文"
/// 書き換えたら、動いているアプリに知らせて読み直させる（DictionaryStore.changedNotification）。
@MainActor
enum DictionaryCommand {
    static let usage = """
    usage: Koebumi --dictionary list [--json]
           Koebumi --dictionary add "TERM=HEARD|HEARD" ...
           Koebumi --dictionary remove TERM ...
           Koebumi --dictionary skill
    """

    static func run(_ args: [String]) -> Int32 {
        guard let i = args.firstIndex(of: "--dictionary"), i + 1 < args.count else {
            print(usage)
            return 2
        }
        let operands = args[(i + 2)...].filter { $0 != "--json" }
        let store = DictionaryStore.shared
        switch args[i + 1] {
        case "list":
            print(args.contains("--json") ? json(store.entries) : listing(store.entries), terminator: "")
            return 0
        case "add" where !operands.isEmpty:
            var invalid = 0
            var counts: [String: Int] = [:]
            for spec in operands {
                let (term, heard) = parse(spec)
                let line: String
                switch store.register(term, heard: heard) {
                case .added:
                    let aliases = store.entries.first { $0.term == term }?.aliases ?? []
                    line = "added: \(term)" + (aliases.isEmpty ? "" : " (heard as \(aliases.joined(separator: ", ")))")
                    counts["added", default: 0] += 1
                case .addedHeard(let new):
                    line = "added heard-as: \(term) (+ \(new.joined(separator: ", ")))"
                    counts["updated", default: 0] += 1
                case .unchanged:
                    line = "unchanged: \(term) (already registered)"
                    counts["unchanged", default: 0] += 1
                case .invalid:
                    line = "invalid: \"\(spec)\" (the term must be 1 to 80 characters)"
                    invalid += 1
                }
                print(line)
            }
            print("\(counts["added"] ?? 0) added, \(counts["updated"] ?? 0) updated, \(counts["unchanged"] ?? 0) unchanged, \(invalid) invalid")
            return finish(store, changed: counts["added"] != nil || counts["updated"] != nil) && invalid == 0 ? 0 : 1
        case "remove" where !operands.isEmpty:
            var missing = 0
            for term in operands {
                if store.remove(term: term) {
                    print("removed: \(term)")
                } else {
                    print("not found: \(term)")
                    missing += 1
                }
            }
            return finish(store, changed: missing < operands.count) && missing == 0 ? 0 : 1
        case "skill":
            print(DictionarySkill.document(executable: executablePath), terminator: "")
            return 0
        default:
            print(usage)
            return 2
        }
    }

    /// このコマンドの絶対パス（スキルに書く）
    static var executablePath: String {
        Bundle.main.executablePath ?? CommandLine.arguments[0]
    }

    /// "Claude Code=クロードコード|クロード・コード" → 語と聞き取られ方
    static func parse(_ spec: String) -> (term: String, heard: [String]) {
        let parts = spec.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        let term = parts[0].trimmingCharacters(in: .whitespaces)
        let heard = parts.count == 2 ? parts[1].split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } : []
        return (term, heard)
    }

    static func listing(_ entries: [DictionaryEntry]) -> String {
        entries.map { e in
            ([e.term] + (e.aliases.isEmpty ? [] : ["=" + e.aliases.joined(separator: "|")])).joined()
                + (e.source == .auto ? "\t(auto)" : "") + "\n"
        }.joined()
    }

    static func json(_ entries: [DictionaryEntry]) -> String {
        let objects = entries.map { ["term": $0.term, "heard_as": $0.aliases, "source": $0.source.rawValue] as [String: Any] }
        guard let data = try? JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys]) else { return "[]\n" }
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    /// 書き込めたかをファイルから読み直して確かめ、動いているアプリに知らせる。書き込めなければ false
    private static func finish(_ store: DictionaryStore, changed: Bool) -> Bool {
        guard changed else { return true }
        let file = Storage.file("dictionary.json")
        // 日付は秒未満が保存されないので、語と聞き取られ方だけを比べる
        let saved = Storage.load([DictionaryEntry].self, at: file) ?? []
        guard saved.map({ [$0.term, $0.replaced ?? ""] }) == store.entries.map({ [$0.term, $0.replaced ?? ""] }) else {
            print("could not save \(file.path)")
            return false
        }
        DictionaryStore.announceChange()
        return true
    }
}
