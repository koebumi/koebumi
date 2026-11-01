@preconcurrency import AudioCommon
import Foundation

// speech.cpp（https://github.com/nyosegawa/speech.cpp、MIT）の `speech worker` を子プロセスで動かし、音声認識に使う。
// speech-swift にない日本語のモデル（Haas）を、ggml と Metal で動かすため。
// アプリには `speech` コマンドを 1 つ同梱する（scripts/fetch-speech-cpp.sh、Contents/Helpers/speech）。
// やりとりは JSON Lines（https://github.com/nyosegawa/speech.cpp/blob/main/docs/worker.md）。

/// 同梱した speech.cpp のコマンドの場所
enum SpeechCpp {
    /// 動作を確かめた版。scripts/fetch-speech-cpp.sh で取ってくる版と同じにする
    static let version = "0.10.0"

    static var executable: URL? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// 探す順: 環境変数、アプリの中、swift build で作った実行ファイルのときはリポジトリの build/speech.cpp
    static var candidates: [URL] {
        var urls: [URL] = []
        if let path = ProcessInfo.processInfo.environment["KOEBUMI_SPEECH_CPP"], !path.isEmpty {
            urls.append(URL(fileURLWithPath: path))
        }
        urls.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/speech"))
        // .build/<triple>/debug/Koebumi → <リポジトリ>/build/speech.cpp/speech
        if let exe = Bundle.main.executableURL?.resolvingSymlinksInPath() {
            var dir = exe.deletingLastPathComponent()
            for _ in 0..<4 {
                if dir.lastPathComponent == ".build" {
                    urls.append(dir.deletingLastPathComponent().appendingPathComponent("build/speech.cpp/speech"))
                    break
                }
                dir = dir.deletingLastPathComponent()
            }
        }
        return urls
    }
}

enum SpeechCppError: LocalizedError {
    case missingExecutable
    case workerFailed(String)
    case workerExited(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .missingExecutable:
            return t("speech.cpp が見つかりません。アプリを入れ直してください（開発中は scripts/fetch-speech-cpp.sh を実行してください）",
                     "speech.cpp was not found. Reinstall the app (when developing, run scripts/fetch-speech-cpp.sh)")
        case .workerFailed(let message):
            return "speech.cpp: " + message
        case .workerExited(let detail):
            return t("speech.cpp が止まりました", "speech.cpp stopped") + (detail.isEmpty ? "" : ": " + detail)
        case .timedOut:
            return t("speech.cpp から返事がありません", "speech.cpp did not respond")
        }
    }
}

/// speech.cpp のワーカー 1 つ。モデルを 1 つ読み込んだまま、認識の依頼を 1 つずつ受ける。
/// 認識は LocalSpeechRuntime の認識用のキューからしか呼ばないので、依頼と返事の読み書きは同時に起きない。
final class SpeechCppModel: SpeechRecognitionModel, ModelMemoryManageable, @unchecked Sendable {
    /// 読み込みと最初のカーネルのコンパイルを待つ時間
    static let readyTimeout: TimeInterval = 180
    /// 1 回に送る音声（10 秒分）。1 行が長くなりすぎないよう分けて送る
    static let chunkSamples = 160_000

    let inputSampleRate = 16_000
    let modelFile: URL
    private let process: Process
    private let input: FileHandle
    private let output: LineReader
    private let log = StderrTail()
    private let lock = NSLock()
    private var loaded = true
    private var nextID = 0

    /// 重みのファイルを（無ければ Hugging Face から取ってきて）ワーカーに読み込ませる
    static func load(repo: String, file: String, offline: Bool, progress: @escaping @Sendable (Double) -> Void) async throws -> SpeechCppModel {
        let dir = try HuggingFaceDownloader.getCacheDirectory(for: repo)
        try await HuggingFaceDownloader.downloadFiles(modelId: repo, to: dir, files: [file], offlineMode: offline) { progress($0 * 0.9) }
        guard let executable = SpeechCpp.executable else { throw SpeechCppError.missingExecutable }
        let modelFile = dir.appendingPathComponent(file)
        // ready が届くまで数秒かかる。並行処理用のスレッドを塞がないよう、別のスレッドで待つ
        let model = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SpeechCppModel, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try SpeechCppModel(executable: executable, modelFile: modelFile) })
            }
        }
        progress(1)
        return model
    }

    init(executable: URL, modelFile: URL) throws {
        self.modelFile = modelFile
        process = Process()
        process.executableURL = executable
        process.arguments = ["worker", modelFile.path]
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        input = stdin.fileHandleForWriting
        output = LineReader(stdout.fileHandleForReading)
        // ワーカーが止まった後に書き込んでも、アプリごと終わらない（SIGPIPE を受けない）
        _ = fcntl(input.fileDescriptor, F_SETNOSIGPIPE, 1)
        // 標準エラーは読み続ける（読まないとパイプが詰まってワーカーが止まる）。最後の数行だけ、失敗の理由に使う
        let log = log
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil } else { log.append(data) }
        }
        try process.run()
        do {
            let ready = try withTimeout(Self.readyTimeout) { try self.readMessage() }
            switch ready["type"] as? String {
            case "ready":
                break
            case "fatal":
                throw SpeechCppError.workerFailed(Self.message(of: ready))
            default:
                throw SpeechCppError.workerFailed("unexpected message: \(ready)")
            }
        } catch {
            stop()
            throw error
        }
    }

    deinit { stop() }

    var isLoaded: Bool { lock.withLock { loaded } }

    var memoryFootprint: Int {
        guard isLoaded else { return 0 }
        return ((try? modelFile.resourceValues(forKeys: [.fileSizeKey]))?.fileSize) ?? 0
    }

    /// ワーカーを終わらせて、モデルのメモリを OS に返す
    func unload() { stop() }

    private func stop() {
        lock.withLock { loaded = false }
        // 標準入力を閉じると、ワーカーは受けた依頼に答えてから終わる
        try? input.close()
        let process = process
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            if process.isRunning { process.terminate() }
        }
    }

    func transcribe(audio: [Float], sampleRate: Int, language: String?) -> String {
        (try? transcribeAudio(audio, sampleRate: sampleRate)) ?? ""
    }

    /// 音声を書き起こす。keywords は Haas のカスタム語彙（表記だけ、または「表記=読み,読み」）
    func transcribeAudio(_ audio: [Float], sampleRate: Int, keywords: [String] = []) throws -> String {
        guard !audio.isEmpty else { return "" }
        let keywords = Self.sanitized(keywords)
        do {
            return try request(audio, sampleRate: sampleRate, keywords: keywords)
        } catch SpeechCppError.workerFailed(let message) where !keywords.isEmpty && message.contains("keywords") {
            // 語彙を受け付けなかったときは、語彙なしで認識し直す（辞書の語のせいで書き起こせなくしない）
            NSLog("Koebumi: speech.cpp refused the keywords: \(message)")
            return try request(audio, sampleRate: sampleRate, keywords: [])
        }
    }

    private func request(_ audio: [Float], sampleRate: Int, keywords: [String]) throws -> String {
        guard isLoaded else { throw SpeechCppError.workerExited("") }
        nextID += 1
        let id = String(nextID)
        let duration = Double(audio.count) / Double(sampleRate)
        return try withTimeout(60 + duration) {
            for (seq, start) in stride(from: 0, to: audio.count, by: Self.chunkSamples).enumerated() {
                let chunk = audio[start..<min(start + Self.chunkSamples, audio.count)]
                try send(["type": "chunk", "id": id, "seq": seq, "pcm": Self.pcm16Base64(chunk)])
            }
            var transcribe: [String: Any] = ["type": "transcribe", "id": id, "sample_rate": sampleRate]
            if !keywords.isEmpty { transcribe["keywords"] = keywords.joined(separator: "\n") }
            try send(transcribe)
            while true {
                let message = try readMessage()
                let type = message["type"] as? String
                if type == "progress" { continue }
                // 依頼の id がない error は、こちらの書いた行が読めなかったということ
                guard let replyID = message["id"] as? String else {
                    throw SpeechCppError.workerFailed(Self.message(of: message))
                }
                guard replyID == id else { continue }
                switch type {
                case "end": return message["text"] as? String ?? ""
                case "error": throw SpeechCppError.workerFailed(Self.message(of: message))
                default: throw SpeechCppError.workerFailed("unexpected message: \(type ?? "?")")
                }
            }
        }
    }

    private func send(_ message: [String: Any]) throws {
        var line = try JSONSerialization.data(withJSONObject: message)
        line.append(0x0A)
        do {
            try input.write(contentsOf: line)
        } catch {
            throw SpeechCppError.workerExited(log.text)
        }
    }

    private func readMessage() throws -> [String: Any] {
        guard let line = output.next() else { throw SpeechCppError.workerExited(log.text) }
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
            throw SpeechCppError.workerFailed("not a JSON object: \(line.prefix(200))")
        }
        return object
    }

    /// 返事が来なければワーカーを止める。止めると読み込み中の行が終わり、workerExited になる
    private func withTimeout<T>(_ seconds: TimeInterval, _ body: () throws -> T) throws -> T {
        let process = process
        var timedOut = false
        let lock = NSLock()
        let watchdog = DispatchWorkItem {
            lock.withLock { timedOut = true }
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: watchdog)
        defer { watchdog.cancel() }
        do {
            return try body()
        } catch {
            if lock.withLock({ timedOut }) {
                stop()
                throw SpeechCppError.timedOut
            }
            throw error
        }
    }

    private static func message(of reply: [String: Any]) -> String {
        guard let error = reply["error"] as? [String: Any] else { return "\(reply)" }
        let option = (error["option"] as? String).map { " (\($0))" } ?? ""
        return (error["message"] as? String ?? error["code"] as? String ?? "error") + option
    }
}

extension SpeechCppModel {
    /// 16 ビットのリトルエンディアンにして base64 にする（ワーカーは x / 32768 として読む）
    static func pcm16Base64(_ samples: ArraySlice<Float>) -> String {
        var data = Data(capacity: samples.count * 2)
        for sample in samples {
            let value = Int16((max(-1, min(1, sample)) * 32767).rounded())
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        return data.base64EncodedString()
    }

    /// Haas の語彙は 1 行に 1 語で、「=」と「,」で表記と読みを分ける。区切りの文字を含む語や空の語は渡さない
    static func sanitized(_ keywords: [String]) -> [String] {
        var seen = Set<String>()
        return keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.rangeOfCharacter(from: CharacterSet(charactersIn: "=,\n\r")) == nil && seen.insert($0).inserted }
    }
}

/// パイプから 1 行ずつ読む。行が届くまで待つ
final class LineReader: @unchecked Sendable {
    private let handle: FileHandle
    private var buffer = Data()

    init(_ handle: FileHandle) { self.handle = handle }

    /// 次の行。パイプが閉じたら nil
    func next() -> String? {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                return String(decoding: line, as: UTF8.self)
            }
            let chunk = handle.availableData
            if chunk.isEmpty { return nil }
            buffer.append(chunk)
        }
    }
}

/// 標準エラーの最後の数行
final class StderrTail: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.withLock {
            data.append(chunk)
            if data.count > 4096 { data = data.suffix(4096) }
        }
    }

    var text: String {
        let lines = lock.withLock { String(decoding: data, as: UTF8.self) }.split(separator: "\n")
        return lines.suffix(3).joined(separator: " / ")
    }
}
