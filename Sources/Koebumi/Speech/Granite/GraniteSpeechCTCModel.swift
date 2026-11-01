// IBM Granite Speech 5.0 470M TurboCTC を、この Mac の MLX で動かす音声認識モデル。
// transformers（Apache License 2.0）の modeling_granite_speech5.py の GraniteSpeech5ForCTC.generate と、
// processor_config.json・tokenizer.json の扱いを Swift に移した。
// Copyright 2026 IBM and The HuggingFace Team. Licensed under the Apache License, Version 2.0.

import AudioCommon
import Foundation
import MLX

/// 非自己回帰の CTC なので、音声全体を 1 回エンコーダーに通すだけで書き起こせる。
/// アテンションは 128 フレーム（約 10 秒）ずつのブロックの中だけを見るので、長い音声もそのまま渡せる（メモリは長さに比例する）。
final class GraniteSpeechCTCModel: SpeechRecognitionModel, ModelMemoryManageable {
    static let defaultModelId = "ibm-granite/granite-speech-5.0-470m-turboctc"
    /// Hugging Face から取ってくるファイル。重みは bf16 で約 0.95 GB
    static let files = ["config.json", "model.safetensors", "processor_config.json", "tokenizer.json", "tokenizer_config.json"]

    let featureExtractor: GraniteSpeechFeatureExtractor
    let tokenizer: GraniteSpeechTokenizer
    /// unload で手放す
    private var encoder: GraniteSpeechEncoder?

    /// ダウンロード済みのディレクトリから読み込む。dtype は行列の計算と重みの型（既定は fp16）。
    init(directory: URL, dtype: DType = .float16) throws {
        func read(_ name: String) throws -> Data { try Data(contentsOf: directory.appendingPathComponent(name)) }
        let config = try GraniteSpeechConfig(json: read("config.json"))
        featureExtractor = GraniteSpeechFeatureExtractor(config: try GraniteSpeechFeatureConfig(json: read("processor_config.json")))
        tokenizer = try GraniteSpeechTokenizer(
            tokenizerJSON: read("tokenizer.json"),
            tokenizerConfigJSON: try? read("tokenizer_config.json"),
            fallbackBlankId: config.padTokenId)
        guard featureExtractor.config.numMelBins == config.numMelBins else {
            throw GraniteSpeechError.invalidConfig("メルの数が processor_config.json と config.json で違う")
        }
        var weights = try loadArrays(url: directory.appendingPathComponent("model.safetensors"))
        encoder = try GraniteSpeechEncoder(weights: &weights, config: config, dtype: dtype)
    }

    /// Hugging Face から取ってきて読み込む。offlineMode が true なら、キャッシュにあるファイルだけで読み込む（ネットワークに出ない）。
    /// 置き場所は speech-swift のほかのモデルと同じ ~/Library/Caches/qwen3-speech/models/<repo>。
    static func fromPretrained(modelId: String = defaultModelId, offlineMode: Bool,
                               progress: @escaping @Sendable (Double) -> Void) async throws -> GraniteSpeechCTCModel {
        let directory = try HuggingFaceDownloader.getCacheDirectory(for: modelId)
        // ダウンロードを 9 割、読み込みを残りの 1 割として知らせる
        try await HuggingFaceDownloader.downloadFiles(
            modelId: modelId, to: directory, files: files, offlineMode: offlineMode
        ) { progress(min($0, 1) * 0.9) }
        let model = try GraniteSpeechCTCModel(directory: directory)
        progress(1)
        return model
    }

    var inputSampleRate: Int { featureExtractor.config.samplingRate }

    /// 書き起こす。失敗したらエラーを投げる。sampleRate が 16 kHz でなければリサンプルする。
    func transcribeAudio(_ audio: [Float], sampleRate: Int) throws -> String {
        guard let encoder else { throw GraniteSpeechError.notLoaded }
        let rate = inputSampleRate
        let samples = sampleRate == rate ? audio : AudioFileLoader.resample(audio, from: sampleRate, to: rate)
        let features = featureExtractor(samples)
        // 間引いた後に 1 フレームも残らないほど短い音声（70 ms 未満）は、何も書き起こさない
        guard features.frames >= encoder.minimumFrames else { return "" }
        let input = MLXArray(features.values, [features.frames, featureExtractor.config.featureSize])
        return tokenizer.decodeCTC(encoder.greedyIds(input))
    }

    /// SpeechRecognitionModel の形。失敗は空の文字列にする。言語は渡さなくても自分で判断する。
    func transcribe(audio: [Float], sampleRate: Int, language: String?) -> String {
        (try? transcribeAudio(audio, sampleRate: sampleRate)) ?? ""
    }

    /// 16 kHz の音声から、CTC の頭の出力（frames × 語彙の数）を返す。参照の実装と比べるときに使う。
    func logits(_ audio: [Float]) throws -> (values: [Float], frames: Int) {
        guard let encoder else { throw GraniteSpeechError.notLoaded }
        let features = featureExtractor(audio)
        guard features.frames >= encoder.minimumFrames else { return ([], 0) }
        let input = MLXArray(features.values, [features.frames, featureExtractor.config.featureSize])
        let out = encoder.logits(input).asType(.float32)
        eval(out)
        return (out.asArray(Float.self), out.dim(0))
    }

    // MARK: - ModelMemoryManageable

    var isLoaded: Bool { encoder != nil }

    /// 重みを手放す。もう一度使うときは fromPretrained で読み込み直す。
    func unload() {
        guard encoder != nil else { return }
        encoder = nil
        Memory.clearCache()
    }

    var memoryFootprint: Int { encoder?.parameterBytes ?? 0 }
}
