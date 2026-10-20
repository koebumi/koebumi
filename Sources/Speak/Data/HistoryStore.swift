import Combine
import Foundation

struct HistoryItem: Codable, Identifiable, Equatable {
    enum Status: String, Codable { case success, failed }

    var id = UUID()
    var date = Date()
    var mode: Mode
    var status: Status = .success
    var rawTranscript: String = ""
    var output: String = ""
    var errorMessage: String?
    var appName: String = ""
    var appBundleID: String?
    var category: AppCategory = .other
    var duration: TimeInterval = 0
    var wordCount: Int = 0
    var language: String?
    var targetLanguage: String?
    var selectedText: String?
    var askAction: String?  // answer / replace / insert / open_url
    var audioFile: String?
    var feedback: String?

    var audioURL: URL? { audioFile.map { Storage.audioDir.appendingPathComponent($0) } }
}

enum HistoryFilter: String, CaseIterable, Identifiable {
    case all, dictations, ask
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return t("すべて", "All")
        case .dictations: return t("ディクテーション", "Dictations")
        case .ask: return "Ask anything"
        }
    }

    func includes(_ item: HistoryItem) -> Bool {
        switch self {
        case .all: return true
        case .dictations: return item.mode != .ask
        case .ask: return item.mode == .ask
        }
    }
}

/// 履歴はこの Mac の中だけに保存する。保存期間を過ぎたものは音声ごと削除する。
@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()
    private static let fileName = "history.json"

    @Published private(set) var items: [HistoryItem] = []

    private init() {
        items = Storage.load([HistoryItem].self, from: Self.fileName) ?? []
    }

    func add(_ item: HistoryItem, retention: Retention) {
        guard retention != .never else {
            if let url = item.audioURL { try? FileManager.default.removeItem(at: url) }
            return
        }
        items.insert(item, at: 0)
        save()
    }

    func update(_ item: HistoryItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i] = item
        save()
    }

    func delete(_ item: HistoryItem) {
        if let url = item.audioURL { try? FileManager.default.removeItem(at: url) }
        items.removeAll { $0.id == item.id }
        save()
    }

    func deleteAll() {
        for item in items {
            if let url = item.audioURL { try? FileManager.default.removeItem(at: url) }
        }
        items = []
        save()
    }

    func prune(retention: Retention, now: Date = Date()) {
        guard let interval = retention.interval else { return }
        let cutoff = now.addingTimeInterval(-interval)
        let expired = items.filter { $0.date < cutoff }
        guard !expired.isEmpty else { return }
        for item in expired {
            if let url = item.audioURL { try? FileManager.default.removeItem(at: url) }
        }
        items.removeAll { $0.date < cutoff }
        save()
    }

    var lastOutput: String? {
        items.first { $0.status == .success && !$0.output.isEmpty }?.output
    }

    private func save() {
        Storage.save(items, to: Self.fileName)
    }

    nonisolated static func saveAudio(_ audio: RecordedAudio, id: UUID) -> String? {
        let name = "\(id.uuidString).wav"
        do {
            try WAV.encode(audio).write(to: Storage.audioDir.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }
}
