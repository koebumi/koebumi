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
    /// nil ならファイルに読み書きしない（テスト用）
    private let fileName: String?
    /// 学習の時間の上限。普段は数秒で終わる。オンデバイスのモデルは一度に 1 件しか処理しないので、長引くとその間の整形を待たせる。
    private let timeout: Duration
    /// 学習に失敗したら、サンプルがこの数まで溜まるまで自動では学習し直さない（話すたびに失敗する学習を繰り返さない）
    private var nextAutoAnalysis = batchSize
    private var analysisTask: Task<Void, Never>?

    init(fileName: String? = "personalization.json", timeout: Duration = .seconds(30)) {
        self.fileName = fileName
        self.timeout = timeout
        let data = fileName.flatMap { Storage.load(PersonalizationData.self, from: $0) } ?? PersonalizationData()
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
        if pending.count >= nextAutoAnalysis, let engine { startAnalysis(engine: engine) }
    }

    func addCorrection(_ c: Correction) {
        guard c.original != c.preferred else { return }
        corrections.append(c)
        if corrections.count > 30 { corrections.removeFirst(corrections.count - 30) }
        save()
    }

    /// 学習して、終わるまで待つ（すでに学習中なら、その学習の終わりを待つ）
    func analyze(engine: LLMEngine) async {
        startAnalysis(engine: engine)
        await analysisTask?.value
    }

    /// 学習を裏で始める
    func startAnalysis(engine: LLMEngine) {
        guard !isAnalyzing, !pending.isEmpty else { return }
        isAnalyzing = true
        analysisTask = Task {
            await run(engine: engine)
            isAnalyzing = false
        }
    }

    /// 学習を取り消す。録音を始めたときに呼び、その録音の整形を学習の後ろで待たせない。取り消した学習は次に話したときにやり直す。
    func cancelAnalysis() {
        analysisTask?.cancel()
    }

    private func run(engine: LLMEngine) async {
        let batch = pending
        let current = profile
        do {
            let result = try await Self.withTimeout(timeout) { try await engine.analyzeStyle(samples: batch, current: current) }
            apply(result, sampleCount: batch.count)
            pending.removeFirst(min(batch.count, pending.count))
            pendingCount = pending.count
            nextAutoAnalysis = Self.batchSize
            lastError = nil
            save()
        } catch {
            if Task.isCancelled { return }
            lastError = error.localizedDescription
            nextAutoAnalysis = pending.count + Self.batchSize
        }
    }

    /// body が limit までに終わらなければ取り消して、時間切れのエラーを投げる
    private static func withTimeout<T: Sendable>(_ limit: Duration, _ body: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await body() }
            group.addTask {
                try await Task.sleep(for: limit)
                throw LLMError.unavailable(t("文体の学習が時間内に終わりませんでした", "Style learning timed out"))
            }
            defer { group.cancelAll() }
            return try await group.next()!
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
        guard let fileName else { return }
        Storage.save(PersonalizationData(profile: profile, pending: pending, corrections: corrections), to: fileName)
    }
}
