import Foundation

/// アプリのローカルデータ置き場。すべて ~/Library/Application Support/Koebumi 以下に保存する。
enum Storage {
    static var rootOverride: URL?

    static var root: URL {
        if let rootOverride { return rootOverride }
        let dir = base.appendingPathComponent("Koebumi", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var base: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// アプリの起動時に、設定を読む前に呼ぶ（開発用の CLI やテストでは写さない）
    static func migrateFromSpeak() -> Bool {
        guard rootOverride == nil else { return false }
        return migrateLegacyRoot(from: base.appendingPathComponent("Speak", isDirectory: true),
                                 to: base.appendingPathComponent("Koebumi", isDirectory: true))
    }

    /// Speak という名前だったころのデータ（設定・履歴・辞書・学習内容）を、新しい置き場所に写す。写したら true を返す。
    /// 新しい置き場所に設定ファイルがまだなく、古い置き場所に Speak の設定ファイルがあるときだけ写す。
    /// 古い置き場所は消さない（Speak.app がまだ動いていても困らないように）。設定ファイルを最後に写すので、途中で失敗しても次の起動で続きを写す
    @discardableResult
    static func migrateLegacyRoot(from legacy: URL, to dir: URL) -> Bool {
        let fm = FileManager.default
        let settings = "settings.json"
        guard !fm.fileExists(atPath: dir.appendingPathComponent(settings).path),
              fm.fileExists(atPath: legacy.appendingPathComponent(settings).path),
              let items = try? fm.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil)
        else { return false }
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for item in items.sorted(by: { $0.lastPathComponent != settings && $1.lastPathComponent == settings }) {
                try copyMissing(from: item, to: dir.appendingPathComponent(item.lastPathComponent))
            }
            return true
        } catch {
            NSLog("Koebumi: failed to copy data from Speak: \(error)")
            return false
        }
    }

    /// 写し先にないものだけを写す。フォルダが先にできていたら（録音の置き場所など）、中身を 1 つずつ写す
    private static func copyMissing(from source: URL, to dest: URL) throws {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: dest.path, isDirectory: &isDirectory) else {
            try fm.copyItem(at: source, to: dest)
            return
        }
        guard isDirectory.boolValue else { return }
        for item in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
            try copyMissing(from: item, to: dest.appendingPathComponent(item.lastPathComponent))
        }
    }

    static var audioDir: URL {
        let dir = root.appendingPathComponent("Audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func file(_ name: String) -> URL {
        root.appendingPathComponent(name)
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        load(type, at: file(name))
    }

    static func load<T: Decodable>(_ type: T.Type, at url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            NSLog("Koebumi: failed to decode \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    static func save<T: Encodable>(_ value: T, to name: String) {
        save(value, at: file(name))
    }

    static func save<T: Encodable>(_ value: T, at url: URL) {
        do {
            let data = try encoder.encode(value)
            try data.write(to: url, options: [.atomic])
        } catch {
            NSLog("Koebumi: failed to save \(url.lastPathComponent): \(error)")
        }
    }

    /// ファイルの更新日時（ないときは nil）。ほかのプロセスが書き換えたかを見分けるのに使う
    static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: root)
    }
}
