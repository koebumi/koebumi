import AVFoundation
import AudioToolbox
import CoreAudio

enum RecorderError: LocalizedError {
    case noInput
    case engine(Error)

    var errorDescription: String? {
        switch self {
        case .noInput: return t("マイクが見つかりません", "No microphone found")
        case .engine(let e): return t("マイクを開始できません: ", "Could not start the microphone: ") + e.localizedDescription
        }
    }
}

/// マイク入力を 16 kHz モノラルに変換しながら録音する。
/// 変換済みバッファは onBuffer でストリーミング認識へ、音量は onLevel で UI へ渡す。
final class AudioRecorder: @unchecked Sendable {
    static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

    /// オーディオスレッドから呼ばれる
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    /// メインスレッドで呼ばれる（0...1）
    var onLevel: ((Float) -> Void)?

    private var engine: AVAudioEngine?
    /// オーディオスレッドでだけ使う（届いたバッファの形式が変わったら作り直す）
    private var converter: AVAudioConverter?
    private var configObserver: NSObjectProtocol?
    private let lock = NSLock()
    private var samples: [Float] = []
    private(set) var isRecording = false

    func start(deviceUID: String?) throws {
        stopEngine()
        lock.withLock { samples = [] }
        let engine = AVAudioEngine()
        let input = engine.inputNode

        if let deviceUID, let deviceID = AudioDevices.deviceID(forUID: deviceUID), let unit = input.audioUnit {
            var id = deviceID
            AudioUnitSetProperty(
                unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                &id, UInt32(MemoryLayout<AudioDeviceID>.size)
            )
        }

        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw RecorderError.noInput }
        converter = nil
        installTap(on: engine)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw RecorderError.engine(error)
        }
        self.engine = engine
        isRecording = true

        // Bluetooth ヘッドセットの切り替えなどで入力形式が変わったら、録音を続けたままつなぎ直す
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            guard let self, let engine = self.engine else { return }
            engine.inputNode.removeTap(onBus: 0)
            self.installTap(on: engine)
            try? engine.start()
        }
    }

    private func installTap(on engine: AVAudioEngine) {
        // format: nil で入力ノードの現在の形式に合わせる（形式の不一致による例外を避ける）
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            self?.process(buffer)
        }
    }

    /// 録音を止めて、ここまでの音声を返す。
    func stop() -> RecordedAudio {
        stopEngine()
        let captured = lock.withLock { samples }
        return RecordedAudio(samples: captured)
    }

    /// 録音中にここまでの音声をコピーする（ストリーミング認識の途中参加用）
    func snapshot() -> RecordedAudio {
        RecordedAudio(samples: lock.withLock { samples })
    }

    private func stopEngine() {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        isRecording = false
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: Self.format)
        }
        guard let converter else { return }
        let ratio = Self.format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: Self.format, frameCapacity: capacity) else { return }

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
        guard error == nil, out.frameLength > 0, let channel = out.floatChannelData?[0] else { return }

        let chunk = Array(UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
        lock.withLock { samples.append(contentsOf: chunk) }
        onBuffer?(out)

        var sum: Float = 0
        for s in chunk { sum += s * s }
        let rms = (sum / Float(chunk.count)).squareRoot()
        // 声の大きさを見やすい 0...1 に変換（約 -50 dB を 0 とする）
        let db = 20 * log10(max(rms, 1e-6))
        let level = max(0, min(1, (db + 50) / 45))
        DispatchQueue.main.async { [weak self] in self?.onLevel?(level) }
    }
}
