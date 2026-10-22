import AVFoundation
import Foundation

/// 音声ファイルやテキストで認識と整形を試すためのコマンドラインモード。
/// 例: Speak --transcribe sample.aiff --mode translate --target en-US --category email
///     Speak --polish "えーと、明日は3時、いや4時です" --vocab "Claude Code=クロードコード,Speak" --json
@MainActor
enum CLI {
    static let usage = """
    usage: Speak (--transcribe <file> | --polish <text>) [--mode dictate|translate|ask] [--lang ja-JP] [--target en-US]
                 [--category chat] [--app Name] [--dir PATH] [--ssh HOST] [--selection TEXT] [--vocab "Term=heard|heard2,Term2~heard3"] [--json] [--prewarm] [--verbose]
                 [--llm appleOnDevice|claude|claudeCode|codex|openAICompatible|none] [--stt apple|local|openai|groq|custom] [--stt-model NAME] [--stt-base-url URL]
                 [--service openai|groq|openrouter|gemini|ollama|custom] [--base-url URL] [--model NAME]
    """

    static func run(_ args: [String]) async -> Int32 {
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        let path = value("--transcribe")
        let text = value("--polish")
        guard path != nil || text != nil else {
            print(usage)
            return 2
        }
        var settings = SettingsStore.shared.settings
        if let llm = value("--llm").flatMap(LLMProvider.init(rawValue:)) { settings.llmProvider = llm }
        if let stt = value("--stt").flatMap(STTProvider.init(rawValue:)) { settings.sttProvider = stt }
        if let url = value("--stt-base-url") { settings.sttBaseURLs[settings.sttProvider.rawValue] = url }
        if let model = value("--stt-model") { settings.sttModels[settings.sttProvider.rawValue] = model }
        if let service = value("--service").flatMap(CompatService.init(rawValue:)) { settings.compatService = service }
        if let url = value("--base-url") { settings.compatBaseURLs[settings.compatService.rawValue] = url }
        if let model = value("--model") {
            settings.claudeModel = model
            settings.codexModel = model
            settings.compatModels[settings.compatService.rawValue] = model
        }
        let mode = value("--mode").flatMap(Mode.init(rawValue:)) ?? .dictate
        let lang = value("--lang") ?? settings.currentDictationLanguage
        let category = value("--category").flatMap(AppCategory.init(rawValue:)) ?? .other
        let appName = value("--app") ?? "Terminal"
        let json = args.contains("--json")
        Polisher.verbose = args.contains("--verbose")
        var vocabulary = DictionaryStore.shared.terms
        var aliases = DictionaryStore.shared.aliases
        var aliasHints = DictionaryStore.shared.aliasHints
        if let spec = value("--vocab") {
            (vocabulary, aliases, aliasHints) = parseVocabulary(spec)
        }

        func report(_ fields: [String: Any]) {
            if json, let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) {
                print(String(decoding: data, as: UTF8.self))
            } else {
                for key in ["raw", "out", "ask"] {
                    guard let v = fields[key] else { continue }
                    print(String(format: "%@  (%.2fs, %@): ", key.uppercased(), fields[key + "_sec"] as? Double ?? 0,
                                 fields[key + "_engine"] as? String ?? "") + "\(v)")
                }
                if let w = fields["warning"] { print("WARNING: \(w)") }
            }
        }

        var fields: [String: Any] = [:]
        do {
            let raw: String
            if let path {
                let audio = try loadAudio(URL(fileURLWithPath: path))
                let request = TranscriptionRequest(languages: settings.sttLanguages(current: lang), vocabulary: vocabulary)
                let t0 = Date()
                raw = try await TranscriberFactory.make(settings: settings, language: lang).transcribe(audio, request)
                fields["raw_sec"] = Date().timeIntervalSince(t0)
                fields["raw_engine"] = settings.sttProvider == .local ? settings.localSpeechModel.rawValue : settings.sttProvider.rawValue
            } else {
                raw = text ?? ""
            }
            fields["raw"] = raw

            // 環境変数のキーがあればキーチェーンより優先する（試験用）
            let env = ProcessInfo.processInfo.environment
            var engine = LLMFactory.make(settings: settings)
            if settings.llmProvider == .claude, let key = env["ANTHROPIC_API_KEY"] {
                engine = ClaudeEngine(apiKey: key, model: settings.claudeModel, webSearch: settings.webSearch)
            } else if settings.llmProvider == .openAICompatible, let key = env["OPENAI_API_KEY"] {
                let svc = settings.compatService
                engine = OpenAICompatibleEngine(service: svc, baseURL: settings.compatBaseURL(svc), model: settings.compatModel(svc), apiKey: key)
            }
            if args.contains("--prewarm"), settings.llmProvider == .appleOnDevice {
                // アプリでは録音中に済ませる準備を、録音時間ぶん待って再現する
                AppleLLMEngine.prewarm(mode: mode, language: lang)
                try await Task.sleep(for: .seconds(3))
            }
            let t1 = Date()
            if mode == .ask {
                guard let engine else { throw LLMError.unavailable("Ask anything needs an AI engine") }
                let ask = AskRequest(query: Polisher.prepare(raw, aliases: aliases), selection: value("--selection"),
                                     selectionEditable: value("--selection") != nil,
                                     hasFocusedTextField: false, appName: appName, vocabulary: vocabulary)
                let outcome = try await engine.ask(ask)
                fields["ask"] = "\(outcome)"
                fields["ask_sec"] = Date().timeIntervalSince(t1)
                fields["ask_engine"] = engine.name
            } else {
                // --app "Claude Code" などでは送信・スラッシュコマンドを扱う（--dir の作業フォルダの .claude にある自作のコマンドも探す。
                // --ssh を付けると、その SSH 先で探す）
                let agent = CodingAgent.allCases.first { $0.name == appName }
                let (spoken, submit) = agent != nil && mode == .dictate ? AgentInput.splitSubmit(raw) : (raw, false)
                if submit { fields["submit"] = true }
                // --screen FILE: 保存した端末の画面に Claude Code の許可の確認が出ていれば、どれを選ぶかを表示する
                if agent == .claudeCode, mode == .dictate,
                   let prompt = value("--screen").flatMap({ try? String(contentsOfFile: $0, encoding: .utf8) }).flatMap(CodingAgent.permissionPrompt(in:)) {
                    let answer = AgentInput.answer(spoken, to: prompt)
                    fields["options"] = prompt.options
                    fields["choice"] = answer.map { "\($0.choice + 1). \(prompt.options[$0.choice])" } ?? "(none)"
                    if let rest = answer?.rest { fields["rest"] = rest }
                    report(fields)
                    return 0
                }
                if let agent, mode == .dictate,
                   let command = AgentInput.slashCommand(spoken, commands: commands(for: agent, directory: value("--dir"), ssh: value("--ssh"))) {
                    fields["out"] = command
                    report(fields)
                    return 0
                }
                let polish = PolishRequest(
                    transcript: spoken, mode: mode, sourceLanguages: [lang],
                    targetLanguage: mode == .translate ? (value("--target") ?? settings.currentTranslationTarget) : nil,
                    appName: appName, category: category, styleDescription: category.defaultStyleDescription,
                    personalStyle: PersonalizationStore.shared.profile.promptDescription(for: category),
                    vocabulary: vocabulary, corrections: PersonalizationStore.shared.corrections, aliases: aliases, aliasHints: aliasHints,
                    notation: settings.japaneseNotation, chatPunctuation: settings.chatPunctuation,
                    codingAgent: category == .ai && CodingAgent.isLabel(appName)
                )
                let out = try await Polisher.run(polish, engine: engine)
                fields["out"] = out.text
                fields["out_sec"] = Date().timeIntervalSince(t1)
                fields["out_engine"] = engine?.name ?? "basic"
                if let w = out.warning { fields["warning"] = w }
            }
            report(fields)
            return 0
        } catch {
            fields["error"] = error.localizedDescription
            if json { report(fields) } else { print("ERROR: \(error.localizedDescription)") }
            return 1
        }
    }

    private static func commands(for agent: CodingAgent, directory: String?, ssh: String?) -> [String] {
        guard let ssh else { return AgentWorkspace.commands(for: agent, directory: directory) }
        return AgentWorkspace.remoteCommands(for: agent, on: RemoteHost(arguments: [ssh], directory: directory))
            ?? AgentWorkspace.builtInCommands(for: agent)
    }

    /// "Claude Code=クロードコード|クロード・コード,田中~棚香,Speak" → 単語の一覧、置き換える聞き取られ方、AI へのヒントにする聞き取られ方。
    /// "=" は認識結果をそのまま置き換え、"~" は自動追加した漢字の語と同じく AI に文脈を見て直してもらう。
    static func parseVocabulary(_ spec: String) -> ([String], [String: String], [String: String]) {
        var terms: [String] = []
        var aliases: [String: String] = [:]
        var hints: [String: String] = [:]
        for item in spec.split(separator: ",") {
            let hint = item.contains("~")
            let parts = item.split(maxSplits: 1, whereSeparator: { $0 == "=" || $0 == "~" }).map { $0.trimmingCharacters(in: .whitespaces) }
            guard let term = parts.first, !term.isEmpty else { continue }
            terms.append(term)
            guard parts.count == 2 else { continue }
            for a in parts[1].split(separator: "|") {
                let alias = a.trimmingCharacters(in: .whitespaces)
                if hint { hints[alias] = term } else { aliases[alias] = term }
            }
        }
        return (terms, aliases, hints)
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
