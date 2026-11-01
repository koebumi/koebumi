// IBM Granite Speech 5.0 TurboCTC のエンコーダー（Conformer）と CTC の頭を MLX で動かす。
// transformers（Apache License 2.0）の modeling_granite_speech5.py を Swift に移した。
// Copyright 2026 IBM and The HuggingFace Team. Licensed under the Apache License, Version 2.0.

import Foundation
import MLX

/// 重みのファイル（model.safetensors）から作った、推論だけに使うエンコーダー。
/// 16 層の Conformer。層 0 と 1 で時間を 2 で割り（20 ms → 80 ms ごと）、真ん中の層の後で CTC の事後確率を足し戻す（self-conditioned CTC）。
final class GraniteSpeechEncoder {
    let config: GraniteSpeechConfig
    /// 行列の計算に使う型。重みもこの型で持つ
    let dtype: DType

    private let inputWeight: MLXArray
    private let inputBias: MLXArray
    private let layers: [Layer]
    /// CTC の頭（ctc_head は encoder.out と重みを共有する）
    private let outWeight: MLXArray
    private let outBias: MLXArray
    /// 真ん中の層の事後確率を、隠れ状態に戻す
    private let outMidWeight: MLXArray
    private let outMidBias: MLXArray
    /// ブロックの中の位置 i と j の相対距離を、埋め込みの表の行に直したもの（context × context）
    private let attentionDists: MLXArray

    /// 重みの合計のバイト数
    let parameterBytes: Int

    /// weights は safetensors のキー（"encoder.layers.0.self_attn.q_proj.weight" など）で引く。
    /// 使った重みは weights から外す（層ごとに型を変えたら元の配列を手放し、読み込みのときのメモリを 2 倍にしない）。
    init(weights: inout [String: MLXArray], config: GraniteSpeechConfig, dtype: DType = .float16) throws {
        self.config = config
        self.dtype = dtype
        func get(_ key: String) throws -> MLXArray {
            guard let w = weights.removeValue(forKey: "encoder." + key) else { throw GraniteSpeechError.missingWeight("encoder." + key) }
            return w
        }
        func cast(_ key: String) throws -> MLXArray { try get(key).asType(dtype) }

        inputWeight = try cast("input_linear.weight")
        inputBias = try cast("input_linear.bias")
        outWeight = try cast("out.weight")
        outBias = try cast("out.bias")
        outMidWeight = try cast("out_mid.weight")
        outMidBias = try cast("out_mid.bias")
        guard inputWeight.shape == [config.hiddenSize, config.numMelBins * 4],
              outWeight.shape == [config.vocabSize, config.hiddenSize] else {
            throw GraniteSpeechError.invalidConfig("重みの形が config.json と合わない")
        }

        var layers: [Layer] = []
        for i in 0..<config.numHiddenLayers {
            let p = "layers.\(i)."
            func linear(_ name: String, bias: Bool = true) throws -> Linear {
                Linear(weight: try cast(p + name + ".weight"), bias: bias ? try cast(p + name + ".bias") : nil)
            }
            func norm(_ name: String) throws -> Norm {
                Norm(weight: try cast(p + name + ".weight"), bias: try cast(p + name + ".bias"))
            }
            // BatchNorm（推論のときは決まった拡大と平行移動）は、前の depthwise の畳み込みの重みに 32 bit のまま畳み込む。
            // 重みの形は PyTorch の (出力, 1, カーネル) から MLX の (出力, カーネル, 1) に変える
            let gamma = try get(p + "conv.norm.weight").asType(.float32)
            let beta = try get(p + "conv.norm.bias").asType(.float32)
            let mean = try get(p + "conv.norm.running_mean").asType(.float32)
            let variance = try get(p + "conv.norm.running_var").asType(.float32)
            let scale = gamma * rsqrt(variance + 1e-5)
            let depthwise = try get(p + "conv.depthwise_conv.weight").asType(.float32)
                * scale.reshaped(-1, 1, 1)
            let layer = Layer(
                subsamples: config.subsampleLayers.contains(i),
                feedForward1: FeedForward(linear1: try linear("feed_forward1.linear1"), linear2: try linear("feed_forward1.linear2")),
                feedForward2: FeedForward(linear1: try linear("feed_forward2.linear1"), linear2: try linear("feed_forward2.linear2")),
                normFeedForward1: try norm("norm_feed_forward1"),
                normSelfAttention: try norm("norm_self_att"),
                normConv: try norm("norm_conv"),
                normFeedForward2: try norm("norm_feed_forward2"),
                normOut: try norm("norm_out"),
                query: try linear("self_attn.q_proj", bias: false),
                key: try linear("self_attn.k_proj", bias: false),
                value: try linear("self_attn.v_proj", bias: false),
                output: try linear("self_attn.o_proj"),
                relativePositions: try cast(p + "self_attn.rel_pos_emb.weight"),
                pointwise1: try linear("conv.pointwise_lin1"),
                depthwise: depthwise.transposed(0, 2, 1),
                depthwiseShift: beta - mean * scale,
                pointwise2: try linear("conv.pointwise_lin2")
            )
            eval(layer.arrays)
            layers.append(layer)
        }
        self.layers = layers

        // clamp(i - j, -context, context) + max_position_embeddings（compute_attention_dists と同じ）
        let c = config.contextSize
        var dists = [Int32](repeating: 0, count: c * c)
        for i in 0..<c {
            for j in 0..<c {
                dists[i * c + j] = Int32(min(max(i - j, -c), c) + config.maxPositionEmbeddings)
            }
        }
        attentionDists = MLXArray(dists, [c, c])

        // 入力と CTC の頭の重みも読み込みを済ませ、元の bf16 の配列を手放す
        var arrays = [inputWeight, inputBias, outWeight, outBias, outMidWeight, outMidBias, attentionDists]
        for layer in layers { arrays += layer.arrays }
        eval(arrays)
        parameterBytes = arrays.reduce(0) { $0 + $1.nbytes }
    }

    /// 特徴量（frames × 320）から、CTC の頭の出力（約 frames / 4 × 語彙の数）を作る。
    /// 2 回の間引きで 1 フレームも残らない長さ（frames < 4）は渡さない。
    func logits(_ features: MLXArray) -> MLXArray {
        var hidden = Linear(weight: inputWeight, bias: inputBias)(features.asType(dtype))
        for (index, layer) in layers.enumerated() {
            hidden = layer(hidden, dists: attentionDists, config: config)
            if index + 1 == config.numHiddenLayers / 2 {
                // self-conditioned CTC: 真ん中の層の CTC の事後確率を、隠れ状態に足し戻す
                let midLogits = addMM(outBias, hidden, outWeight.T)
                let posteriors = softmax(midLogits, axis: -1, precise: true)
                hidden = hidden + addMM(outMidBias, posteriors, outMidWeight.T)
            }
        }
        return addMM(outBias, hidden, outWeight.T)
    }

    /// フレームごとに、いちばん確率の高いトークンの id
    func greedyIds(_ features: MLXArray) -> [Int] {
        let ids = argMax(logits(features), axis: -1).asType(.int32)
        eval(ids)
        return ids.asArray(Int32.self).map(Int.init)
    }

    /// 2 回の間引きの後に 1 フレーム以上残るのに要る、特徴量のフレームの数
    var minimumFrames: Int { 1 << config.subsampleLayers.count }
}

// MARK: - 層

extension GraniteSpeechEncoder {
    struct Linear {
        let weight: MLXArray
        let bias: MLXArray?

        func callAsFunction(_ x: MLXArray) -> MLXArray {
            if let bias { return addMM(bias, x, weight.T) }
            return matmul(x, weight.T)
        }
    }

    struct Norm {
        let weight: MLXArray
        let bias: MLXArray

        func callAsFunction(_ x: MLXArray) -> MLXArray {
            layerNorm(x, weight: weight, bias: bias, eps: 1e-5)
        }
    }

    struct FeedForward {
        let linear1: Linear
        let linear2: Linear

        func callAsFunction(_ x: MLXArray) -> MLXArray {
            let h = linear1(x)
            return linear2(h * sigmoid(h))
        }
    }

    /// Conformer の 1 層。隠れ状態は (frames, hidden) の 2 次元で持つ（音声は 1 つずつ認識する）。
    struct Layer {
        let subsamples: Bool
        let feedForward1: FeedForward
        let feedForward2: FeedForward
        let normFeedForward1: Norm
        let normSelfAttention: Norm
        let normConv: Norm
        let normFeedForward2: Norm
        let normOut: Norm
        let query: Linear
        let key: Linear
        let value: Linear
        let output: Linear
        /// Shaw の相対位置の埋め込み（2 × max_position_embeddings + 1, head_dim）
        let relativePositions: MLXArray
        let pointwise1: Linear
        /// BatchNorm を畳み込んだ depthwise の重み（チャンネル, カーネル, 1）。32 bit
        let depthwise: MLXArray
        /// BatchNorm の平行移動。32 bit
        let depthwiseShift: MLXArray
        let pointwise2: Linear

        var arrays: [MLXArray] {
            var out = [relativePositions, depthwise, depthwiseShift]
            for linear in [feedForward1.linear1, feedForward1.linear2, feedForward2.linear1, feedForward2.linear2,
                           query, key, value, output, pointwise1, pointwise2] {
                out.append(linear.weight)
                if let bias = linear.bias { out.append(bias) }
            }
            for norm in [normFeedForward1, normSelfAttention, normConv, normFeedForward2, normOut] {
                out += [norm.weight, norm.bias]
            }
            return out
        }

        func callAsFunction(_ input: MLXArray, dists: MLXArray, config: GraniteSpeechConfig) -> MLXArray {
            // Conformer は前後の FFN に 0.5 を掛ける
            var hidden = input + 0.5 * feedForward1(normFeedForward1(input))
            hidden = hidden + attention(normSelfAttention(hidden), dists: dists, config: config)
            let conv = convolution(normConv(hidden), stride: subsamples ? 2 : 1, config: config)
            if subsamples {
                // 残差は 2 フレームずつの平均にする（奇数なら最後のフレームを捨てる）
                let half = hidden.dim(0) / 2
                let pooled = hidden[..<(2 * half)].reshaped(half, 2, hidden.dim(1)).mean(axis: 1)
                hidden = pooled + conv[..<half]
            } else {
                hidden = hidden + conv
            }
            hidden = hidden + 0.5 * feedForward2(normFeedForward2(hidden))
            return normOut(hidden)
        }

        /// ブロック単位のアテンション。context_size フレームずつに区切り、ブロックの中だけを見る。
        /// 位置の情報は、クエリとブロックの中の相対距離の埋め込みの内積を、アテンションのバイアスとして足す。
        func attention(_ x: MLXArray, dists: MLXArray, config: GraniteSpeechConfig) -> MLXArray {
            let frames = x.dim(0)
            let c = config.contextSize
            let heads = config.numAttentionHeads
            let headDim = config.headDim
            let scale = 1 / Float(headDim).squareRoot()
            // 終わりを 0 で埋めてブロックの数を整数にする
            let padding = (c - frames % c) % c
            let padded = padding > 0 ? MLX.padded(x, widths: [IntOrPair((0, padding)), IntOrPair((0, 0))]) : x
            let blocks = (frames + padding) / c

            func split(_ y: MLXArray) -> MLXArray {
                y.reshaped(blocks, c, heads, headDim).transposed(0, 2, 1, 3)
            }
            let q = split(query(padded))
            let k = split(key(padded))
            let v = split(value(padded))

            // bias[b, h, i, j] = q[b, h, i] · E[dist(i, j)] × scale
            let relative = take(relativePositions, dists, axis: 0) * scale  // (c, c, headDim)
            let queries = q.transposed(2, 0, 1, 3).reshaped(c, blocks * heads, headDim)
            var bias = matmul(queries, relative.transposed(0, 2, 1))  // (c, blocks × heads, c)
            bias = bias.reshaped(c, blocks, heads, c).transposed(1, 2, 0, 3)
            if padding > 0 {
                // 埋めたフレームはキーとして見ない。最後のブロックの終わりの列だけを大きく下げる
                var mask = [Float](repeating: 0, count: blocks * c)
                for j in (c - padding)..<c { mask[(blocks - 1) * c + j] = -30000 }
                bias = bias + MLXArray(mask, [blocks, 1, 1, c]).asType(bias.dtype)
            }

            let attended = scaledDotProductAttention(queries: q, keys: k, values: v, scale: scale, mask: bias)
            let merged = attended.transposed(0, 2, 1, 3).reshaped(blocks * c, heads * headDim)
            return output(padding > 0 ? merged[..<frames] : merged)
        }

        /// Conformer の畳み込み。GLU → depthwise（stride が 2 なら時間を半分に）→ BatchNorm → SiLU → 1×1
        func convolution(_ x: MLXArray, stride: Int, config: GraniteSpeechConfig) -> MLXArray {
            let h = pointwise1(x)
            let inner = h.dim(1) / 2
            let gated = h[0..., ..<inner] * sigmoid(h[0..., inner...])
            // depthwise と BatchNorm は 32 bit で計算する（transformers も conv.norm を 32 bit のまま持つ）
            var y = conv1d(gated.asType(.float32).expandedDimensions(axis: 0), depthwise,
                           stride: stride, padding: (config.convKernelSize - 1) / 2, groups: inner)
            y = y.squeezed(axis: 0) + depthwiseShift
            y = y * sigmoid(y)
            return pointwise2(y.asType(x.dtype))
        }
    }
}
