import AudioCommon
import Foundation
import MLX
import Testing
@testable import Koebumi

@Suite struct GraniteSpeechFeatureTests {
    /// 参照の値を作った信号（transformers の GraniteSpeech5FeatureExtractor に同じ信号を渡した）
    static func signal(_ count: Int) -> [Float] {
        (0..<count).map { i in
            let t = Double(i)
            let a = 0.5 * sin(2 * Double.pi * 440 * t / 16000)
            let b = 0.3 * sin(2 * Double.pi * 1234 * t / 16000 + 0.5) * (t / Double(count))
            let c = 0.05 * pow(sin(2 * Double.pi * 3100 * t / 16000), 3)
            return Float(a + b + c)
        }
    }

    @Test func featureShapeFollowsTheTransformersExtractor() {
        let extractor = GraniteSpeechFeatureExtractor()
        // 1 秒は 100 フレーム（10 ms ごと）で、2 フレームずつまとめて 50
        #expect(extractor(Self.signal(16000)).frames == 50)
        // 半端なフレームは捨てずに、音声を 0 で伸ばして 2 つ目を埋める（123 → 124 → 62）
        let output = extractor(Self.signal(19744))
        #expect(output.frames == 62)
        #expect(output.values.count == 62 * 320)
        #expect(extractor(Self.signal(1120)).frames == 4)
        #expect(extractor(Self.signal(300)).frames == 1)
        // 1 フレーム（160 サンプル）に満たない音声は何も作らない
        #expect(extractor(Self.signal(159)).frames == 0)
        #expect(extractor([]).frames == 0)
    }

    @Test func featureValuesMatchTheTransformersExtractor() {
        let f = GraniteSpeechFeatureExtractor()(Self.signal(19744)).values
        func row(_ frame: Int, _ start: Int) -> [Float] { Array(f[(frame * 320 + start)..<(frame * 320 + start + 4)]) }
        func close(_ a: [Float], _ b: [Float]) -> Bool { zip(a, b).allSatisfy { abs($0 - $1) < 1e-4 } }
        // 最初のフレームの log-mel
        #expect(close(row(0, 0), [1.3300739526748657, 1.3404340744018555, 1.3562140464782715, 1.3890855312347412]))
        // 2 つ目の 10 ms の log-mel（まとめた後の後ろ半分の頭）
        #expect(close(row(10, 160), [-0.0003323554992675781, 0.0725981593132019, 0.14434361457824707, 0.18960005044937134]))
        // delta
        #expect(close(row(30, 80), [0.0003274083137512207, 0.00028899312019348145, 0.000269085168838501, 0.00020590424537658691]))
        // 0 で伸ばした最後のフレームの delta
        #expect(close(row(61, 316), [0.13547879457473755, 0.17106449604034424, 0.15825682878494263, 0.20482581853866577]))
        let sum = f.reduce(0.0) { $0 + Double($1) }
        #expect(abs(sum - 2990.0921482145786) < 0.05)
    }

    @Test func reflectPaddingDoesNotRepeatTheEdge() {
        // torch の reflect: [a b c d] を左に 2 つ伸ばすと [c b a b c d]
        #expect((-2...5).map { GraniteSpeechFeatureExtractor.reflect($0, count: 4) } == [2, 1, 0, 1, 2, 3, 2, 1])
    }

    @Test func deltasUseReplicatedEdges() {
        // 1 つのビンで 0, 1, 4, 9 と増える値。端は同じ値で伸ばして (x[t+1] - x[t-1]) / 2
        let d = GraniteSpeechFeatureExtractor.deltas([0, 1, 4, 9], frames: 4, bins: 1, winLength: 3)
        #expect(d == [0.5, 2, 4, 2.5])
    }

    @Test func configsAreReadFromTheCheckpointFiles() throws {
        let config = try GraniteSpeechConfig(json: Data("""
        {"encoder_config": {"context_size": 128, "head_dim": 128, "hidden_act": "silu", "hidden_size": 1024,
         "num_attention_heads": 8, "num_hidden_layers": 16, "num_key_value_heads": 8, "subsample_layers": [0, 1],
         "vocab_size": 16384}, "pad_token_id": 0, "vocab_size": 16384}
        """.utf8))
        #expect(config == GraniteSpeechConfig())
        let features = try GraniteSpeechFeatureConfig(json: Data("""
        {"feature_extractor": {"delta_win_length": 3, "feature_size": 320, "hop_length": 160, "logmel_floor_db": 8.0,
         "n_fft": 512, "num_mel_bins": 80, "sampling_rate": 16000, "win_length": 400}}
        """.utf8))
        #expect(features == GraniteSpeechFeatureConfig())
        #expect(throws: GraniteSpeechError.self) {
            try GraniteSpeechConfig(json: Data(#"{"encoder_config": {"hidden_act": "gelu"}}"#.utf8))
        }
    }
}

@Suite struct GraniteSpeechDecodingTests {
    static let tokenizer = GraniteSpeechTokenizer(
        pieces: ["<unk>", "<|nospeech|>", "<|ja|>", "▁Hello", "▁world", "<0xE3>", "<0x81>", "<0x82>", "。", "<0xFF>", "▁", "明日"],
        specialIds: [0, 1, 2], blankId: 0)

    @Test func ctcMergesRepeatsBeforeDroppingBlanks() {
        // 続く同じ id は 1 つ。ブランクを挟んだ同じ id は 2 つ残る
        #expect(GraniteSpeechTokenizer.collapse([0, 3, 3, 0, 3, 4, 4, 4, 0, 0], blankId: 0) == [3, 3, 4])
        #expect(GraniteSpeechTokenizer.collapse([0, 0, 0], blankId: 0) == [])
        #expect(GraniteSpeechTokenizer.collapse([], blankId: 0) == [])
    }

    @Test func tokensBecomeTextLikeTheHuggingFaceDecoder() {
        let t = Self.tokenizer
        // ▁ は空白にし、先頭の空白を 1 つだけ削る
        #expect(t.decodeCTC([0, 3, 3, 0, 4, 0]) == "Hello world")
        // 特殊なトークン（言語の印など）は書き出さない
        #expect(t.decodeCTC([2, 2, 11, 8, 1]) == "明日。")
        // 続くバイトのトークンは UTF-8 としてまとめる（E3 81 82 = あ）
        #expect(t.decodeCTC([5, 6, 0, 7, 8]) == "あ。")
        // UTF-8 として読めないバイトは � にする
        #expect(t.decode([9, 8]) == "\u{FFFD}。")
        #expect(t.decode([10, 3]) == " Hello")
    }

    @Test func tokenizerFilesGiveTheBlankAndSpecialTokens() throws {
        let json = Data("""
        {"added_tokens": [{"id": 0, "content": "<unk>", "special": true}, {"id": 1, "content": "<|nospeech|>", "special": true}],
         "model": {"type": "BPE", "vocab": {"<unk>": 0, "<|nospeech|>": 1, "▁a": 2, "b": 3}}}
        """.utf8)
        let t = try GraniteSpeechTokenizer(tokenizerJSON: json, tokenizerConfigJSON: Data(#"{"pad_token": "<unk>"}"#.utf8), fallbackBlankId: 5)
        #expect(t.blankId == 0)
        #expect(t.specialIds == [0, 1])
        #expect(t.decodeCTC([1, 2, 2, 0, 3]) == "ab")
    }
}

/// swift test では、MLX が Metal のシェーダー（metallib）を見つけられない（MLX は実行ファイルの隣やアプリのバンドルを探す）。
/// MLX が最後に探す、今のディレクトリの default.metallib を使う。SwiftPM がテストのバンドルに入れたシェーダーのディレクトリに移って
/// MLX に Metal を準備させてから、元のディレクトリに戻る。見つからなければ MLX を使うテストは動かさない（MLX はシェーダーがないとプロセスごと止める）。
enum MLXTestSupport {
    static let isReady: Bool = {
        var info = Dl_info()
        guard dladdr(#dsohandle, &info) != 0, let name = info.dli_fname else { return false }
        // KoebumiTests.xctest/Contents/MacOS/KoebumiTests
        let contents = URL(fileURLWithPath: String(cString: name)).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent()
        let shaders = "mlx-swift_Cmlx.bundle/Contents/Resources"
        let fm = FileManager.default
        // テストのバンドルの中と、その隣（.build/debug）
        let candidates = [contents.appendingPathComponent("Resources/" + shaders),
                          contents.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(shaders)]
        guard let directory = candidates.first(where: { fm.fileExists(atPath: $0.appendingPathComponent("default.metallib").path) }) else {
            return false
        }
        let previous = fm.currentDirectoryPath
        guard fm.changeCurrentDirectoryPath(directory.path) else { return false }
        defer { fm.changeCurrentDirectoryPath(previous) }
        // 初めて配列を作るときに、Metal の準備とシェーダーの読み込みをする
        eval(MLXArray(Float(1)) + 1)
        return true
    }()
}

@Suite(.enabled(if: MLXTestSupport.isReady)) struct GraniteSpeechEncoderTests {
    /// 小さな形で、乱数の重みを作る
    static func tinyEncoder(context: Int = 4, maxPositions: Int = 6) throws -> GraniteSpeechEncoder {
        var config = GraniteSpeechConfig()
        config.hiddenSize = 8
        config.intermediateSize = 16
        config.numHiddenLayers = 4
        config.numAttentionHeads = 2
        config.headDim = 4
        config.numMelBins = 2
        config.maxPositionEmbeddings = maxPositions
        config.contextSize = context
        config.vocabSize = 12
        let h = config.hiddenSize, inner = h * config.convExpansionFactor
        // テストは並んで動くので、乱数の状態を共有しないよう鍵を渡す
        var draws: UInt64 = 0
        func r(_ shape: [Int]) -> MLXArray {
            draws += 1
            return MLXRandom.normal(shape, key: MLXRandom.key(draws)) * 0.3
        }
        var w: [String: MLXArray] = [
            "encoder.input_linear.weight": r([h, config.numMelBins * 4]), "encoder.input_linear.bias": r([h]),
            "encoder.out.weight": r([config.vocabSize, h]), "encoder.out.bias": r([config.vocabSize]),
            "encoder.out_mid.weight": r([h, config.vocabSize]), "encoder.out_mid.bias": r([h]),
        ]
        for i in 0..<config.numHiddenLayers {
            let p = "encoder.layers.\(i)."
            for ff in ["feed_forward1", "feed_forward2"] {
                w[p + ff + ".linear1.weight"] = r([config.intermediateSize, h])
                w[p + ff + ".linear1.bias"] = r([config.intermediateSize])
                w[p + ff + ".linear2.weight"] = r([h, config.intermediateSize])
                w[p + ff + ".linear2.bias"] = r([h])
            }
            for norm in ["norm_feed_forward1", "norm_self_att", "norm_conv", "norm_feed_forward2", "norm_out"] {
                w[p + norm + ".weight"] = 1 + r([h])
                w[p + norm + ".bias"] = r([h])
            }
            for proj in ["q_proj", "k_proj", "v_proj", "o_proj"] { w[p + "self_attn." + proj + ".weight"] = r([h, h]) }
            w[p + "self_attn.o_proj.bias"] = r([h])
            w[p + "self_attn.rel_pos_emb.weight"] = r([2 * config.maxPositionEmbeddings + 1, config.headDim])
            w[p + "conv.pointwise_lin1.weight"] = r([inner * 2, h])
            w[p + "conv.pointwise_lin1.bias"] = r([inner * 2])
            w[p + "conv.depthwise_conv.weight"] = r([inner, 1, config.convKernelSize])
            w[p + "conv.norm.weight"] = 1 + r([inner])
            w[p + "conv.norm.bias"] = r([inner])
            w[p + "conv.norm.running_mean"] = r([inner])
            w[p + "conv.norm.running_var"] = 1 + abs(r([inner]))
            w[p + "conv.pointwise_lin2.weight"] = r([h, inner])
            w[p + "conv.pointwise_lin2.bias"] = r([h])
        }
        return try GraniteSpeechEncoder(weights: &w, config: config, dtype: .float32)
    }

    @Test func outputIsQuarterLengthForAnyInputLength() throws {
        let encoder = try Self.tinyEncoder()
        // ブロック（4 フレーム）で割り切れない長さも、埋めて動く。2 回の間引きで 4 分の 1（端数は切り捨て）
        for frames in [4, 5, 7, 9, 16, 33] {
            let features = MLXRandom.normal([frames, 8], key: MLXRandom.key(100))
            #expect(encoder.logits(features).shape == [frames / 4, 12])
            #expect(encoder.greedyIds(features).count == frames / 4)
        }
    }

    @Test func paddedFramesDoNotLeakIntoAttention() throws {
        // 24 フレームが 1 つのブロックに収まる長さの文脈なら、埋めたフレームをキーとして見ない限り、文脈の長さで結果は変わらない。
        // 文脈 24 は層 0 で埋めず、32 と 64 は毎層埋める。重みは同じ乱数の種で同じものを作る
        let features = MLXRandom.normal([24, 8], key: MLXRandom.key(200))
        let exact = try Self.tinyEncoder(context: 24, maxPositions: 64).logits(features)
        for context in [32, 64] {
            let padded = try Self.tinyEncoder(context: context, maxPositions: 64).logits(features)
            #expect(padded.shape == [6, 12])
            #expect(allClose(padded, exact, rtol: 1e-4, atol: 1e-4).item(Bool.self))
        }
    }
}

/// 本物の重みで書き起こす。KOEBUMI_E2E_GRANITE=1 のときだけ動かす（初めてなら約 0.95 GB をダウンロードする）。
@Suite(.enabled(if: ProcessInfo.processInfo.environment["KOEBUMI_E2E_GRANITE"] == "1"), .serialized)
struct GraniteSpeechE2ETests {
    init() throws {
        try #require(MLXTestSupport.isReady, "MLX の metallib が見つからない")
    }

    /// say で読み上げた音声（16 kHz）
    static func speech(_ text: String, voice: String) throws -> [Float] {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("granite-\(UUID().uuidString).aiff")
        defer { try? FileManager.default.removeItem(at: url) }
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-v", voice, "-o", url.path, text]
        try say.run()
        say.waitUntilExit()
        return try AudioFileLoader.load(url: url, targetSampleRate: 16000)
    }

    /// 文字の編集距離 / 正解の長さ。句読点と空白は数えない
    static func cer(_ hypothesis: String, _ reference: String) -> Double {
        func clean(_ s: String) -> [Character] {
            Array(s.lowercased().filter { !$0.isPunctuation && !$0.isWhitespace && !"、。，．".contains($0) })
        }
        let h = clean(hypothesis), r = clean(reference)
        var row = Array(0...h.count)
        for (i, rc) in r.enumerated() {
            var next = [i + 1]
            for (j, hc) in h.enumerated() {
                next.append(min(row[j] + (rc == hc ? 0 : 1), row[j + 1] + 1, next[j] + 1))
            }
            row = next
        }
        return Double(row[h.count]) / Double(max(r.count, 1))
    }

    static let japanese = "明日の会議は午後三時から第二会議室で行います。"
    static let english = "The quick brown fox jumps over the lazy dog near the river bank."

    @Test func downloadsLoadsAndTranscribesJapaneseAndEnglish() async throws {
        let model = try await GraniteSpeechCTCModel.fromPretrained(offlineMode: false) { _ in }
        #expect(model.isLoaded)
        #expect(model.memoryFootprint > 900_000_000)

        let ja = try model.transcribeAudio(try Self.speech(Self.japanese, voice: "Kyoko"), sampleRate: 16000)
        print("Granite ja: \(ja)")
        #expect(Self.cer(ja, Self.japanese) < 0.15)

        // 16 kHz でない音声はリサンプルする
        let en48k = AudioFileLoader.resample(try Self.speech(Self.english, voice: "Samantha"), from: 16000, to: 48000)
        let en = try model.transcribeAudio(en48k, sampleRate: 48000)
        print("Granite en: \(en)")
        #expect(Self.cer(en, Self.english) < 0.1)

        // 短すぎる音声は空
        #expect(try model.transcribeAudio([Float](repeating: 0, count: 500), sampleRate: 16000) == "")

        model.unload()
        #expect(!model.isLoaded)
        #expect(model.transcribe(audio: [Float](repeating: 0, count: 16000), sampleRate: 16000, language: nil) == "")
        #expect(throws: GraniteSpeechError.notLoaded) { try model.transcribeAudio([], sampleRate: 16000) }

        // ダウンロードした後は、ネットワークに出ずに読み込める
        let offline = try await GraniteSpeechCTCModel.fromPretrained(offlineMode: true) { _ in }
        #expect(offline.isLoaded)
    }

    @Test func longRecordingIsTranscribedInOnePass() async throws {
        let model = try await GraniteSpeechCTCModel.fromPretrained(offlineMode: true) { _ in }
        let sentence = try Self.speech(Self.japanese, voice: "Kyoko")
        let pause = [Float](repeating: 0, count: 8000)
        // 約 10 秒（同じ文を 2 回と少し）
        var ten: [Float] = []
        while ten.count < 160_000 { ten += sentence + pause }
        ten = Array(ten.prefix(160_000))
        _ = try model.transcribeAudio(Array(ten.prefix(32000)), sampleRate: 16000)  // シェーダーの準備
        Memory.peakMemory = 0
        var times: [Double] = []
        var text = ""
        for _ in 0..<3 {
            let start = Date()
            text = try model.transcribeAudio(ten, sampleRate: 16000)
            times.append(Date().timeIntervalSince(start))
        }
        print("Granite 10 s: \(times.map { String(format: "%.3f", $0) }) s, MLX peak \(Memory.peakMemory / 1_000_000) MB, \(text)")
        #expect(text.contains("会議"))

        // 約 3 分。ブロック単位のアテンションなので、そのまま 1 回で通る
        var long: [Float] = []
        while long.count < 16000 * 180 { long += sentence + pause }
        Memory.peakMemory = 0
        let start = Date()
        let longText = try model.transcribeAudio(long, sampleRate: 16000)
        let elapsed = Date().timeIntervalSince(start)
        let repeats = long.count / (sentence.count + pause.count)
        let found = longText.components(separatedBy: "会議室").count - 1
        print("Granite \(long.count / 16000) s: \(String(format: "%.3f", elapsed)) s, MLX peak \(Memory.peakMemory / 1_000_000) MB, 会議室 \(found)/\(repeats)")
        #expect(found >= repeats - 1)
    }
}
