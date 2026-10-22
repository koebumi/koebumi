import Foundation
import Testing
@testable import Koebumi

@MainActor @Suite struct PersonalizationStoreTests {
    @Test func failedAnalysisWaitsForAnotherBatchBeforeRetrying() async {
        let engine = FakeStyleEngine(.fail)
        let store = PersonalizationStore(fileName: nil)
        for i in 0..<PersonalizationStore.batchSize { store.addSample(sample(i), engine: engine) }
        await store.analyze(engine: engine)
        #expect(engine.calls == 1)
        #expect(store.lastError != nil)

        // 失敗した直後は、話すたびに学習し直さない
        for i in 0..<PersonalizationStore.batchSize - 1 { store.addSample(sample(10 + i), engine: engine) }
        #expect(!store.isAnalyzing)
        store.addSample(sample(20), engine: engine)
        #expect(store.isAnalyzing)
        await store.analyze(engine: engine)
        #expect(engine.calls == 2)
    }

    @Test func analysisThatNeverFinishesTimesOut() async {
        let engine = FakeStyleEngine(.hang)
        let store = PersonalizationStore(fileName: nil, timeout: .milliseconds(100))
        for i in 0..<PersonalizationStore.batchSize { store.addSample(sample(i), engine: engine) }
        await store.analyze(engine: engine)
        #expect(store.lastError != nil)
        #expect(store.pendingCount == PersonalizationStore.batchSize)
    }

    @Test func cancelledAnalysisIsRetriedOnTheNextSample() async {
        let engine = FakeStyleEngine(.hang)
        let store = PersonalizationStore(fileName: nil)
        for i in 0..<PersonalizationStore.batchSize { store.addSample(sample(i), engine: engine) }
        await engine.waitForCall()
        store.cancelAnalysis()
        await store.analyze(engine: engine)
        // 取り消しは失敗ではない
        #expect(store.lastError == nil)

        store.addSample(sample(10), engine: engine)
        #expect(store.isAnalyzing)
        store.cancelAnalysis()
        await store.analyze(engine: engine)
    }

    private func sample(_ i: Int) -> StyleSample {
        StyleSample(category: .chat, text: "明日の会議の件です \(i)")
    }
}

@Suite struct StylePromptTests {
    @Test func appleStyleInstructionsDoNotShowTheJSONFormat() {
        // 書式の「"code" | "chat"」を見せると、Apple のモデルはそれをまねようとして生成が止まる
        #expect(!Prompts.styleRules.contains("|"))
        #expect(Prompts.styleSystem.hasPrefix(Prompts.styleRules))
        #expect(Prompts.styleSystem.contains("\"categories\""))
    }
}

/// 文体の分析だけをする偽の AI。.hang は取り消されるまで終わらない。
private final class FakeStyleEngine: LLMEngine, @unchecked Sendable {
    enum Behavior { case fail, hang }

    private let behavior: Behavior
    private let lock = NSLock()
    private var count = 0
    private let started: AsyncStream<Void>
    private let startedContinuation: AsyncStream<Void>.Continuation

    init(_ behavior: Behavior) {
        self.behavior = behavior
        (started, startedContinuation) = AsyncStream.makeStream()
    }

    var name: String { "Fake" }
    var supportsWebSearch: Bool { false }
    var calls: Int { lock.withLock { count } }

    func polish(_ request: PolishRequest) async throws -> String { request.transcript }
    func ask(_ request: AskRequest) async throws -> AskOutcome { .answer("") }

    func analyzeStyle(samples: [StyleSample], current: StyleProfile) async throws -> StyleAnalysis {
        lock.withLock { count += 1 }
        startedContinuation.yield()
        switch behavior {
        case .fail:
            throw LLMError.badResponse
        case .hang:
            try await Task.sleep(for: .seconds(3600))
            return StyleAnalysis(general: "", categories: [])
        }
    }

    func waitForCall() async {
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()
    }
}
