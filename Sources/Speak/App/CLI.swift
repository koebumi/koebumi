import AVFoundation
import Foundation

/// 音声ファイルで認識と整形を試すためのコマンドラインモード。
/// 例: Speak --transcribe sample.aiff --mode translate --target en-US --category email
@MainActor
enum CLI {
    static func run(_ args: [String]) async -> Int32 {
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        guard let path = value("--transcribe") else {
            print("usage: Speak --transcribe <file> [--mode dictate|translate|ask] [--lang ja-JP] [--target en-US] [--category chat] [--app Name] [--selection TEXT] [--llm appleOnDevice|claude|openAICompatible|none] [--stt apple|openai|groq|custom] [--stt-base-url URL] [--service openai|groq|openrouter|gemini|ollama|custom] [--base-url URL] [--model NAME]")
            return 2
        }
        var settings = SettingsStore.shared.settings
        if let llm = value("--llm").flatMap(LLMProvider.init(rawValue:)) { settings.llmProvider = llm }
        if let stt = value("--stt").flatMap(STTProvider.init(rawValue:)) { settings.sttProvider = stt }
        if let url = value("--stt-base-url") { settings.sttBaseURLs[settings.sttProvider.rawValue] = url }
        if let service = value("--service").flatMap(CompatService.init(rawValue:)) { settings.compatService = service }
        if let url = value("--base-url") { settings.compatBaseURLs[settings.compatService.rawValue] = url }
        if let model = value("--model") {
            settings.claudeModel = model
            settings.compatModels[settings.compatService.rawValue] = model
        }
        let mode = value("--mode").flatMap(Mode.init(rawValue:)) ?? .dictate
        let lang = value("--lang") ?? settings.currentDictationLanguage
        let category = value("--category").flatMap(AppCategory.init(rawValue:)) ?? .other
        let appName = value("--app") ?? "Terminal"

        do {
            let audio = try loadAudio(URL(fileURLWithPath: path))
            let vocabulary = DictionaryStore.shared.terms
            let request = TranscriptionRequest(languages: settings.sttProvider == .apple ? [lang] : settings.dictationLanguages, vocabulary: vocabulary)
            let t0 = Date()
            let raw = try await TranscriberFactory.make(settings: settings, language: lang).transcribe(audio, request)
            print(String(format: "RAW  (%.2fs, %@): ", Date().timeIntervalSince(t0), settings.sttProvider.rawValue) + raw)

            // 環境変数のキーがあればキーチェーンより優先する（試験用）
            let env = ProcessInfo.processInfo.environment
            var engine = LLMFactory.make(settings: settings)
            if settings.llmProvider == .claude, let key = env["ANTHROPIC_API_KEY"] {
                engine = ClaudeEngine(apiKey: key, model: settings.claudeModel, webSearch: settings.webSearch)
            } else if settings.llmProvider == .openAICompatible, let key = env["OPENAI_API_KEY"] {
                let svc = settings.compatService
                engine = OpenAICompatibleEngine(service: svc, baseURL: settings.compatBaseURL(svc), model: settings.compatModel(svc), apiKey: key)
            }
            guard let engine else {
                print("OUT  (basic): " + BasicCleaner.clean(raw))
                return 0
            }
            let t1 = Date()
            if mode == .ask {
                let ask = AskRequest(query: raw, selection: value("--selection"), selectionEditable: value("--selection") != nil,
                                     hasFocusedTextField: false, appName: appName, vocabulary: vocabulary)
                let outcome = try await engine.ask(ask)
                print(String(format: "ASK  (%.2fs, %@): ", Date().timeIntervalSince(t1), engine.name) + "\(outcome)")
            } else {
                let polish = PolishRequest(
                    transcript: raw, mode: mode, sourceLanguages: [lang],
                    targetLanguage: mode == .translate ? (value("--target") ?? settings.currentTranslationTarget) : nil,
                    appName: appName, category: category, styleDescription: category.defaultStyleDescription,
                    personalStyle: PersonalizationStore.shared.profile.promptDescription(for: category),
                    vocabulary: vocabulary, corrections: PersonalizationStore.shared.corrections
                )
                let out = try await engine.polish(polish)
                print(String(format: "OUT  (%.2fs, %@): ", Date().timeIntervalSince(t1), engine.name) + out)
            }
            return 0
        } catch {
            print("ERROR: \(error.localizedDescription)")
            return 1
        }
    }

    /// 任意の音声ファイルを 16 kHz モノラルに変換して読み込む
    static func loadAudio(_ url: URL) throws -> RecordedAudio {
        let file = try AVAudioFile(forReading: url)
        let inFormat = file.processingFormat
        guard let input = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(file.length)) else { return RecordedAudio(samples: []) }
        try file.read(into: input)
        guard let converter = AVAudioConverter(from: inFormat, to: AudioRecorder.format) else { return RecordedAudio(samples: []) }
        let capacity = AVAudioFrameCount(Double(input.frameLength) * 16000 / inFormat.sampleRate) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: AudioRecorder.format, frameCapacity: capacity) else { return RecordedAudio(samples: []) }
        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed {
                status.pointee = .endOfStream
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return input
        }
        if let error { throw error }
        return RecordedAudio(samples: Array(UnsafeBufferPointer(start: out.floatChannelData![0], count: Int(out.frameLength))))
    }
}
