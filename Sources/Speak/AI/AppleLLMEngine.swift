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

    private func makeSession(instructions: String) throws -> LanguageModelSession {
        if let status = Self.onDeviceStatus { throw LLMError.unavailable(status) }
        // 書き起こしの整形は「入力文の変換」なので、変換向けの緩いガードレールを使う
        let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
        return LanguageModelSession(model: model, instructions: instructions)
    }

    func polish(_ request: PolishRequest) async throws -> String {
        let system = request.mode == .translate ? Prompts.translateSystem : Prompts.polishSystem
        let session = try makeSession(instructions: system)
        return try await mapErrors {
            let response = try await session.respond(to: Prompts.polishUser(request), options: GenerationOptions(temperature: 0.2))
            return Prompts.cleanOutput(response.content)
        }
    }

    func ask(_ request: AskRequest) async throws -> AskOutcome {
        let session = try makeSession(instructions: Prompts.askSystemCommon)
        return try await mapErrors {
            let response = try await session.respond(to: Prompts.askUser(request), generating: AppleAskDecision.self)
            let d = response.content
            return Prompts.outcome(action: d.action, text: d.text, url: d.url, request: request)
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
