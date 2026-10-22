import Foundation
import Testing
@testable import Koebumi

@Suite struct StorageMigrationTests {
    private let fm = FileManager.default

    private func makeBase() throws -> URL {
        let base = fm.temporaryDirectory.appendingPathComponent("koebumi-migration-\(UUID().uuidString)")
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func write(_ text: String, _ url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    @Test func copiesSpeakDataAndKeepsTheOriginal() throws {
        let base = try makeBase()
        defer { try? fm.removeItem(at: base) }
        let legacy = base.appendingPathComponent("Speak")
        let dir = base.appendingPathComponent("Koebumi")
        try write("{}", legacy.appendingPathComponent("settings.json"))
        try write("[]", legacy.appendingPathComponent("history.json"))
        try write("wav", legacy.appendingPathComponent("Audio/a.wav"))

        #expect(Storage.migrateLegacyRoot(from: legacy, to: dir))
        #expect(try read(dir.appendingPathComponent("settings.json")) == "{}")
        #expect(try read(dir.appendingPathComponent("history.json")) == "[]")
        #expect(try read(dir.appendingPathComponent("Audio/a.wav")) == "wav")
        #expect(fm.fileExists(atPath: legacy.appendingPathComponent("settings.json").path))
    }

    @Test func fillsFoldersCreatedBeforeTheMigration() throws {
        // 先に Koebumi が録音の置き場所だけ作っていても、Speak の録音を写す
        let base = try makeBase()
        defer { try? fm.removeItem(at: base) }
        let legacy = base.appendingPathComponent("Speak")
        let dir = base.appendingPathComponent("Koebumi")
        try write("{}", legacy.appendingPathComponent("settings.json"))
        try write("old", legacy.appendingPathComponent("Audio/a.wav"))
        try write("new", dir.appendingPathComponent("Audio/b.wav"))

        #expect(Storage.migrateLegacyRoot(from: legacy, to: dir))
        #expect(try read(dir.appendingPathComponent("Audio/a.wav")) == "old")
        #expect(try read(dir.appendingPathComponent("Audio/b.wav")) == "new")
    }

    @Test func keepsExistingKoebumiSettings() throws {
        let base = try makeBase()
        defer { try? fm.removeItem(at: base) }
        let legacy = base.appendingPathComponent("Speak")
        let dir = base.appendingPathComponent("Koebumi")
        try write("old", legacy.appendingPathComponent("settings.json"))
        try write("old", legacy.appendingPathComponent("history.json"))
        try write("new", dir.appendingPathComponent("settings.json"))

        #expect(!Storage.migrateLegacyRoot(from: legacy, to: dir))
        #expect(try read(dir.appendingPathComponent("settings.json")) == "new")
        #expect(!fm.fileExists(atPath: dir.appendingPathComponent("history.json").path))
    }

    @Test func ignoresFolderWithoutSpeakSettings() throws {
        // 別のアプリが同じ名前のフォルダを使っていても、Speak の設定ファイルがなければ触らない
        let base = try makeBase()
        defer { try? fm.removeItem(at: base) }
        let legacy = base.appendingPathComponent("Speak")
        let dir = base.appendingPathComponent("Koebumi")
        try write("", legacy.appendingPathComponent("other.db"))

        #expect(!Storage.migrateLegacyRoot(from: legacy, to: dir))
        #expect(!fm.fileExists(atPath: dir.path))
    }
}
