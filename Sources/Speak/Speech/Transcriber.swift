import AVFoundation
import Foundation
import Speech

struct TranscriptionRequest {
    /// 話す言語（BCP-47）。先頭が主言語。
    var languages: [String]
    /// 辞書の単語（固有名詞・専門用語）
    var vocabulary: [String]
}

enum TranscriptionError: LocalizedError {
    case unsupportedLocale(String)
    case missingKey(String)
    case http(Int, String)
    case empty

    var errorDescription: String? {
        switch self {
        case .unsupportedLocale(let l):
            return t("Apple の音声認識は \(Languages.name(l)) に対応していません。設定で別の言語かクラウドの音声認識を選んでください。",
                     "Apple speech recognition does not support \(Languages.name(l)). Choose another language or a cloud engine in Settings.")
        case .missingKey(let name):
            return t("\(name) の API キーが未設定です（設定 > AI エンジン）", "\(name) API key is not set (Settings > AI engines)")
        case .http(let code, let body):
            return t("音声認識エラー (\(code)): ", "Transcription error (\(code)): ") + body.prefix(200)
        case .empty:
            return t("音声を認識できませんでした", "No speech was recognized")
        }
    }
}

/// 録音しながら逐次認識するセッション。append はオーディオスレッドから呼ばれる。
protocol TranscriptionSession: AnyObject, Sendable {
    func append(_ buffer: AVAudioPCMBuffer)
    func finish() async throws -> String
    func cancel()
}

protocol Transcriber: Sendable {
    /// 逐次認識に対応するエンジンはセッションを返す。非対応なら nil（録音後にまとめて認識）。
    func makeSession(_ request: TranscriptionRequest) async throws -> TranscriptionSession?
    func transcribe(_ audio: RecordedAudio, _ request: TranscriptionRequest) async throws -> String
}

enum TranscriberFactory {
    @MainActor
    static func make(settings: AppSettings, language: String) -> Transcriber {
        switch settings.sttProvider {
        case .apple:
            return AppleTranscriber(locale: language)
        case .openai, .groq, .custom:
            let p = settings.sttProvider
            return OpenAICompatibleTranscriber(
                name: p.title,
                baseURL: settings.sttBaseURL(p),
                model: settings.sttModel(p),
                apiKey: p.keyAccount.flatMap { Keychain.get($0) },
                requiresKey: p != .custom
            )
        }
    }
}

// MARK: - Apple SpeechAnalyzer（オンデバイス）

struct AppleTranscriber: Transcriber {
    let locale: String

    func makeSession(_ request: TranscriptionRequest) async throws -> TranscriptionSession? {
        try await AppleSpeechSession.make(locale: locale, vocabulary: request.vocabulary)
    }

    func transcribe(_ audio: RecordedAudio, _ request: TranscriptionRequest) async throws -> String {
        let session = try await AppleSpeechSession.make(locale: locale, vocabulary: request.vocabulary)
        let chunk = 16000  // 1 秒ずつ流す
        var i = 0
        while i < audio.samples.count {
            let end = min(i + chunk, audio.samples.count)
            if let buf = AppleSpeechSession.buffer(from: Array(audio.samples[i..<end])) {
                session.append(buf)
            }
            i = end
        }
        return try await session.finish()
    }

    /// 言語の音声モデルがなければダウンロードする（設定画面から呼ぶ）
    static func ensureAssets(locale: String) async throws -> Bool {
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: locale)) else { return false }
        let transcriber = SpeechTranscriber(locale: supported, preset: .transcription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        return true
    }

    static func assetStatus(locale: String) async -> AssetInventory.Status {
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: locale)) else { return .unsupported }
        return await AssetInventory.status(forModules: [SpeechTranscriber(locale: supported, preset: .transcription)])
    }
}

final class AppleSpeechSession: TranscriptionSession, @unchecked Sendable {
    private let analyzer: SpeechAnalyzer
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private let analyzerFormat: AVAudioFormat
    private let converter: AVAudioConverter?
    private let resultTask: Task<String, Error>
    private let unspaced: Bool
    private let lock = NSLock()
    private var finished = false

    private init(analyzer: SpeechAnalyzer, continuation: AsyncStream<AnalyzerInput>.Continuation,
                 analyzerFormat: AVAudioFormat, resultTask: Task<String, Error>, unspaced: Bool) {
        self.analyzer = analyzer
        self.continuation = continuation
        self.analyzerFormat = analyzerFormat
        self.resultTask = resultTask
        self.unspaced = unspaced
        converter = AVAudioConverter(from: AudioRecorder.format, to: analyzerFormat)
    }

    static func make(locale identifier: String, vocabulary: [String]) async throws -> AppleSpeechSession {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: identifier)) else {
            throw TranscriptionError.unsupportedLocale(identifier)
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        let analyzer = SpeechAnalyzer(
            modules: [transcriber],
            options: SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .processLifetime)
        )
        if !vocabulary.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = Array(vocabulary.prefix(100))
            try await analyzer.setContext(context)
        }
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) ?? AudioRecorder.format
        let unspaced = Languages.isUnspaced(identifier)
        let resultTask = Task<String, Error> {
            var text = ""
            for try await result in transcriber.results {
                text = Self.join(text, String(result.text.characters), unspaced: unspaced)
            }
            return text
        }
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        do {
            try await analyzer.start(inputSequence: stream)
        } catch {
            continuation.finish()
            resultTask.cancel()
            throw error
        }
        return AppleSpeechSession(analyzer: analyzer, continuation: continuation, analyzerFormat: format,
                                  resultTask: resultTask, unspaced: unspaced)
    }

    static func join(_ a: String, _ b: String, unspaced: Bool) -> String {
        let b = b.trimmingCharacters(in: .whitespaces)
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        if unspaced || a.last?.isWhitespace == true { return a + b }
        return a + " " + b
    }

    static func buffer(from samples: [Float]) -> AVAudioPCMBuffer? {
        guard let buf = AVAudioPCMBuffer(pcmFormat: AudioRecorder.format, frameCapacity: AVAudioFrameCount(samples.count)) else { return nil }
        buf.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buf.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        return buf
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard lock.withLock({ !finished }) else { return }
        if analyzerFormat == AudioRecorder.format {
            continuation.yield(AnalyzerInput(buffer: buffer))
            return
        }
        guard let converter else { return }
        let ratio = analyzerFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: capacity) else { return }
        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        if error == nil, out.frameLength > 0 {
            continuation.yield(AnalyzerInput(buffer: out))
        }
    }

    func finish() async throws -> String {
        lock.withLock { finished = true }
        continuation.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        return try await resultTask.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() {
        lock.withLock { finished = true }
        continuation.finish()
        resultTask.cancel()
        let analyzer = analyzer
        Task { await analyzer.cancelAndFinishNow() }
    }
}

// MARK: - OpenAI 互換の音声認識 API（OpenAI / Groq / ローカルの Whisper サーバー）

struct OpenAICompatibleTranscriber: Transcriber {
    let name: String
    let baseURL: String
    let model: String
    let apiKey: String?
    let requiresKey: Bool

    func makeSession(_ request: TranscriptionRequest) async throws -> TranscriptionSession? { nil }

    func transcribe(_ audio: RecordedAudio, _ request: TranscriptionRequest) async throws -> String {
        if requiresKey && (apiKey ?? "").isEmpty { throw TranscriptionError.missingKey(name) }
        guard let url = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/audio/transcriptions") else {
            throw TranscriptionError.http(0, "invalid URL")
        }
        let boundary = "speak-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("model", model)
        field("response_format", "json")
        field("temperature", "0")
        // 話す言語が 1 つだけなら指定する。複数なら自動判定に任せる（混在した発話にも対応）。
        if request.languages.count == 1, let lang = request.languages.first {
            field("language", Languages.isoCode(lang))
        }
        if !request.vocabulary.isEmpty {
            field("prompt", request.vocabulary.prefix(60).joined(separator: ", "))
        }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        body.append(WAV.encode(audio.normalized()))
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var req = URLRequest(url: url, timeoutInterval: 120)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        req.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw TranscriptionError.http(status, String(decoding: data, as: UTF8.self)) }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (json?["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
