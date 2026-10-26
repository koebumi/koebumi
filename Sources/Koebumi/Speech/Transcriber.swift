import AVFoundation
import CoreMedia
import Foundation
import Speech

struct TranscriptionRequest {
    /// 話す言語（BCP-47）。先頭が主言語。
    var languages: [String]
    /// 辞書の単語（固有名詞・専門用語）
    var vocabulary: [String]
    /// 録音中に、ここまでに話した内容の書き起こしを受け取る（音声バーに出す）。録音中に書き起こすエンジンだけが呼ぶ
    var onPartial: (@Sendable (String) -> Void)? = nil
}

enum TranscriptionError: LocalizedError {
    case unsupportedLocale(String)
    case unsupportedModelLanguage(String, String)
    case modelNotDownloaded(String)
    case modelDownloading(String)
    case modelFailed(String, String)
    case missingKey(String)
    case http(Int, String)
    case empty

    var errorDescription: String? {
        switch self {
        case .unsupportedLocale(let l):
            return t("Apple の音声認識は \(Languages.name(l)) に対応していません。設定で別の言語かクラウドの音声認識を選んでください。",
                     "Apple speech recognition does not support \(Languages.name(l)). Choose another language or a cloud engine in Settings.")
        case .unsupportedModelLanguage(let model, let l):
            return t("\(model) は \(Languages.name(l)) に対応していません。設定 > AI エンジン で別のモデルを選んでください。",
                     "\(model) does not support \(Languages.name(l)). Choose another model in Settings > AI engines.")
        case .modelNotDownloaded(let model):
            return t("\(model) がまだダウンロードされていません（設定 > AI エンジン）", "\(model) is not downloaded yet (Settings > AI engines)")
        case .modelDownloading(let model):
            return t("\(model) をダウンロードしています。終わってからもう一度話してください", "\(model) is still downloading. Try again when it finishes")
        case .modelFailed(let model, let detail):
            return t("\(model) で認識できませんでした: ", "\(model) could not transcribe: ") + detail.prefix(200)
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
        case .local:
            return LocalModelTranscriber(model: settings.localSpeechModel)
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

/// 時刻つきの認識結果の断片（秒）
struct TimedText: Equatable {
    var text: String
    var start: Double
    var end: Double
}

final class AppleSpeechSession: TranscriptionSession, @unchecked Sendable {
    private let analyzer: SpeechAnalyzer
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private let analyzerFormat: AVAudioFormat
    private let converter: AVAudioConverter?
    private let resultTask: Task<[[TimedText]], Error>
    private let lineBreakTask: Task<[TimedText], Never>?
    private let unspaced: Bool
    private let lock = NSLock()
    private var finished = false

    private init(analyzer: SpeechAnalyzer, continuation: AsyncStream<AnalyzerInput>.Continuation, analyzerFormat: AVAudioFormat,
                 resultTask: Task<[[TimedText]], Error>, lineBreakTask: Task<[TimedText], Never>?, unspaced: Bool) {
        self.analyzer = analyzer
        self.continuation = continuation
        self.analyzerFormat = analyzerFormat
        self.resultTask = resultTask
        self.lineBreakTask = lineBreakTask
        self.unspaced = unspaced
        converter = AVAudioConverter(from: AudioRecorder.format, to: analyzerFormat)
    }

    static func make(locale identifier: String, vocabulary: [String]) async throws -> AppleSpeechSession {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: identifier)) else {
            throw TranscriptionError.unsupportedLocale(identifier)
        }
        // .transcription と同じ設定に、改行の位置合わせ用の時刻を足したもの
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        var modules: [any SpeechModule] = [transcriber]
        let lineBreakDetector = await makeLineBreakDetector(locale: locale, identifier: identifier)
        if let lineBreakDetector { modules.append(lineBreakDetector) }

        let analyzer = SpeechAnalyzer(
            modules: modules,
            options: SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .processLifetime)
        )
        if !vocabulary.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = Array(vocabulary.prefix(100))
            try await analyzer.setContext(context)
        }
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules) ?? AudioRecorder.format
        let resultTask = Task<[[TimedText]], Error> {
            var segments: [[TimedText]] = []
            for try await result in transcriber.results {
                segments.append(Self.timedRuns(result.text, fallback: result.range))
            }
            return segments
        }
        let lineBreakTask = lineBreakDetector.map { detector in
            Task<[TimedText], Never> {
                var breaks: [TimedText] = []
                do {
                    for try await result in detector.results {
                        breaks += Self.timedRuns(result.text, fallback: result.range).filter { $0.text.contains("\n") }
                    }
                } catch {
                    NSLog("Koebumi: line break detection failed: \(error)")
                }
                return breaks
            }
        }
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        do {
            try await analyzer.start(inputSequence: stream)
        } catch {
            continuation.finish()
            resultTask.cancel()
            lineBreakTask?.cancel()
            throw error
        }
        return AppleSpeechSession(analyzer: analyzer, continuation: continuation, analyzerFormat: format,
                                  resultTask: resultTask, lineBreakTask: lineBreakTask, unspaced: Languages.isUnspaced(identifier))
    }

    /// SpeechTranscriber は日本語の「改行」と話した語を黙って捨てるので、改行の位置だけを DictationTranscriber で拾う。
    /// モデルが入っていなければ今回は使わず、次回のために裏でダウンロードしておく。
    private static func makeLineBreakDetector(locale: Locale, identifier: String) async -> DictationTranscriber? {
        guard Languages.isoCode(identifier) == "ja",
              let dictationLocale = await DictationTranscriber.supportedLocale(equivalentTo: locale) else { return nil }
        let detector = DictationTranscriber(locale: dictationLocale, contentHints: [], transcriptionOptions: [.punctuation],
                                            reportingOptions: [], attributeOptions: [.audioTimeRange])
        guard await AssetInventory.status(forModules: [detector]) == .installed else {
            Task.detached(priority: .utility) {
                if let request = try? await AssetInventory.assetInstallationRequest(supporting: [detector]) {
                    try? await request.downloadAndInstall()
                }
            }
            return nil
        }
        return detector
    }

    private static func timedRuns(_ text: AttributedString, fallback: CMTimeRange) -> [TimedText] {
        text.runs.map { run in
            let range = run.audioTimeRange ?? fallback
            return TimedText(text: String(text[run.range].characters), start: range.start.seconds, end: range.end.seconds)
        }
    }

    /// 認識結果をつなぎ、話した「改行」の位置に改行を入れる。
    /// 改行は、その時刻より後で終わる最初の語の前に入れる（SpeechTranscriber は捨てた語の時間を次の語に含めるため）。
    static func compose(_ segments: [[TimedText]], lineBreaks: [TimedText], unspaced: Bool) -> String {
        var breaks = lineBreaks.sorted { $0.start < $1.start }
        let all = segments.flatMap { $0 }
        var text = ""
        for (index, segment) in segments.enumerated() {
            var piece = ""
            for run in segment {
                while let b = breaks.first, run.end > b.start + 0.3 {
                    breaks.removeFirst()
                    // 認識結果にも「改行」が残っていれば、それを改行にする処理に任せる
                    let spokenWord = all.contains { $0.text.contains("改行") && $0.end > b.start - 0.5 && $0.start < b.end + 0.5 }
                    guard !spokenWord, !(text + piece).trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                    let newline = b.text.filter(\.isNewline)
                    if piece.isEmpty {
                        text = text.trimmingCharacters(in: .whitespaces) + newline
                    } else {
                        piece = piece.trimmingCharacters(in: .whitespaces) + newline
                    }
                }
                piece += run.text
            }
            text = index == 0 ? piece.trimmingCharacters(in: .whitespaces) : join(text, piece, unspaced: unspaced)
        }
        return text
    }

    static func join(_ a: String, _ b: String, unspaced: Bool) -> String {
        let b = b.trimmingCharacters(in: .whitespaces)
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        if unspaced || a.last?.isWhitespace == true || a.last?.isNewline == true { return a + b }
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
        lock.withLock {
            guard !finished else { return }
            feed(buffer)
        }
    }

    /// lock を持った状態で呼ぶ
    private func feed(_ buffer: AVAudioPCMBuffer) {
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

    /// 話し終わりに足す無音。キーを離した直後で音声が途切れても、最後の語と句点まで確定させる。
    static let trailingSilence: TimeInterval = 0.5

    func finish() async throws -> String {
        lock.withLock {
            guard !finished else { return }
            finished = true
            if let silence = Self.buffer(from: [Float](repeating: 0, count: Int(Self.trailingSilence * AudioRecorder.format.sampleRate))) {
                feed(silence)
            }
        }
        continuation.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        let segments = try await resultTask.value
        let lineBreaks = await lineBreakTask?.value ?? []
        return Self.compose(segments, lineBreaks: lineBreaks, unspaced: unspaced).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() {
        lock.withLock { finished = true }
        continuation.finish()
        resultTask.cancel()
        lineBreakTask?.cancel()
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
        let boundary = "koebumi-\(UUID().uuidString)"
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
