import AVFoundation
import AppKit
import Combine

/// 録音中の音声をストリーミング認識セッションへ渡す。セッションの準備ができるまでは溜めておく。
final class StreamFeeder: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [AVAudioPCMBuffer] = []
    private var session: TranscriptionSession?
    private var closed = false
    private var receivedSamples = 0
    /// reset / restart のたびに増える。遅れて準備できた古いセッションを取り付けないために使う。
    private(set) var epoch = 0

    func reset() {
        lock.withLock {
            pending = []
            session = nil
            closed = false
            receivedSamples = 0
            epoch += 1
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            guard !closed else { return }
            receivedSamples += Int(buffer.frameLength)
            if let session { session.append(buffer) } else { pending.append(buffer) }
        }
    }

    /// セッションを取り付ける。古い epoch のものなら取り付けずに false を返す。
    func attach(_ s: TranscriptionSession, epoch expected: Int) -> Bool {
        lock.withLock {
            guard !closed, epoch == expected else { return false }
            session = s
            for b in pending { s.append(b) }
            pending = []
            return true
        }
    }

    var currentEpoch: Int { lock.withLock { epoch } }

    /// 認識言語を途中で変えたとき、ここまでの音声を新しいセッションに渡し直す
    func restart(with recorder: AudioRecorder) {
        lock.withLock {
            session = nil
            epoch += 1
            let snapshot = recorder.snapshot().samples
            let upTo = min(receivedSamples, snapshot.count)
            pending = AppleSpeechSession.buffer(from: Array(snapshot[0..<upTo])).map { [$0] } ?? []
        }
    }

    func close() {
        lock.withLock {
            closed = true
            pending = []
        }
    }
}

struct AnswerCardContent: Equatable {
    var question: String
    var answer: String
}

@MainActor
final class DictationController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording
        case processing
        case message(String, isError: Bool)
    }

    @Published private(set) var phase: Phase = .idle {
        didSet { hotkeys.refreshState() }
    }
    @Published private(set) var mode: Mode = .dictate {
        didSet { hotkeys.refreshState() }
    }
    @Published private(set) var levels: [Float] = Array(repeating: 0, count: 22)
    @Published private(set) var elapsed: TimeInterval = 0
    @Published var answer: AnswerCardContent? {
        didSet { hotkeys.refreshState() }
    }
    @Published private(set) var retrying: Set<UUID> = []

    let settingsStore = SettingsStore.shared
    let history = HistoryStore.shared
    let dictionary = DictionaryStore.shared
    let personalization = PersonalizationStore.shared
    let stats = StatsStore.shared
    let recorder = AudioRecorder()
    let hotkeys = HotkeyManager()
    let watcher = CorrectionWatcher()

    private let feeder = StreamFeeder()
    private var sessionTask: Task<TranscriptionSession?, Error>?
    private var processingTask: Task<Void, Never>?
    private var selectionTask: Task<SelectionInfo?, Never>?
    private var surroundingTask: Task<SurroundingText?, Never>?
    private var context = AppContextInfo.unknown
    private var muteToken: AudioDevices.MuteToken?
    private var recordStart = Date()
    private var tick: Timer?
    private var messageTask: Task<Void, Never>?
    private var sessionLanguage = "ja-JP"
    /// 録音ごとに増える番号。キャンセル済みの古い処理が新しい録音の状態を書き換えないようにする。
    private var generation = 0

    /// 1 回の録音の処理に必要なものをまとめたもの
    private struct Job {
        var generation: Int
        var mode: Mode
        var context: AppContextInfo
        var language: String
        var targetLanguage: String?
        var session: Task<TranscriptionSession?, Error>?
        var selection: Task<SelectionInfo?, Never>?
        var surrounding: Task<SurroundingText?, Never>?
    }

    static let maxDuration: TimeInterval = 10 * 60

    private var settings: AppSettings { settingsStore.settings }

    var engineState: EngineState {
        switch phase {
        case .recording: return .recording(mode)
        case .processing: return .busy
        case .idle, .message: return .idle
        }
    }

    init() {
        hotkeys.stateProvider = { [unowned self] in engineState }
        hotkeys.onCommand = { [unowned self] command in handle(command) }
        hotkeys.escapeTargetProvider = { [unowned self] in answer != nil }
        hotkeys.onIdleEscape = { [unowned self] in answer = nil }
        recorder.onLevel = { [weak self] level in self?.pushLevel(level) }
        recorder.onBuffer = { [feeder] buffer in feeder.append(buffer) }
        watcher.onLearn = { [weak self] term, replaced in
            guard let self, settings.autoAddDictionary else { return }
            dictionary.add(term, source: .auto, replaced: replaced)
        }
    }

    func handle(_ command: HotkeyCommand) {
        switch command {
        case .begin(let m): begin(m)
        case .switchMode(let m): switchMode(m)
        case .finish: finish()
        case .cancel: cancel()
        case .abort: abort()
        }
    }

    // MARK: - 録音

    func begin(_ newMode: Mode) {
        if case .recording = phase { return }
        if phase == .processing { return }
        messageTask?.cancel()

        guard Permissions.microphoneGranted else {
            if Permissions.microphoneDenied {
                showMessage(t("マイクへのアクセスを許可してください", "Allow microphone access in System Settings"), isError: true)
                Permissions.openMicrophoneSettings()
            } else {
                Task { _ = await Permissions.requestMicrophone() }
            }
            return
        }

        answer = nil
        watcher.stop()
        // 文体の学習が AI を使っていると、この録音の整形がその後ろで待たされる
        personalization.cancelAnalysis()
        generation += 1
        mode = newMode
        context = AppContext.current(overrides: settings.appCategoryOverrides)
        if let pid = context.pid, pid != ProcessInfo.processInfo.processIdentifier {
            TextInserter.enableAccessibility(for: pid)
        }
        selectionTask = newMode == .ask ? Task { await TextInserter.selectedText() } : nil
        surroundingTask = readSurrounding(mode: newMode)

        feeder.reset()
        do {
            try recorder.start(deviceUID: settings.microphoneUID)
        } catch {
            showMessage(error.localizedDescription, isError: true)
            return
        }
        Sounds.start()
        if settings.muteWhileDictating {
            Task {
                try? await Task.sleep(for: .milliseconds(150))  // 開始音を鳴らしてからミュート
                if phase == .recording, muteToken == nil { muteToken = AudioDevices.muteOutput() }
            }
        }

        phase = .recording
        recordStart = Date()
        elapsed = 0
        levels = Array(repeating: 0, count: levels.count)
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.onTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tick = timer
        startSession(language: settings.currentDictationLanguage)
        if settings.sttProvider == .local {
            LocalSpeechRuntime.shared.prewarm(settings.localSpeechModel)
        }
        if settings.llmProvider == .appleOnDevice {
            AppleLLMEngine.prewarm(mode: newMode, language: settings.currentDictationLanguage)
        }
    }

    /// 入力欄とウィンドウの文字列を、録音と並行して読む（応答の遅いアプリでもメインスレッドを止めない）
    private func readSurrounding(mode: Mode) -> Task<SurroundingText?, Never>? {
        let s = settings
        guard s.contextAwareness != .off, mode != .ask, context.pid != ProcessInfo.processInfo.processIdentifier else { return nil }
        let includeScreen = s.shareSurroundingWithLLM || s.shareSurroundingWithSTT
        let pid = context.pid
        return Task.detached(priority: .userInitiated) { SurroundingTextReader.read(pid: pid, includeScreen: includeScreen) }
    }

    private func startSession(language: String) {
        sessionLanguage = language
        let transcriber = TranscriberFactory.make(settings: settings, language: language)
        let request = transcriptionRequest(language: language)
        let feeder = feeder
        let epoch = feeder.currentEpoch
        let surrounding = settings.shareSurroundingWithSTT ? surroundingTask : nil
        sessionTask = Task {
            // 画面に出ている人名や用語を音声認識のヒントにする（読み取りは 0.3 秒ほどで終わる。その間の音声は溜めてある）
            let terms = await surrounding?.value?.terms ?? []
            guard let session = try await transcriber.makeSession(Self.addingTerms(terms, to: request)) else { return nil }
            guard feeder.attach(session, epoch: epoch) else {
                session.cancel()
                return nil
            }
            return session
        }
    }

    private func transcriptionRequest(language: String) -> TranscriptionRequest {
        TranscriptionRequest(languages: settings.sttLanguages(current: language), vocabulary: dictionary.terms)
    }

    /// 画面から拾った語を辞書の前に足す（ヒントの数に上限があるため、その場の語を優先する）
    private static func addingTerms(_ terms: [String], to request: TranscriptionRequest) -> TranscriptionRequest {
        var r = request
        r.vocabulary = terms.filter { !request.vocabulary.contains($0) } + request.vocabulary
        return r
    }

    func switchMode(_ newMode: Mode) {
        guard phase == .recording, newMode != mode else { return }
        mode = newMode
        if settings.llmProvider == .appleOnDevice {
            AppleLLMEngine.prewarm(mode: newMode, language: sessionLanguage)
        }
        if newMode == .ask, selectionTask == nil {
            selectionTask = Task { await TextInserter.selectedText() }
        }
    }

    /// 録音中に話す言語を切り替える（Apple の音声認識は言語を自動判定しないため）
    func changeDictationLanguage(_ language: String) {
        settingsStore.settings.activeDictationLanguage = language
        guard phase == .recording, settings.sttProvider == .apple, language != sessionLanguage else { return }
        let old = sessionTask
        Task { (try? await old?.value)??.cancel() }
        feeder.restart(with: recorder)
        startSession(language: language)
    }

    func changeTranslationTarget(_ target: String) {
        settingsStore.settings.activeTranslationTarget = target
    }

    func finish() {
        guard phase == .recording else { return }
        phase = .processing
        let job = Job(
            generation: generation, mode: mode, context: context, language: sessionLanguage,
            targetLanguage: mode == .translate ? settings.currentTranslationTarget : nil,
            session: sessionTask, selection: selectionTask, surrounding: surroundingTask
        )
        sessionTask = nil
        selectionTask = nil
        surroundingTask = nil
        processingTask = Task {
            // キーを離した直後の語尾まで録れるよう、少し待ってから止める（止めた後に終了音を鳴らす）
            try? await Task.sleep(for: .milliseconds(150))
            guard job.generation == generation else { return }
            let audio = stopRecording()
            Sounds.stop()
            await process(audio: audio, job: job)
        }
    }

    func cancel() {
        switch phase {
        case .recording:
            _ = stopRecording()
            discardSession()
            Sounds.cancel()
            phase = .idle
        case .processing:
            processingTask?.cancel()
            processingTask = nil
            generation += 1
            if recorder.isRecording { _ = stopRecording() }
            Sounds.cancel()
            phase = .idle
        default:
            answer = nil
        }
    }

    /// Fn + 矢印キーなど、ディクテーションのつもりではなかった操作。音を鳴らさず黙って止める。
    func abort() {
        guard phase == .recording else { return }
        _ = stopRecording()
        discardSession()
        phase = .idle
    }

    private func stopRecording() -> RecordedAudio {
        tick?.invalidate()
        tick = nil
        let audio = recorder.stop()
        if let token = muteToken {
            AudioDevices.restoreOutput(token)
            muteToken = nil
        }
        return audio
    }

    private func discardSession() {
        feeder.close()
        Self.cancelSession(sessionTask)
        sessionTask = nil
        selectionTask = nil
        surroundingTask = nil
    }

    private func onTick() {
        elapsed = Date().timeIntervalSince(recordStart)
        if elapsed >= Self.maxDuration { finish() }
    }

    private func pushLevel(_ level: Float) {
        guard phase == .recording else { return }
        levels.removeFirst()
        levels.append(level)
    }

    // MARK: - 認識と整形

    private func process(audio: RecordedAudio, job: Job) async {
        let isCurrent = { [unowned self] in job.generation == generation && !Task.isCancelled }
        if audio.isSilent {
            Self.cancelSession(job.session)
            showMessage(t("音声が検出されませんでした", "No speech detected"), isError: false)
            return
        }

        let s = settings
        let mode = job.mode
        let ctx = job.context
        let id = UUID()
        var item = HistoryItem(id: id, mode: mode)
        item.appName = ctx.appName
        item.appBundleID = ctx.bundleID
        item.category = ctx.category
        item.duration = audio.duration
        item.language = job.language
        item.targetLanguage = job.targetLanguage
        if s.keepAudio, s.historyRetention != .never {
            item.audioFile = await Task.detached(priority: .utility) { HistoryStore.saveAudio(audio, id: id) }.value
        }

        let surrounding = await job.surrounding?.value
        if let surrounding {
            NSLog("Speak: surrounding text before=\(surrounding.before.count) after=\(surrounding.after.count) screen=\(surrounding.screen.count)")
        }

        do {
            let raw = try await transcribe(audio, session: job.session, language: job.language,
                                           terms: s.shareSurroundingWithSTT ? surrounding?.terms ?? [] : [])
            try Task.checkCancellation()
            guard !raw.isEmpty else { throw TranscriptionError.empty }
            item.rawTranscript = raw

            switch mode {
            case .dictate, .translate:
                let (output, warning) = try await polish(raw, mode: mode, category: ctx.category, appName: ctx.appName,
                                                         target: job.targetLanguage, language: job.language, surrounding: surrounding)
                try Task.checkCancellation()
                // 「えーと」だけなど、整形すると何も残らなかった
                guard !output.isEmpty else { throw TranscriptionError.empty }
                await TextInserter.paste(output, keepInClipboard: s.keepResultInClipboard)
                item.output = output
                item.wordCount = StatsStore.wordCount(output)
                stats.record(words: item.wordCount, seconds: audio.duration)
                if mode == .dictate {
                    if s.autoAddDictionary, isCurrent() { watcher.start(inserted: output) }
                    if s.personalizationEnabled {
                        personalization.addSample(StyleSample(category: ctx.category, text: raw), engine: LLMFactory.make(settings: s))
                    }
                }
                history.add(item, retention: s.historyRetention)
                if isCurrent() {
                    if let warning { showMessage(warning, isError: true) } else { phase = .idle }
                }

            case .ask:
                let selection = await job.selection?.value
                item.selectedText = selection?.text
                let outcome = try await ask(raw, selection: selection, appName: ctx.appName)
                try Task.checkCancellation()
                try await apply(outcome, question: raw, selection: selection, item: &item, isCurrent: isCurrent)
                history.add(item, retention: s.historyRetention)
            }
        } catch {
            // キャンセルされた（URLSession は URLError.cancelled を投げる）なら履歴に残さず黙って終える
            if error is CancellationError || Task.isCancelled || job.generation != generation {
                Self.cancelSession(job.session)
                return
            }
            item.status = .failed
            item.errorMessage = error.localizedDescription
            history.add(item, retention: s.historyRetention)
            guard isCurrent() else { return }
            Sounds.error()
            showMessage(error.localizedDescription, isError: true)
        }
    }

    private static func cancelSession(_ task: Task<TranscriptionSession?, Error>?) {
        Task { (try? await task?.value)??.cancel() }
    }

    private func transcribe(_ audio: RecordedAudio, session task: Task<TranscriptionSession?, Error>?, language: String,
                            terms: [String] = []) async throws -> String {
        if let task, let session = try await task.value {
            do {
                return try await session.finish()
            } catch {
                if Task.isCancelled { throw CancellationError() }
                NSLog("Speak: streaming transcription failed, retrying from audio: \(error)")
            }
        }
        let transcriber = TranscriberFactory.make(settings: settings, language: language)
        return try await transcriber.transcribe(audio, Self.addingTerms(terms, to: transcriptionRequest(language: language)))
    }

    /// 整形済みテキストと、AI 整形を諦めて簡易整形にしたときの警告を返す
    private func polish(_ raw: String, mode: Mode, category: AppCategory, appName: String, target: String?, language: String,
                        surrounding: SurroundingText? = nil) async throws -> (String, String?) {
        let s = settings
        let preset = s.style(for: category)
        let request = PolishRequest(
            transcript: raw,
            mode: mode,
            sourceLanguages: s.sttLanguages(current: language),
            targetLanguage: mode == .translate ? (target ?? s.currentTranslationTarget) : nil,
            appName: appName,
            category: category,
            styleDescription: preset.styleDescription(for: category),
            personalStyle: preset == .auto && s.personalizationEnabled ? personalization.profile.promptDescription(for: category) : nil,
            vocabulary: dictionary.terms,
            corrections: s.personalizationEnabled ? personalization.corrections : [],
            aliases: dictionary.aliases,
            aliasHints: dictionary.aliasHints,
            notation: s.japaneseNotation,
            surrounding: surrounding,
            surroundingInPrompt: s.shareSurroundingWithLLM,
            allowsRewording: preset != .auto
        )
        let output = try await Polisher.run(request, engine: LLMFactory.make(settings: s))
        return (output.text, output.warning)
    }

    private func ask(_ query: String, selection: SelectionInfo?, appName: String) async throws -> AskOutcome {
        guard let engine = LLMFactory.make(settings: settings) else {
            throw LLMError.unavailable(t("Ask anything には AI エンジンが必要です（設定 > AI エンジン）", "Ask anything needs an AI engine (Settings > AI engines)"))
        }
        let request = AskRequest(
            query: Polisher.prepare(query, aliases: dictionary.aliases),
            selection: selection?.text,
            selectionEditable: selection?.editable ?? false,
            hasFocusedTextField: selection == nil && TextInserter.hasFocusedTextField(),
            appName: appName,
            vocabulary: dictionary.terms
        )
        return try await engine.ask(request)
    }

    private func apply(_ outcome: AskOutcome, question: String, selection: SelectionInfo?, item: inout HistoryItem,
                       isCurrent: () -> Bool) async throws {
        switch outcome {
        case .replace(let text):
            item.askAction = "replace"
            item.output = text
            if selection?.editable == true {
                await TextInserter.paste(text, keepInClipboard: settings.keepResultInClipboard)
            } else if isCurrent() {
                answer = AnswerCardContent(question: question, answer: text)
            }
        case .insert(let text):
            item.askAction = "insert"
            item.output = text
            await TextInserter.paste(text, keepInClipboard: settings.keepResultInClipboard)
        case .openURL(let url, let description):
            item.askAction = "open_url"
            item.output = url.absoluteString
            NSWorkspace.shared.open(url)
            if isCurrent() {
                let host = url.host() ?? url.absoluteString
                showMessage(description.isEmpty ? t("\(host) を開きました", "Opened \(host)") : description, isError: false)
            }
            return
        case .answer(let text):
            item.askAction = "answer"
            item.output = text
            if isCurrent() {
                answer = AnswerCardContent(question: question, answer: text.isEmpty ? t("（回答が空でした）", "(Empty answer)") : text)
            }
        }
        if isCurrent() { phase = .idle }
    }

    // MARK: - 履歴からの操作

    /// 保存した音声をもう一度認識・整形する。結果はクリップボードにコピーする。
    func retry(_ item: HistoryItem) {
        guard let url = item.audioURL, let data = try? Data(contentsOf: url), let audio = WAV.decode(data) else {
            showMessage(t("この履歴には音声が保存されていません", "No audio saved for this item"), isError: true)
            return
        }
        retrying.insert(item.id)
        Task {
            defer { retrying.remove(item.id) }
            var updated = item
            do {
                let language = item.language ?? settings.currentDictationLanguage
                let transcriber = TranscriberFactory.make(settings: settings, language: language)
                let raw = try await transcriber.transcribe(audio, transcriptionRequest(language: language))
                guard !raw.isEmpty else { throw TranscriptionError.empty }
                updated.rawTranscript = raw
                if item.mode == .ask {
                    let selection = item.selectedText.map { SelectionInfo(text: $0, editable: false) }
                    switch try await ask(raw, selection: selection, appName: item.appName) {
                    case .answer(let s), .replace(let s), .insert(let s): updated.output = s
                    case .openURL(let u, _): updated.output = u.absoluteString
                    }
                } else {
                    let (output, warning) = try await polish(raw, mode: item.mode, category: item.category, appName: item.appName,
                                                             target: item.targetLanguage, language: language)
                    updated.output = output
                    updated.wordCount = StatsStore.wordCount(output)
                    if let warning { updated.errorMessage = warning }
                }
                updated.status = .success
                if updated.errorMessage != nil, item.mode == .ask { updated.errorMessage = nil }
                history.update(updated)
                TextInserter.copyToClipboard(updated.output)
                showMessage(t("再処理しました。結果をコピーしました", "Reprocessed and copied to the clipboard"), isError: false)
            } catch {
                updated.status = .failed
                updated.errorMessage = error.localizedDescription
                history.update(updated)
                showMessage(error.localizedDescription, isError: true)
            }
        }
    }

    func pasteLastResult() {
        guard let text = history.lastOutput else { return }
        Task { await TextInserter.paste(text, keepInClipboard: settings.keepResultInClipboard) }
    }

    func runStyleAnalysisNow() {
        guard let engine = LLMFactory.make(settings: settings) else { return }
        Task { await personalization.analyze(engine: engine) }
    }

    /// 開発用（--snapshot）: 音声バーの見た目を確認するために状態を直接設定する
    func setPreviewState(_ phase: Phase, mode: Mode) {
        self.phase = phase
        self.mode = mode
        levels = (0..<levels.count).map { i in Float(0.25 + 0.6 * abs(sin(Double(i) / 2.3))) }
        elapsed = 12
    }

    // MARK: - メッセージ

    func showMessage(_ text: String, isError: Bool) {
        messageTask?.cancel()
        let message = Phase.message(text, isError: isError)
        phase = message
        messageTask = Task {
            try? await Task.sleep(for: .seconds(isError ? 4 : 2))
            if !Task.isCancelled, phase == message { phase = .idle }
        }
    }
}
