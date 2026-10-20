import Combine
import Foundation

struct CategoryProfile: Codable, Equatable {
    var formality: Int
    var verbosity: Int
    var notes: String
}

/// 学習した文体。内容そのものは保存せず、抽象的な傾向だけを持つ。
struct StyleProfile: Codable, Equatable {
    var general: String = ""
    var categories: [String: CategoryProfile] = [:]
    var samplesAnalyzed: Int = 0
    var updatedAt: Date?

    func promptDescription(for category: AppCategory) -> String? {
        var parts: [String] = []
        if let c = categories[category.rawValue] {
            parts.append("formality \(c.formality)/100, verbosity \(c.verbosity)/100. \(c.notes)")
        }
        if !general.isEmpty { parts.append(general) }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

/// ユーザーが出力を直した例（履歴のフィードバックから作る）
struct Correction: Codable, Equatable {
    var original: String
    var preferred: String
}

private struct PersonalizationData: Codable {
    var profile = StyleProfile()
    var pending: [StyleSample] = []
    var corrections: [Correction] = []
}

@MainActor
final class PersonalizationStore: ObservableObject {
    static let shared = PersonalizationStore()
    private static let fileName = "personalization.json"
    /// この数だけサンプルが溜まったら文体を学習し、サンプルは捨てる
    static let batchSize = 6
    /// 学習の進み具合を 100% とみなすサンプル数
    static let fullProgressSamples = 60

    @Published private(set) var profile = StyleProfile()
    @Published private(set) var corrections: [Correction] = []
    @Published private(set) var pendingCount = 0
    @Published private(set) var isAnalyzing = false
    @Published var lastError: String?

    private var pending: [StyleSample] = []

    private init() {
        let data = Storage.load(PersonalizationData.self, from: Self.fileName) ?? PersonalizationData()
        profile = data.profile
        pending = data.pending
        corrections = data.corrections
        pendingCount = pending.count
    }

    var progress: Double {
        min(1, Double(profile.samplesAnalyzed + pending.count) / Double(Self.fullProgressSamples))
    }

    func addSample(_ sample: StyleSample, engine: LLMEngine?) {
        guard sample.text.count >= 8 else { return }
        pending.append(sample)
        pendingCount = pending.count
        save()
        if pending.count >= Self.batchSize, let engine {
            Task { await analyze(engine: engine) }
        }
    }

    func addCorrection(_ c: Correction) {
        guard c.original != c.preferred else { return }
        corrections.append(c)
        if corrections.count > 30 { corrections.removeFirst(corrections.count - 30) }
        save()
    }

    func analyze(engine: LLMEngine) async {
        guard !isAnalyzing, !pending.isEmpty else { return }
        isAnalyzing = true
        defer { isAnalyzing = false }
        let batch = pending
        do {
            let result = try await engine.analyzeStyle(samples: batch, current: profile)
            apply(result, sampleCount: batch.count)
            pending.removeFirst(min(batch.count, pending.count))
            pendingCount = pending.count
            lastError = nil
            save()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func apply(_ result: StyleAnalysis, sampleCount: Int) {
        if !result.general.isEmpty { profile.general = result.general }
        for c in result.categories {
            guard AppCategory(rawValue: c.category) != nil else { continue }
            profile.categories[c.category] = CategoryProfile(
                formality: max(0, min(100, c.formality)),
                verbosity: max(0, min(100, c.verbosity)),
                notes: c.notes
            )
        }
        profile.samplesAnalyzed += sampleCount
        profile.updatedAt = Date()
    }

    func reset() {
        profile = StyleProfile()
        pending = []
        corrections = []
        pendingCount = 0
        save()
    }

    private func save() {
        Storage.save(PersonalizationData(profile: profile, pending: pending, corrections: corrections), to: Self.fileName)
    }
}
