// モデルは Sendable ではないが、認識は専用のキューの上でしか呼ばないので、キューに渡すときの警告は出さない
@preconcurrency import AudioCommon
import CohereTranscribeASR
import Foundation
import MLX
import MossTranscribe
import Qwen3ASR
import WhisperASR

// MARK: - モデルのファイル

extension LocalSpeechModel {
    /// speech-swift の既定の置き場所（~/Library/Caches/qwen3-speech/models/<repo>）。もう一度ダウンロードできるので Caches に置く。
    var cacheDirectory: URL? {
        try? HuggingFaceDownloader.getCacheDirectory(for: repo)
    }

    /// ダウンロードと読み込みが一度でも終わったら置く印。名前は Speak だったころのまま（変えると、ダウンロード済みのモデルを取り直すことになる）
    private var readyMarker: URL? {
        cacheDirectory?.appendingPathComponent(".speak-ready")
    }

    /// 印だけで判定する。重みのファイルがあるだけでは、途中で止まったダウンロード（トークナイザーや CoreML の残りのファイルがない）と見分けられない。
    var isDownloaded: Bool {
        guard let marker = readyMarker else { return false }
        return FileManager.default.fileExists(atPath: marker.path)
    }

    func markReady() {
        guard let marker = readyMarker else { return }
        FileManager.default.createFile(atPath: marker.path, contents: nil)
    }

    func deleteFiles() throws {
        guard let dir = cacheDirectory, FileManager.default.fileExists(atPath: dir.path) else { return }
        try FileManager.default.removeItem(at: dir)
    }

    /// 重みを読み込む。offline が false なら、無いファイルを Hugging Face から取ってくる。
    fileprivate func load(offline: Bool, progress: @escaping @Sendable (Double) -> Void) async throws -> SpeechRecognitionModel {
        switch self {
        case .qwen3Small, .qwen3Large:
            return try await Qwen3ASRModel.fromPretrained(modelId: repo, offlineMode: offline) { p, _ in progress(p) }
        case .moss:
            return try await MossMLXModel.fromPretrained(modelId: repo, offlineMode: offline) { p, _ in progress(p) }
        case .whisperTurbo:
            return try await WhisperASRModel.fromPretrained(modelId: repo, offlineMode: offline) { p, _ in progress(p) }
        case .cohere:
            return try await CohereTranscribeModel.fromPretrained(repo, offlineMode: offline) { progress($0) }
        }
    }
}

// MARK: - 読み込んだモデル

/// モデルのファイルの扱い。テストでは本物のファイルに触らないものに差し替える。
struct LocalModelFiles: Sendable {
    var isDownloaded: @Sendable (LocalSpeechModel) -> Bool
    /// offline が false なら、無いファイルを Hugging Face から取ってくる
    var load: @Sendable (LocalSpeechModel, _ offline: Bool, _ progress: @escaping @Sendable (Double) -> Void) async throws -> SpeechRecognitionModel
    var markReady: @Sendable (LocalSpeechModel) -> Void
    /// 読み込んだモデルを手放して、メモリを OS に返す
    var unload: @Sendable (SpeechRecognitionModel) -> Void

    static let live = LocalModelFiles(
        isDownloaded: { $0.isDownloaded },
        load: { try await $0.load(offline: $1, progress: $2) },
        markReady: { $0.markReady() },
        unload: { LocalSpeechRuntime.unload($0) }
    )
}

/// 読み込んだモデルを 1 つだけ持つ。別のモデルに切り替えたら前のモデルを手放してメモリを空ける。
actor LocalSpeechRuntime {
    static let shared = LocalSpeechRuntime()

    /// 認識は数百ミリ秒〜数秒かかり、Whisper は中で別のタスクの完了を待つ。並行処理用のスレッドを塞がないよう専用のキューで動かす。
    private static let inferenceQueue = DispatchQueue(label: "io.github.koebumi.local-speech", qos: .userInitiated)

    private let files: LocalModelFiles
    private var loaded: (id: LocalSpeechModel, model: SpeechRecognitionModel)?
    private var loading: (id: LocalSpeechModel, task: Task<SpeechRecognitionModel, Error>)?
    /// ダウンロード中のモデル。読み込み中のモデルとは別に持ち、ほかのモデルを読み込んでもダウンロード中だと分かるようにする。
    private var downloading: Set<LocalSpeechModel> = []
    /// 設定で選んでいるモデル。ダウンロードが終わったモデルは、これと同じときだけ読み込んだままにする。
    private var selected: LocalSpeechModel?

    init(files: LocalModelFiles = .live) {
        self.files = files
    }

    /// ダウンロード済みのモデルを読み込む
    func model(_ id: LocalSpeechModel) async throws -> SpeechRecognitionModel {
        if let loaded, loaded.id == id { return loaded.model }
        // ダウンロードが終わるまで録音の結果を待たせない
        if downloading.contains(id) { throw TranscriptionError.modelDownloading(id.title) }
        if let loading, loading.id == id { return try await loading.task.value }
        guard files.isDownloaded(id) else { throw TranscriptionError.modelNotDownloaded(id.title) }
        unloadCurrent()
        let task = Task { [files] in try await files.load(id, true) { _ in } }
        loading = (id, task)
        defer { if loading?.id == id { loading = nil } }
        let model = try await task.value
        loaded = (id, model)
        return model
    }

    /// Hugging Face から取ってきて、読み込めることを確かめる。選んでいるモデルなら、そのまま認識に使う。
    /// 使っているモデルは読み込んだまま残すので、ダウンロード中に話しても読み込み直しを待たせない。
    func download(_ id: LocalSpeechModel, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard downloading.insert(id).inserted else { throw TranscriptionError.modelDownloading(id.title) }
        defer { downloading.remove(id) }
        let model = try await files.load(id, false, progress)
        files.markReady(id)
        if selected == id {
            unloadCurrent()
            loaded = (id, model)
        } else {
            // 読み込めることを確かめただけなので手放す
            files.unload(model)
        }
    }

    /// 録音を始めたときに読み込んでおく（話し終えてから読み込むと、その分だけ待たせる）
    nonisolated func prewarm(_ id: LocalSpeechModel) {
        guard files.isDownloaded(id) else { return }
        Task { _ = try? await model(id) }
    }

    /// 削除したモデルを手放す
    func release(_ id: LocalSpeechModel) {
        if loaded?.id == id { unloadCurrent() }
    }

    /// 読み込んだモデルを手放す
    private func unloadCurrent() {
        guard let model = loaded?.model else { return }
        loaded = nil
        files.unload(model)
    }

    /// 設定で選んでいるモデルだけを読み込んだままにする。nil ならすべて手放す（別のエンジンを選んだとき）。
    nonisolated func keepLoaded(_ id: LocalSpeechModel?) {
        Task { await retain(id) }
    }

    func retain(_ id: LocalSpeechModel?) async {
        selected = id
        // まだダウンロードしていないモデルを選んだときも、前のモデルは手放す
        if loaded?.id != id { unloadCurrent() }
        guard let id, loading?.id != id, files.isDownloaded(id) else { return }
        _ = try? await model(id)
    }

    func transcribe(_ audio: RecordedAudio, with id: LocalSpeechModel, languages: [String], vocabulary: [String]) async throws -> String {
        if let lang = languages.first, !id.supports(lang) { throw TranscriptionError.unsupportedModelLanguage(id.title, lang) }
        let model = try await model(id)
        let samples = audio.samples
        let sampleRate = Int(audio.sampleRate)
        let language = id.languageHint(for: languages)
        // 辞書の単語を渡すと、その表記で書き起こしやすくなる。Qwen3-ASR は文脈として、MOSS は指示文の末尾のホットワードとして渡す。
        let terms = Array(vocabulary.prefix(60))
        let context = terms.isEmpty ? nil : terms.joined(separator: ", ")
        // 短い発話や無音のとき、モデルが文脈の語の並びをそのまま書き出すことがある（続けて同じ語を繰り返すこともある）。
        // 先頭を削るだけでは繰り返しが残るので、文脈なしで認識し直す。
        // Qwen3-ASR 0.6B は、話した名前の代わりに文脈の名前を書くことがある（わたなべさん → 矢野さん。1.7B では起きなかった）。
        // 敬称の前に文脈の語があれば文脈なしでも認識し、そこにその語の読みがなければ、文脈なしの結果を使う
        let checksNames = id == .qwen3Small
        func withContext(_ run: (String?) throws -> String) rethrows -> String {
            let text = try run(context)
            if Self.echoesContext(text, terms: terms) { return try run(nil) }
            let names = checksNames ? Self.namesFromContext(in: text, terms: terms) : []
            guard !names.isEmpty else { return text }
            let plain = try run(nil)
            return plain.isEmpty || names.allSatisfy({ Self.heard($0, in: plain) }) ? text : plain
        }
        return try await withCheckedThrowingContinuation { continuation in
            Self.inferenceQueue.async {
                do {
                    let text: String
                    if let qwen = model as? Qwen3ASRModel {
                        // ライブラリは録音全体を一度に書き起こし、448 トークンで切る。15 秒を超えると同じ 3 トークンの並びも禁じるので、
                        // 言い回しが繰り返されると 2 回目から崩れる。この制限は外し、30 秒以内に区切って順に書き起こす。
                        // 15 秒で区切ると、文の途中の区切りに「。」が入ることが増えた。
                        let parts = audio.split(maxDuration: 30).filter { !$0.isSilent }.map { part in
                            withContext {
                                qwen.transcribe(audio: part.samples, sampleRate: sampleRate, options: Qwen3DecodingOptions(
                                    maxTokens: Self.maxTokens(for: part.duration), language: language, context: $0,
                                    longInputThresholdSeconds: .infinity))
                            }
                        }
                        text = Self.joinTranscripts(parts)
                    } else if let moss = model as? MossMLXModel {
                        // MOSS の transcribe は失敗を空の文字列にして返すので、エラーを投げる transcribeDetailed を使う
                        text = try withContext { context in
                            let instruction = MossMLXModel.defaultInstruction + (context.map { "热词提示：" + $0 } ?? "")
                            return try moss.transcribeDetailed(audio: samples, sampleRate: sampleRate, instruction: instruction).text
                        }
                    } else if let whisper = model as? WhisperASRModel {
                        // Whisper の transcribe も失敗を空の文字列にして返すので、エラーを投げる transcribeAudio を待つ
                        text = try Self.wait { try await whisper.transcribeAudio(samples, sampleRate: sampleRate, language: language) }
                    } else {
                        text = model.transcribe(audio: samples, sampleRate: sampleRate, language: language)
                    }
                    continuation.resume(returning: text.trimmingCharacters(in: .whitespacesAndNewlines))
                } catch {
                    continuation.resume(throwing: TranscriptionError.modelFailed(id.title, error.localizedDescription))
                }
            }
        }
    }
}

extension LocalSpeechRuntime {
    /// 認識結果が、文脈として渡した語の並び（"語1, 語2, …"）の書き出しで始まっているか。
    /// 先頭の語の直後が "," "." "。" か文の終わりのときだけ数え、「Claudeに聞いて」のように語から話し始めた文は数えない。
    /// 途中の語から書き出すこともある（画面の語を飛ばして、辞書の語から「新版, 音声入力時, …」）ので、
    /// 「,」で区切った先頭の 3 つのうち 2 つが文脈の語なら、どの語から始まっても書き出しとみなす。
    /// 書き出すときに語を崩すこともある（Codex → Code）ので、3 つすべての一致は求めない
    static func echoesContext(_ text: String, terms: [String]) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = terms.first, !first.isEmpty else { return false }
        if text.hasPrefix(first) {
            guard let next = text.dropFirst(first.count).first else { return true }
            if next == "," || next == "." || next == "。" { return true }
        }
        let pieces = text.split(separator: ",", maxSplits: 3).prefix(3).map { $0.trimmingCharacters(in: .whitespaces) }
        return pieces.count == 3 && pieces.filter(terms.contains).count >= 2
    }

    /// 認識結果で、敬称の直前にある文脈の語（「矢野さん」の「矢野」）
    static func namesFromContext(in text: String, terms: [String]) -> [String] {
        terms.filter { term in
            guard !term.isEmpty else { return false }
            var rest = text[...]
            while let r = rest.range(of: term) {
                rest = rest[r.upperBound...]
                if ScreenNameFixer.honorifics.contains(where: { rest.hasPrefix($0) }) { return true }
            }
            return false
        }
    }

    /// 文脈なしで認識した文に、名前の読みがあるか。聞き取りの揺れ（わたなべ → わたべ）は、読みの 4 分の 1 までの違いを許す
    static func heard(_ name: String, in text: String) -> Bool {
        let target = reading(name)
        guard !target.isEmpty else { return true }
        return distance(target, within: reading(text)) <= target.count / 4
    }

    private static func reading(_ s: String) -> [Character] {
        Array(ScreenNameFixer.tokens(s).map { $0.reading.isEmpty ? $0.surface : $0.reading }.joined().lowercased().filter(\.isLetter))
    }

    /// target と、text のどこかの部分との編集距離のうち、いちばん小さいもの
    private static func distance(_ target: [Character], within text: [Character]) -> Int {
        var column = Array(0...target.count)
        var best = target.count
        for c in text {
            var next = [0]
            for i in 1...target.count {
                next.append(min(column[i - 1] + (target[i - 1] == c ? 0 : 1), column[i] + 1, next[i - 1] + 1))
            }
            column = next
            best = min(best, column[target.count])
        }
        return best
    }

    /// 書き起こしのトークン数の上限。速い発話でも 1 秒あたり 9 トークンほどなので、15 トークンあれば切れない。
    /// 繰り返しで崩れたときに、既定の 448 トークンまで書き続けて待たせないよう、音声の長さに合わせる。
    static func maxTokens(for duration: TimeInterval) -> Int {
        24 + Int(duration * 15)
    }

    /// 区切って書き起こした文をつなぐ。英数字や記号どうしの間にだけ空白を入れる。
    static func joinTranscripts(_ parts: [String]) -> String {
        parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.reduce("") { text, part in
            guard let last = text.last, let first = part.first else { return text + part }
            return text + (last.isASCII && first.isASCII ? " " : "") + part
        }
    }

    /// モデルの重みを消して、メモリを OS に返す。参照を外すだけでは、重みのメモリが MLX のキャッシュに残る。
    /// 認識中のモデルを壊さないよう、認識と同じキューで、前の認識が終わってから消す。
    static func unload(_ model: SpeechRecognitionModel) {
        inferenceQueue.async {
            // 重みを消す unload を持つのは Qwen3-ASR だけ。ほかのモデルは、このブロックが手放されたときに解放される。
            (model as? ModelMemoryManageable)?.unload()
        }
        // モデルが解放されてから、キャッシュに残った重みを OS に返す
        inferenceQueue.async { Memory.clearCache() }
    }

    /// async の認識を、認識用のキューの上で止めて待つ。キューは並行処理用のスレッドではないので、止めても他のタスクを塞がない。
    fileprivate static func wait(_ operation: @escaping @Sendable () async throws -> String) throws -> String {
        final class Box: @unchecked Sendable { var result: Result<String, Error>? }
        let box = Box()
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            do { box.result = .success(try await operation()) } catch { box.result = .failure(error) }
            semaphore.signal()
        }
        semaphore.wait()
        return try box.result!.get()
    }
}

struct LocalModelTranscriber: Transcriber {
    let model: LocalSpeechModel

    func makeSession(_ request: TranscriptionRequest) async throws -> TranscriptionSession? { nil }

    func transcribe(_ audio: RecordedAudio, _ request: TranscriptionRequest) async throws -> String {
        try await LocalSpeechRuntime.shared.transcribe(audio, with: model, languages: request.languages, vocabulary: request.vocabulary)
    }
}

// MARK: - ダウンロードの状態（設定画面）

@MainActor
final class LocalModelStore: ObservableObject {
    static let shared = LocalModelStore()

    enum State: Equatable {
        case notDownloaded
        case downloading(Double)
        case ready
        case failed(String)
    }

    @Published private(set) var states: [LocalSpeechModel: State] = [:]

    private init() { refresh() }

    func state(_ id: LocalSpeechModel) -> State { states[id] ?? .notDownloaded }

    func refresh() {
        for id in LocalSpeechModel.allCases where !isBusy(id) {
            states[id] = id.isDownloaded ? .ready : .notDownloaded
        }
    }

    private func isBusy(_ id: LocalSpeechModel) -> Bool {
        if case .downloading = states[id] { return true }
        return false
    }

    /// ダウンロードして、読み込めることを確かめる
    func download(_ id: LocalSpeechModel) {
        guard !isBusy(id) else { return }
        states[id] = .downloading(0)
        Task {
            do {
                try await LocalSpeechRuntime.shared.download(id) { p in
                    Task { @MainActor in
                        // 読み込みの最後に 0 から数え直すことがあるので、進み具合は戻さない
                        if case .downloading(let old) = LocalModelStore.shared.states[id], p > old {
                            LocalModelStore.shared.states[id] = .downloading(min(p, 1))
                        }
                    }
                }
                states[id] = .ready
            } catch {
                states[id] = .failed(error.localizedDescription)
            }
        }
    }

    func delete(_ id: LocalSpeechModel) {
        Task {
            await LocalSpeechRuntime.shared.release(id)
            do {
                try id.deleteFiles()
                states[id] = .notDownloaded
            } catch {
                states[id] = .failed(error.localizedDescription)
            }
        }
    }
}
