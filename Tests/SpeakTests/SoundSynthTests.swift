import Foundation
import Testing
@testable import Speak

@Suite struct SoundSynthTests {
    private let twoNotes = SoundSynth.Recipe(notes: [
        .init(frequency: 587.3, attack: 0.012, decay: 0.07),
        .init(time: 0.07, frequency: 880, attack: 0.012, decay: 0.1),
    ])

    @Test func alignsPeakWithSystemSounds() {
        let samples = SoundSynth.render(twoNotes)
        let peak = samples.map(abs).max() ?? 0
        #expect(abs(peak - 0.32) < 0.001)  // macOS の効果音と同じ約 -10 dB
    }

    @Test func gainMakesItQuieter() {
        var quiet = twoNotes
        quiet.gain = 0.5
        let peak = SoundSynth.render(quiet).map(abs).max() ?? 0
        #expect(abs(peak - 0.16) < 0.001)
    }

    @Test func endsSilentWithoutClick() {
        let samples = SoundSynth.render(twoNotes)
        #expect(abs(samples.last ?? 1) < 1e-4)
        #expect(!samples.contains { $0.isNaN })
    }

    @Test func measuresAudibleLength() {
        let samples = SoundSynth.render(twoNotes)
        let length = SoundSynth.audibleLength(samples)
        // 2 音目は 0.07 秒に鳴り始め、0.5 秒前後で 40 dB 下がる
        #expect(length > 0.45 && length < 0.6)
        #expect(length < Double(samples.count) / SoundSynth.sampleRate)
    }

    @MainActor @Test func matchesSoundPage() {
        // 「Speak 効果音」のページで選んだ音（やわらか・ガラスのエラー）と同じ長さになる
        let expected: [(Sounds.Cue, Double)] = [(.start, 0.52), (.stop, 0.69), (.cancel, 0.38), (.error, 0.98)]
        for (cue, length) in expected {
            let measured = SoundSynth.audibleLength(SoundSynth.render(Sounds.recipe(cue)))
            #expect(abs(measured - length) < 0.01, "\(cue): \(measured)")
        }
    }

    @Test func glidesPitch() {
        // 音程を動かしても壊れない（音の長さは減衰で決まる）
        let glide = SoundSynth.Recipe(notes: [.init(frequency: 420, glideTo: 980, glide: 0.07, decay: 0.05)])
        let samples = SoundSynth.render(glide)
        #expect(!samples.contains { $0.isNaN })
        #expect(SoundSynth.audibleLength(samples) > 0.2)
    }
}
