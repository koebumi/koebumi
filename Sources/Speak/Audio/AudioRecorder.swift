import AVFoundation

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
/// AVAudioEngine は macOS ではシステムの既定のマイクにしかつながらない（別のマイクを指定しても、すぐ既定に戻す）ため、
/// 設定で選んだマイクで録れる AVCaptureSession を使う。
final class AudioRecorder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

    /// 録音用のキューから呼ばれる
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    /// メインスレッドで呼ばれる（0...1）
    var onLevel: ((Float) -> Void)?

    private var session: AVCaptureSession?
    private let queue = DispatchQueue(label: "Speak.AudioRecorder", qos: .userInteractive)
    /// queue でだけ使う（届いたバッファの形式が変わったら作り直す。Bluetooth のマイクは録音を始めると形式が変わる）
    private var converter: AVAudioConverter?
    private let lock = NSLock()
    private var samples: [Float] = []
    private(set) var isRecording = false

    /// deviceUID が nil のときは自動検出（AudioDevices.automaticInput）のマイクで録る。
    /// 代わりのマイクがないとき、または選んだマイクが外されているときは、システムの既定のマイクで録る。
    func start(deviceUID: String?) throws {
        stopSession()
        lock.withLock { samples = [] }
        let uid = deviceUID ?? AudioDevices.automaticInput()?.uid
        guard let device = uid.flatMap(AVCaptureDevice.init(uniqueID:)) ?? AVCaptureDevice.default(for: .audio) else {
            throw RecorderError.noInput
        }
        let session = AVCaptureSession()
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw RecorderError.engine(error)
        }
        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddInput(input), session.canAddOutput(output) else { throw RecorderError.noInput }
        session.addInput(input)
        session.addOutput(output)
        queue.sync { converter = nil }
        session.startRunning()
        guard session.isRunning else { throw RecorderError.noInput }
        self.session = session
        isRecording = true
    }

    /// 録音を止めて、ここまでの音声を返す。
    func stop() -> RecordedAudio {
        stopSession()
        let captured = lock.withLock { samples }
        return RecordedAudio(samples: captured)
    }

    /// 録音中にここまでの音声をコピーする（ストリーミング認識の途中参加用）
    func snapshot() -> RecordedAudio {
        RecordedAudio(samples: lock.withLock { samples })
    }

    private func stopSession() {
        guard let session else { return }
        session.stopRunning()
        // 止める前に届いていたバッファを処理し終えてから返す（語尾を落とさない）
        queue.sync {}
        self.session = nil
        isRecording = false
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let description = sampleBuffer.formatDescription else { return }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        let frames = AVAudioFrameCount(sampleBuffer.numSamples)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        buffer.frameLength = frames
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList
        ) == noErr else { return }
        process(buffer)
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
