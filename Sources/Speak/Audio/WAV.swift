import Foundation

/// 16 kHz モノラルの録音データ
struct RecordedAudio {
    var samples: [Float]
    var sampleRate: Double = 16000

    var duration: TimeInterval { Double(samples.count) / sampleRate }

    var peak: Float { samples.reduce(0) { max($0, abs($1)) } }

    var rms: Float {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return (sum / Float(samples.count)).squareRoot()
    }

    /// 声が入っていないとみなす（無音・極端に短い録音）
    var isSilent: Bool { duration < 0.3 || peak < 0.008 }

    /// ささやき声でも認識しやすいよう、ピークを -1 dBFS 付近まで持ち上げる（最大 +24 dB）。
    func normalized() -> RecordedAudio {
        let p = peak
        guard p > 0 else { return self }
        let gain = min(0.89 / p, 16)
        guard gain > 1.05 else { return self }
        return RecordedAudio(samples: samples.map { $0 * gain }, sampleRate: sampleRate)
    }

    /// maxDuration 以下の区間に分ける。単語の途中で切らないよう、区間の後半で声が最も小さい 0.3 秒の中央で区切る。
    func split(maxDuration: TimeInterval) -> [RecordedAudio] {
        let maxCount = Int(maxDuration * sampleRate)
        let frame = max(Int(sampleRate / 100), 1)
        let window = 30
        guard maxCount >= frame * window * 4, samples.count > maxCount else { return [self] }
        // 10 ミリ秒ごとの音の大きさ
        let energy = stride(from: 0, to: samples.count, by: frame).map { start in
            samples[start..<min(start + frame, samples.count)].reduce(Float(0)) { $0 + $1 * $1 }
        }
        var parts: [RecordedAudio] = []
        var start = 0
        while samples.count - start > maxCount {
            let candidates = (start + maxCount / 2) / frame...(start + maxCount) / frame - window
            let quietest = candidates.min { energy[$0..<$0 + window].reduce(0, +) < energy[$1..<$1 + window].reduce(0, +) }!
            let cut = (quietest + window / 2) * frame
            parts.append(RecordedAudio(samples: Array(samples[start..<cut]), sampleRate: sampleRate))
            start = cut
        }
        parts.append(RecordedAudio(samples: Array(samples[start...]), sampleRate: sampleRate))
        return parts
    }
}

/// 16-bit PCM WAV のエンコード・デコード（履歴の音声保存とクラウド認識のアップロード用）
enum WAV {
    static func encode(_ audio: RecordedAudio) -> Data {
        let sampleRate = UInt32(audio.sampleRate)
        let dataSize = UInt32(audio.samples.count * 2)
        var data = Data(capacity: Int(dataSize) + 44)
        func append<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36) + dataSize)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))  // PCM
        append(UInt16(1))  // mono
        append(sampleRate)
        append(sampleRate * 2)
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(dataSize)
        for s in audio.samples {
            let clamped = max(-1, min(1, s))
            append(Int16(clamped * Float(Int16.max)))
        }
        return data
    }

    static func decode(_ data: Data) -> RecordedAudio? {
        guard data.count >= 44, String(decoding: data[0..<4], as: UTF8.self) == "RIFF" else { return nil }
        func u32(_ o: Int) -> UInt32 { data[o..<o + 4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian }
        func u16(_ o: Int) -> UInt16 { data[o..<o + 2].withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }.littleEndian }
        var offset = 12
        var sampleRate: Double = 16000
        var channels = 1
        while offset + 8 <= data.count {
            let id = String(decoding: data[offset..<offset + 4], as: UTF8.self)
            let size = Int(u32(offset + 4))
            let body = offset + 8
            if id == "fmt " {
                channels = Int(u16(body + 2))
                sampleRate = Double(u32(body + 4))
            } else if id == "data" {
                let end = min(body + size, data.count)
                var samples: [Float] = []
                samples.reserveCapacity((end - body) / 2 / max(channels, 1))
                var i = body
                while i + 2 * channels <= end {
                    let v = data[i..<i + 2].withUnsafeBytes { $0.loadUnaligned(as: Int16.self) }.littleEndian
                    samples.append(Float(v) / Float(Int16.max))
                    i += 2 * channels
                }
                return RecordedAudio(samples: samples, sampleRate: sampleRate)
            }
            offset = body + size + (size % 2)
        }
        return nil
    }
}
