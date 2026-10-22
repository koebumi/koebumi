import AppKit

/// 開始・確定・取り消し・エラーの効果音（設定でオフにできる）。
/// 音のファイルは持たず、初めて鳴らすときに SoundSynth で作る。開始・確定・取り消しは立ち上がりの丸い「やわらか」、
/// エラーは少しはっきりした「ガラス」の音（聞き比べた「Speak 効果音」のページと同じ計算）。
@MainActor
enum Sounds {
    static func start() { play(.start) }
    static func stop() { play(.stop) }
    static func cancel() { play(.cancel) }
    static func error() { play(.error) }

    /// 開始の音が聞こえなくなるまでの秒数。音を鳴らさない設定のときは 0
    static var startLength: TimeInterval {
        guard SettingsStore.shared.settings.interactionSounds else { return 0 }
        return made(.start)?.length ?? 0
    }

    enum Cue { case start, stop, cancel, error }

    private static var cache: [Cue: (sound: NSSound, length: TimeInterval)] = [:]

    private static func play(_ cue: Cue) {
        guard SettingsStore.shared.settings.interactionSounds, let sound = made(cue)?.sound else { return }
        // 鳴っている途中でもう一度鳴らすときは、頭から鳴らし直す
        sound.stop()
        sound.play()
    }

    private static func made(_ cue: Cue) -> (sound: NSSound, length: TimeInterval)? {
        if let cached = cache[cue] { return cached }
        let samples = SoundSynth.render(recipe(cue))
        guard let sound = NSSound(data: WAV.encode(RecordedAudio(samples: samples, sampleRate: SoundSynth.sampleRate))) else { return nil }
        let result = (sound, SoundSynth.audibleLength(samples))
        cache[cue] = result
        return result
    }

    static func recipe(_ cue: Cue) -> SoundSynth.Recipe {
        typealias Note = SoundSynth.Note
        // やわらか: 2 倍音を少しだけ足したサイン波。12 ミリ秒かけて立ち上げ、角を立てない
        let soft = [SoundSynth.Partial(ratio: 1, amp: 1, decay: 1), .init(ratio: 2, amp: 0.08, decay: 0.6)]
        // ガラスのエラー: 2・3 倍音を足した低い音
        let low = [SoundSynth.Partial(ratio: 1, amp: 1, decay: 1), .init(ratio: 2, amp: 0.3, decay: 0.6), .init(ratio: 3, amp: 0.1, decay: 0.4)]
        switch cue {
        case .start:  // レ → ラ（上がる）
            return .init(notes: [Note(frequency: 587.3, attack: 0.012, decay: 0.07, partials: soft),
                                 Note(time: 0.07, frequency: 880, attack: 0.012, decay: 0.1, partials: soft)])
        case .stop:  // ラ → レ（下がる）
            return .init(notes: [Note(frequency: 880, attack: 0.012, decay: 0.07, partials: soft),
                                 Note(time: 0.07, frequency: 587.3, attack: 0.012, decay: 0.14, partials: soft)])
        case .cancel:  // シ 1 音だけ、少し小さく
            return .init(notes: [Note(frequency: 493.9, attack: 0.012, decay: 0.08, partials: soft)], gain: 0.8)
        case .error:  // ミ → ド（低く下がる）
            return .init(notes: [Note(frequency: 329.6, attack: 0.004, decay: 0.11, partials: low),
                                 Note(time: 0.12, frequency: 261.6, attack: 0.004, decay: 0.2, partials: low)])
        }
    }
}

/// 効果音を作る。減衰するサイン波（と倍音）を重ね、macOS の効果音と同じくらいの大きさにそろえる。
enum SoundSynth {
    static let sampleRate = 48000.0

    /// 倍音。decay が 1 未満ほど、基音より早く消える
    struct Partial {
        var ratio: Double
        var amp: Double
        var decay: Double
    }

    struct Note {
        /// 鳴り始め（秒）
        var time = 0.0
        var frequency: Double
        /// 音程を動かすときの行き先と、行き着くまでの秒数
        var glideTo: Double?
        var glide = 0.0
        var amp = 1.0
        /// 立ち上がりの秒数と、そこから 1/e まで小さくなる秒数
        var attack = 0.002
        var decay: Double
        var partials = [Partial(ratio: 1, amp: 1, decay: 1)]
    }

    struct Recipe {
        var notes: [Note]
        /// ほかの音より小さくしたいときの倍率
        var gain = 1.0
    }

    static func render(_ recipe: Recipe) -> [Float] {
        let end = min(1.2, (recipe.notes.map { $0.time + $0.attack + $0.decay * 7 }.max() ?? 0) + 0.01)
        let count = Int((end * sampleRate).rounded(.up))
        var out = [Double](repeating: 0, count: count)
        for note in recipe.notes {
            let start = Int((note.time * sampleRate).rounded())
            guard start < count else { continue }
            var phase = 0.0
            for i in start..<count {
                let t = Double(i - start) / sampleRate
                let f = note.glideTo.map { note.frequency * pow($0 / note.frequency, min(1, t / note.glide)) } ?? note.frequency
                phase += 2 * .pi * f / sampleRate
                let env = t < note.attack ? t / note.attack : exp(-(t - note.attack) / note.decay)
                if t > note.attack && env < 1e-4 { break }
                var v = 0.0
                for p in note.partials {
                    v += p.amp * sin(phase * p.ratio) * (t < note.attack ? env : pow(env, 1 / p.decay))
                }
                out[i] += note.amp * v
            }
        }
        // いちばん大きいところを約 -10 dB にそろえ、最後の 4 ミリ秒で消してプツッという音を防ぐ
        let peak = out.map(abs).max() ?? 0
        let k = peak > 0 ? 0.32 * recipe.gain / peak : 0
        let fade = Int((0.004 * sampleRate).rounded())
        return out.indices.map { i in
            var v = out[i] * k
            if i > count - fade { v *= Double(count - i) / Double(fade) }
            return Float(v)
        }
    }

    /// 聞こえなくなるまでの秒数（いちばん大きいところから 40 dB 下がるまで）
    static func audibleLength(_ samples: [Float]) -> TimeInterval {
        let peak = samples.map(abs).max() ?? 0
        guard let last = samples.lastIndex(where: { abs($0) > peak * 0.01 }) else { return 0 }
        return Double(last) / sampleRate
    }
}
