// IBM Granite Speech 5.0 の特徴量（log-mel と delta）を作る。
// transformers（Apache License 2.0）の feature_extraction_granite_speech5.py と、
// そこで使う torchaudio の MelSpectrogram・compute_deltas の計算を Swift に移した。
// Copyright 2026 IBM and The HuggingFace Team. Licensed under the Apache License, Version 2.0.

import Accelerate
import Foundation

/// 16 kHz の音声から、エンコーダーに入れる特徴量を作る。
/// 1 フレーム（10 ms）ごとに 80 次元の log-mel とその delta を並べ、続く 2 フレームをまとめて 320 次元にする（20 ms ごとに 1 つ）。
struct GraniteSpeechFeatureExtractor {
    let config: GraniteSpeechFeatureConfig
    /// 周波数の数（n_fft / 2 + 1）× メルの数。torchaudio の melscale_fbanks（HTK、正規化なし）と同じ
    let melFilters: [Float]
    /// n_fft の長さの窓。win_length のハン窓を真ん中に置き、両側は 0（torch.stft と同じ）
    let window: [Float]

    init(config: GraniteSpeechFeatureConfig = .init()) {
        self.config = config
        melFilters = Self.melFilterBank(config: config)
        window = Self.paddedHannWindow(winLength: config.winLength, nFFT: config.nFFT)
    }

    struct Output {
        /// frames × 320 を行ごとに並べたもの
        var values: [Float]
        /// エンコーダーのフレームの数（20 ms ごと）
        var frames: Int
    }

    /// 音声（16 kHz、モノラル）から特徴量を作る。短すぎて 1 フレームもないときは frames が 0。
    func callAsFunction(_ audio: [Float]) -> Output {
        let hop = config.hopLength
        let melCount = config.numMelBins
        let stack = GraniteSpeechFeatureConfig.frameStacking
        // 2 フレームずつまとめるので、端の半端なフレームは捨てずに音声を 0 で伸ばして埋める
        let melFrames = audio.count / hop
        guard melFrames > 0 else { return Output(values: [], frames: 0) }
        let numFrames = stack * ((melFrames + stack - 1) / stack)
        var signal = audio
        let needed = (numFrames - 1) * hop + 1
        if signal.count < needed { signal += [Float](repeating: 0, count: needed - signal.count) }

        let power = powerSpectrogram(signal, frames: numFrames)
        var mel = melSpectrogram(power, frames: numFrames)

        // log10 を取り、音声全体でいちばん大きい値から logmelFloorDB 下で切ってから、/ 4 + 1 で揃える
        var peak = -Float.infinity
        for i in mel.indices {
            mel[i] = log10(max(mel[i], 1e-10))
            peak = max(peak, mel[i])
        }
        let floor = peak - config.logmelFloorDB
        for i in mel.indices { mel[i] = max(mel[i], floor) / 4 + 1 }

        let deltas = Self.deltas(mel, frames: numFrames, bins: melCount, winLength: config.deltaWinLength)

        // フレーム t は [log-mel(t), delta(t)] の 160 次元。続く 2 フレームを並べて 320 次元にする
        let width = melCount * GraniteSpeechFeatureConfig.deltaExpansion
        var values = [Float](repeating: 0, count: numFrames * width)
        for t in 0..<numFrames {
            for m in 0..<melCount {
                values[t * width + m] = mel[t * melCount + m]
                values[t * width + melCount + m] = deltas[t * melCount + m]
            }
        }
        return Output(values: values, frames: numFrames / stack)
    }

    // MARK: - スペクトログラム

    /// フレームごとのパワー（frames × (n_fft/2 + 1)）。torch.stft（center=True、反射で埋める）と同じ位置で切り出す。
    func powerSpectrogram(_ signal: [Float], frames: Int) -> [Float] {
        let nFFT = config.nFFT
        let half = nFFT / 2
        let bins = half + 1
        let log2n = vDSP_Length(log2(Double(nFFT)).rounded())
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return [] }
        defer { vDSP_destroy_fftsetup(setup) }

        var power = [Float](repeating: 0, count: frames * bins)
        var frame = [Float](repeating: 0, count: nFFT)
        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        let count = signal.count
        for t in 0..<frames {
            // 両端は n_fft / 2 だけ反射で伸ばしたものとして読む
            let start = t * config.hopLength - half
            for n in 0..<nFFT {
                frame[n] = signal[Self.reflect(start + n, count: count)] * window[n]
            }
            real.withUnsafeMutableBufferPointer { re in
                imag.withUnsafeMutableBufferPointer { im in
                    var split = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                    frame.withUnsafeBytes { raw in
                        vDSP_ctoz(raw.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(half))
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                }
            }
            // vDSP の実数 FFT は 2 倍の値を返す。0 と n_fft/2 の成分は real[0] と imag[0] に入る
            let row = t * bins
            power[row] = (real[0] / 2) * (real[0] / 2)
            power[row + half] = (imag[0] / 2) * (imag[0] / 2)
            for k in 1..<half {
                power[row + k] = (real[k] * real[k] + imag[k] * imag[k]) / 4
            }
        }
        return power
    }

    /// メルのパワー（frames × メルの数）
    func melSpectrogram(_ power: [Float], frames: Int) -> [Float] {
        let bins = config.nFFT / 2 + 1
        var mel = [Float](repeating: 0, count: frames * config.numMelBins)
        vDSP_mmul(power, 1, melFilters, 1, &mel, 1,
                  vDSP_Length(frames), vDSP_Length(config.numMelBins), vDSP_Length(bins))
        return mel
    }

    /// 反射で伸ばした信号の i 番目が、元の信号のどこか（端の値は繰り返さない。torch の reflect と同じ）
    static func reflect(_ i: Int, count: Int) -> Int {
        guard count > 1 else { return 0 }
        let period = 2 * (count - 1)
        var j = i % period
        if j < 0 { j += period }
        return j < count ? j : period - j
    }

    // MARK: - 係数

    static func paddedHannWindow(winLength: Int, nFFT: Int) -> [Float] {
        var window = [Float](repeating: 0, count: nFFT)
        let left = (nFFT - winLength) / 2
        for n in 0..<winLength {
            // torch.hann_window の既定（periodic=True）
            window[left + n] = Float(0.5 - 0.5 * cos(2 * Double.pi * Double(n) / Double(winLength)))
        }
        return window
    }

    /// torchaudio.functional.melscale_fbanks（mel_scale="htk"、norm=None、f_min=0、f_max=sr/2）
    static func melFilterBank(config: GraniteSpeechFeatureConfig) -> [Float] {
        let bins = config.nFFT / 2 + 1
        let mels = config.numMelBins
        let nyquist = Double(config.samplingRate / 2)
        func hzToMel(_ hz: Double) -> Double { 2595 * log10(1 + hz / 700) }
        func melToHz(_ mel: Double) -> Double { 700 * (pow(10, mel / 2595) - 1) }
        let maxMel = hzToMel(nyquist)
        let points = (0..<(mels + 2)).map { melToHz(maxMel * Double($0) / Double(mels + 1)) }
        var filters = [Float](repeating: 0, count: bins * mels)
        for k in 0..<bins {
            let freq = nyquist * Double(k) / Double(bins - 1)
            for m in 0..<mels {
                let down = (freq - points[m]) / (points[m + 1] - points[m])
                let up = (points[m + 2] - freq) / (points[m + 2] - points[m + 1])
                filters[k * mels + m] = Float(max(0, min(down, up)))
            }
        }
        return filters
    }

    /// torchaudio.functional.compute_deltas（端は同じ値で伸ばす）。values は frames × bins
    static func deltas(_ values: [Float], frames: Int, bins: Int, winLength: Int) -> [Float] {
        let n = (winLength - 1) / 2
        let denom = Float(n * (n + 1) * (2 * n + 1)) / 3
        var out = [Float](repeating: 0, count: values.count)
        for t in 0..<frames {
            for b in 0..<bins {
                var sum: Float = 0
                for k in 1...n {
                    let next = values[min(t + k, frames - 1) * bins + b]
                    let prev = values[max(t - k, 0) * bins + b]
                    sum += Float(k) * (next - prev)
                }
                out[t * bins + b] = sum / denom
            }
        }
        return out
    }
}
