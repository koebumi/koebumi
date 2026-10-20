import Foundation

/// アプリのローカルデータ置き場。すべて ~/Library/Application Support/Speak 以下に保存する。
enum Storage {
    static var rootOverride: URL?

    static var root: URL {
        if let rootOverride { return rootOverride }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Speak", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
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
        guard let data = try? Data(contentsOf: file(name)) else { return nil }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            NSLog("Speak: failed to decode \(name): \(error)")
            return nil
        }
    }

    static func save<T: Encodable>(_ value: T, to name: String) {
        do {
            let data = try encoder.encode(value)
            try data.write(to: file(name), options: [.atomic])
        } catch {
            NSLog("Speak: failed to save \(name): \(error)")
        }
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: root)
    }
}
