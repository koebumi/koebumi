import Foundation
import FoundationModels

@Generable
struct AppleAskDecision {
    @Guide(description: "What to do", .anyOf(["answer", "replace", "insert", "open_url"]))
    var action: String
    @Guide(description: "The answer, the replacement for the selection, the text to insert, or for open_url a short description")
    var text: String
    @Guide(description: "For open_url, the URL to open. Otherwise an empty string.")
    var url: String
}

@Generable
struct AppleCategoryStyle {
    @Guide(description: "App category", .anyOf(["email", "chat", "document", "code", "ai", "other"]))
    var category: String
    @Guide(description: "0 = very casual, 100 = very formal", .range(0...100))
    var formality: Int
    @Guide(description: "0 = very concise, 100 = very detailed", .range(0...100))
    var verbosity: Int
    @Guide(description: "Abstract style notes in English, at most 25 words")
    var notes: String
}

@Generable
struct AppleStyleAnalysis {
    @Guide(description: "Overall abstract style summary in English, at most 30 words")
    var general: String
    var categories: [AppleCategoryStyle]
}

/// Apple Intelligence のオンデバイスモデル（キー不要・オフライン）。
/// Private Cloud Compute は Apple の申請制 entitlement がないと実行時に落ちるため使わない。
struct AppleLLMEngine: LLMEngine {
    var name: String { t("Apple オンデバイス", "Apple on-device") }
    var supportsWebSearch: Bool { false }

    static var onDeviceStatus: String? {
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(.appleIntelligenceNotEnabled):
            return t("Apple Intelligence がオフです（システム設定 > Apple Intelligence と Siri）", "Apple Intelligence is turned off (System Settings > Apple Intelligence & Siri)")
        case .unavailable(.modelNotReady):
            return t("Apple のモデルを準備中です。しばらく待ってください", "Apple's model is still downloading")
        case .unavailable(.deviceNotEligible):
            return t("この Mac は Apple Intelligence に対応していません", "This Mac does not support Apple Intelligence")
        case .unavailable:
            return t("Apple のモデルを利用できません", "Apple's model is unavailable")
        }
    }

    private static func model() -> SystemLanguageModel {
        // 書き起こしの整形は「入力文の変換」なので、変換向けの緩いガードレールを使う
        SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
    }

    private func makeSession(instructions: String) throws -> LanguageModelSession {
        if let status = Self.onDeviceStatus { throw LLMError.unavailable(status) }
        return LanguageModelSession(model: Self.model(), instructions: instructions)
    }

    /// 整形用のセッション。小さいモデルは指示文より実例に従うので、例を会話の往復として先に入れておく。
    private static func makePolishSession(mode: Mode, examples: [Prompts.Example]) -> LanguageModelSession {
        let system = mode == .translate ? Prompts.translateRules : Prompts.polishRules
        var entries: [Transcript.Entry] = [
            .instructions(Transcript.Instructions(segments: [.text(.init(content: system))], toolDefinitions: [])),
        ]
        for e in examples {
            entries.append(.prompt(Transcript.Prompt(segments: [.text(.init(content: Prompts.exampleUser(e)))])))
            entries.append(.response(Transcript.Response(assetIDs: [], segments: [.text(.init(content: e.output))])))
        }
        return LanguageModelSession(model: model(), tools: [], transcript: Transcript(entries: entries))
    }

    /// 録音を始めたときに呼ぶ。モデルと例の読み込みを済ませておき、話し終えてからの待ち時間を減らす。
    static func prewarm(mode: Mode, language: String) {
        guard onDeviceStatus == nil, mode != .ask else { return }
        let probe = PolishRequest(transcript: "", mode: mode, sourceLanguages: [language], targetLanguage: nil, appName: "",
                                  category: .other, styleDescription: "", personalStyle: nil, vocabulary: [], corrections: [])
        let examples = Prompts.examples(for: probe)
        let session = makePolishSession(mode: mode, examples: examples)
        session.prewarm()
        SessionCache.shared.put(session, key: SessionCache.key(mode: mode, examples: examples))
    }

    func polish(_ request: PolishRequest) async throws -> String {
        if let status = Self.onDeviceStatus { throw LLMError.unavailable(status) }
        let examples = Prompts.examples(for: request)
        let key = SessionCache.key(mode: request.mode, examples: examples)
        // 長い書き起こしは文の切れ目で分けて整形する（コンテキストに収め、途中で切れないようにする）
        let limit = SystemLanguageModel.default.contextSize >= 8192 ? 1500 : 600
        let parts = Prompts.split(request.transcript, limit: limit)
        var outputs: [String] = []
        for part in parts {
            try Task.checkCancellation()
            guard !part.text.isEmpty else {
                outputs.append(part.separator)
                continue
            }
            var r = request
            r.transcript = part.text
            let session = SessionCache.shared.take(key: key) ?? Self.makePolishSession(mode: request.mode, examples: examples)
            let options = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: part.text.count * 3 + 200)
            let prompt = Prompts.smallModelUser(r)
            let text = try await mapErrors {
                Prompts.cleanOutput(try await session.respond(to: prompt, options: options).content)
            }
            outputs.append(text + part.separator)
        }
        return outputs.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func ask(_ request: AskRequest) async throws -> AskOutcome {
        let session = try makeSession(instructions: Prompts.askSystemCommon)
        let outcome = try await mapErrors {
            let response = try await session.respond(to: Prompts.askUser(request), generating: AppleAskDecision.self)
            let d = response.content
            return Prompts.outcome(action: d.action, text: d.text, url: d.url, request: request)
        }
        // 書き換えは、決めるときに一緒に書いた文より、例を見せて書き換えだけをさせた方が意味を変えない
        guard case .replace = outcome, let selection = request.selection else { return outcome }
        let rewritten = try await rewrite(selection: selection, request: request.query)
        if rewritten.isEmpty || Prompts.changesLanguage(selection: selection, output: rewritten, request: request.query) {
            return outcome
        }
        return .replace(rewritten)
    }

    private func rewrite(selection: String, request: String) async throws -> String {
        var entries: [Transcript.Entry] = [
            .instructions(Transcript.Instructions(segments: [.text(.init(content: Prompts.rewriteRules))], toolDefinitions: [])),
        ]
        for e in Prompts.rewriteExamples {
            entries.append(.prompt(Transcript.Prompt(segments: [.text(.init(content: Prompts.rewriteUser(selection: e.selection, request: e.request)))])))
            entries.append(.response(Transcript.Response(assetIDs: [], segments: [.text(.init(content: e.output))])))
        }
        let session = LanguageModelSession(model: Self.model(), tools: [], transcript: Transcript(entries: entries))
        let options = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: selection.count * 3 + 200)
        return try await mapErrors {
            Prompts.cleanOutput(try await session.respond(to: Prompts.rewriteUser(selection: selection, request: request), options: options).content)
        }
    }

    func analyzeStyle(samples: [StyleSample], current: StyleProfile) async throws -> StyleAnalysis {
        let session = try makeSession(instructions: Prompts.styleSystem)
        return try await mapErrors {
            let response = try await session.respond(to: Prompts.styleUser(samples: samples, current: current), generating: AppleStyleAnalysis.self)
            let a = response.content
            return StyleAnalysis(
                general: a.general,
                categories: a.categories.map {
                    CategoryStyleAnalysis(category: $0.category, formality: $0.formality, verbosity: $0.verbosity, notes: $0.notes)
                }
            )
        }
    }

    private func mapErrors<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize: throw LLMError.contextTooLong
            case .guardrailViolation, .refusal: throw LLMError.refused
            default: throw LLMError.unavailable(error.localizedDescription)
            }
        }
    }
}

/// prewarm したセッションを、次の整形まで 1 つだけ預かる
final class SessionCache: @unchecked Sendable {
    static let shared = SessionCache()
    private let lock = NSLock()
    private var stored: (key: String, session: LanguageModelSession, date: Date)?

    static func key(mode: Mode, examples: [Prompts.Example]) -> String {
        mode.rawValue + "|" + examples.map(\.transcript).joined(separator: "|")
    }

    func put(_ session: LanguageModelSession, key: String) {
        lock.withLock { stored = (key, session, Date()) }
    }

    /// 同じ種類のセッションがあれば取り出す（10 分より古いものは使わない）
    func take(key: String) -> LanguageModelSession? {
        lock.withLock {
            defer { stored = nil }
            guard let s = stored, s.key == key, Date().timeIntervalSince(s.date) < 600 else { return nil }
            return s.session
        }
    }
}
