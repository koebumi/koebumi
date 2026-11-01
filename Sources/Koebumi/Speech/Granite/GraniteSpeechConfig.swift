// IBM Granite Speech 5.0 TurboCTC を MLX で動かす。
// transformers（Apache License 2.0）の src/transformers/models/granite_speech5/ を Swift に移した。
// 元: https://github.com/huggingface/transformers/tree/674c0e396a06aa9d96cdc4741ce9c0853eae64b8/src/transformers/models/granite_speech5
// Copyright 2026 IBM and The HuggingFace Team. Licensed under the Apache License, Version 2.0.

import Foundation

/// 読み込みや認識の失敗
enum GraniteSpeechError: LocalizedError, Equatable {
    case notLoaded
    case invalidConfig(String)
    case missingWeight(String)
    case invalidTokenizer(String)

    var errorDescription: String? {
        switch self {
        case .notLoaded: return "Granite Speech のモデルを読み込んでいません"
        case .invalidConfig(let detail): return "Granite Speech の設定ファイルを読めません: \(detail)"
        case .missingWeight(let name): return "Granite Speech の重みがありません: \(name)"
        case .invalidTokenizer(let detail): return "Granite Speech のトークナイザーを読めません: \(detail)"
        }
    }
}

/// エンコーダーの設定（config.json の encoder_config と、CTC の頭の設定）。既定の値は configuration_granite_speech5.py と同じ。
struct GraniteSpeechConfig: Equatable {
    var hiddenSize = 1024
    var intermediateSize = 4096
    var numHiddenLayers = 16
    var numAttentionHeads = 8
    var headDim = 128
    var numMelBins = 80
    /// 相対位置の埋め込みの表は 2 × これ + 1 行
    var maxPositionEmbeddings = 512
    /// アテンションを区切るブロックの長さ（フレーム）
    var contextSize = 128
    var convKernelSize = 7
    var convExpansionFactor = 2
    /// 時間を 2 で割る層
    var subsampleLayers = [0, 1]
    var vocabSize = 16384
    /// CTC のブランク（パディングのトークン）
    var padTokenId = 0

    init() {}

    /// config.json を読む。書いていない値は既定の値を使う。
    init(json data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GraniteSpeechError.invalidConfig("config.json が JSON のオブジェクトではない")
        }
        let encoder = root["encoder_config"] as? [String: Any] ?? [:]
        func int(_ key: String, _ fallback: Int) -> Int { (encoder[key] as? NSNumber)?.intValue ?? fallback }
        hiddenSize = int("hidden_size", hiddenSize)
        intermediateSize = int("intermediate_size", intermediateSize)
        numHiddenLayers = int("num_hidden_layers", numHiddenLayers)
        numAttentionHeads = int("num_attention_heads", numAttentionHeads)
        headDim = int("head_dim", hiddenSize / numAttentionHeads)
        numMelBins = int("num_mel_bins", numMelBins)
        maxPositionEmbeddings = int("max_position_embeddings", maxPositionEmbeddings)
        contextSize = int("context_size", contextSize)
        convKernelSize = int("conv_kernel_size", convKernelSize)
        convExpansionFactor = int("conv_expansion_factor", convExpansionFactor)
        subsampleLayers = (encoder["subsample_layers"] as? [NSNumber])?.map(\.intValue) ?? subsampleLayers
        vocabSize = int("vocab_size", vocabSize)
        padTokenId = (root["pad_token_id"] as? NSNumber)?.intValue ?? padTokenId

        // この移植が前提にしている形と違えば、読み込まずに止める
        if let act = encoder["hidden_act"] as? String, act != "silu" {
            throw GraniteSpeechError.invalidConfig("hidden_act が \(act)（silu だけに対応）")
        }
        if let kv = (encoder["num_key_value_heads"] as? NSNumber)?.intValue, kv != numAttentionHeads {
            throw GraniteSpeechError.invalidConfig("num_key_value_heads が \(kv)（ヘッドの数と同じものだけに対応）")
        }
        if let rootVocab = (root["vocab_size"] as? NSNumber)?.intValue, rootVocab != vocabSize {
            throw GraniteSpeechError.invalidConfig("vocab_size が CTC の頭とエンコーダーで違う")
        }
        guard contextSize > 0, contextSize <= maxPositionEmbeddings, convKernelSize % 2 == 1 else {
            throw GraniteSpeechError.invalidConfig("context_size か conv_kernel_size が正しくない")
        }
    }
}

/// 特徴量の設定（processor_config.json の feature_extractor）。既定の値は feature_extraction_granite_speech5.py と同じ。
struct GraniteSpeechFeatureConfig: Equatable {
    var numMelBins = 80
    var samplingRate = 16000
    var nFFT = 512
    var winLength = 400
    var hopLength = 160
    var deltaWinLength = 3
    /// 各音声のいちばん大きい値から、これだけ下（log10 の単位）で切り捨てる
    var logmelFloorDB: Float = 8

    /// フレームごとに、log-mel とその delta を並べる（× 2）
    static let deltaExpansion = 2
    /// 続く 2 フレームを 1 つにまとめる（× 2）
    static let frameStacking = 2

    /// エンコーダーの 1 フレームの次元（80 × 2 × 2 = 320）
    var featureSize: Int { numMelBins * Self.deltaExpansion * Self.frameStacking }

    init() {}

    init(json data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GraniteSpeechError.invalidConfig("processor_config.json が JSON のオブジェクトではない")
        }
        // processor_config.json は feature_extractor の下に、preprocessor_config.json はそのまま書く
        let fe = root["feature_extractor"] as? [String: Any] ?? root
        func int(_ key: String, _ fallback: Int) -> Int { (fe[key] as? NSNumber)?.intValue ?? fallback }
        numMelBins = int("num_mel_bins", numMelBins)
        samplingRate = int("sampling_rate", samplingRate)
        nFFT = int("n_fft", nFFT)
        winLength = int("win_length", winLength)
        hopLength = int("hop_length", hopLength)
        deltaWinLength = int("delta_win_length", deltaWinLength)
        logmelFloorDB = (fe["logmel_floor_db"] as? NSNumber)?.floatValue ?? logmelFloorDB
        // FFT は 2 のべき乗の長さだけに対応する
        guard nFFT > 0, nFFT & (nFFT - 1) == 0, winLength <= nFFT, hopLength > 0, deltaWinLength >= 3 else {
            throw GraniteSpeechError.invalidConfig("n_fft・win_length・hop_length・delta_win_length のどれかが正しくない")
        }
        if let size = (fe["feature_size"] as? NSNumber)?.intValue, size != featureSize {
            throw GraniteSpeechError.invalidConfig("feature_size が \(size)（\(featureSize) のはず）")
        }
    }
}
