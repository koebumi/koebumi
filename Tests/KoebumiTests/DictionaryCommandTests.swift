import Foundation
import Testing
@testable import Koebumi

@MainActor @Suite struct DictionaryCommandTests {
    private let fm = FileManager.default

    private func makeDir() throws -> URL {
        let dir = fm.temporaryDirectory.appendingPathComponent("koebumi-dictionary-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func registersTermsAndNewHeardAs() {
        let store = DictionaryStore(file: nil)
        #expect(store.register("Koebumi", heard: ["コエブミ"]) == .added)
        #expect(store.register("Koebumi", heard: ["コエブミ", "声文、こえぶみ"]) == .addedHeard(["声文", "こえぶみ"]))
        #expect(store.register("Koebumi", heard: ["Koebumi"]) == .unchanged)
        #expect(store.register(" ", heard: []) == .invalid)
        #expect(store.register(String(repeating: "a", count: 81), heard: []) == .invalid)
        #expect(store.entries.map(\.aliases) == [["コエブミ", "声文", "こえぶみ"]])
        #expect(store.entries.first?.source == .manual)
    }

    @Test func keepsWordsAnotherProcessAdded() throws {
        let dir = try makeDir()
        defer { try? fm.removeItem(at: dir) }
        let file = dir.appendingPathComponent("dictionary.json")
        let app = DictionaryStore(file: file)
        app.add("Claude Code", source: .manual, replaced: "クロードコード")

        // アプリが動いている間に、CLI が別のプロセスで語を足す
        let cli = DictionaryStore(file: file)
        #expect(cli.register("DictationController", heard: ["ディクテーションコントローラー"]) == .added)

        // アプリが自動で語を覚えても、CLI が足した語を古い一覧で上書きしない
        #expect(app.learn("田中", replaced: "棚香"))
        #expect(Set(DictionaryStore(file: file).terms) == ["Claude Code", "DictationController", "田中"])

        #expect(cli.remove(term: "田中"))
        app.reloadIfChanged()
        #expect(Set(app.terms) == ["Claude Code", "DictationController"])
    }

    @Test func reloadsWhenTheCommandAnnouncesAChange() async throws {
        let dir = try makeDir()
        defer { try? fm.removeItem(at: dir) }
        let file = dir.appendingPathComponent("dictionary.json")
        let app = DictionaryStore(file: file)
        app.observeOtherProcesses()

        DictionaryStore(file: file).register("Koebumi", heard: ["コエブミ"])
        DictionaryStore.announceChange()
        for _ in 0..<40 where app.terms.isEmpty {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(app.terms == ["Koebumi"])
    }

    @Test func parsesAndListsTheSameSyntax() {
        #expect(DictionaryCommand.parse("Claude Code = クロードコード | クロード・コード ").term == "Claude Code")
        #expect(DictionaryCommand.parse("Claude Code=クロードコード|クロード・コード").heard == ["クロードコード", "クロード・コード"])
        #expect(DictionaryCommand.parse("Koebumi").heard.isEmpty)
        #expect(DictionaryCommand.parse("=フー").term.isEmpty)

        let store = DictionaryStore(file: nil)
        store.add("Koebumi", source: .manual)
        store.learn("田中", replaced: "棚香")
        store.register("Claude Code", heard: ["クロードコード", "クロード・コード"])
        #expect(DictionaryCommand.listing(store.entries) == "Claude Code=クロードコード|クロード・コード\n田中=棚香\t(auto)\nKoebumi\n")
    }

    @Test func installsUpdatesAndRemovesOnlyItsOwnSkill() throws {
        let home = try makeDir()
        defer { try? fm.removeItem(at: home) }
        let app = "/Applications/Koebumi.app/Contents/MacOS/Koebumi"
        #expect(DictionarySkill.status(executable: app, home: home.path) == .notInstalled)

        try DictionarySkill.install(executable: app, home: home.path)
        #expect(DictionarySkill.status(executable: app, home: home.path) == .installed)
        let text = try String(contentsOf: DictionarySkill.file(home: home.path), encoding: .utf8)
        #expect(text.hasPrefix("---\nname: koebumi-dictionary\n"))
        #expect(text.contains("'\(app)' --dictionary list"))

        // アプリを動かしたら、起動したときに新しいパスで書き直す
        let moved = "/Users/me/Apps/Koebumi.app/Contents/MacOS/Koebumi"
        #expect(DictionarySkill.status(executable: moved, home: home.path) == .outdated)
        DictionarySkill.refreshIfInstalled(executable: moved, home: home.path)
        #expect(DictionarySkill.status(executable: moved, home: home.path) == .installed)

        try DictionarySkill.uninstall(home: home.path)
        #expect(DictionarySkill.status(executable: moved, home: home.path) == .notInstalled)

        // ユーザーが自分で書いた同じ名前のスキルは、上書きも削除もしない
        let own = DictionarySkill.file(home: home.path)
        try fm.createDirectory(at: own.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("my own skill".utf8).write(to: own)
        #expect(DictionarySkill.status(executable: app, home: home.path) == .foreign)
        try DictionarySkill.install(executable: app, home: home.path)
        DictionarySkill.refreshIfInstalled(executable: app, home: home.path)
        try DictionarySkill.uninstall(home: home.path)
        #expect(try String(contentsOf: own, encoding: .utf8) == "my own skill")
    }

    @Test func quotesPathsAsOneShellWord() {
        #expect(DictionarySkill.shellQuoted("/Users/me/My Apps/Koebumi") == "'/Users/me/My Apps/Koebumi'")
        #expect(DictionarySkill.shellQuoted("/tmp/it's") == "'/tmp/it'\\''s'")
    }
}
