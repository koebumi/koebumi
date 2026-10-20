import Foundation
import Testing
@testable import Speak

/// テスト用の時計を進められる HotkeyEngine
private final class Harness {
    let engine = HotkeyEngine()
    var clock = Date(timeIntervalSince1970: 1000)
    var state: EngineState = .idle

    init() {
        engine.bindings = [(.dictate, .fn), (.translate, .fnLeftShift), (.ask, .fnSpace)]
        engine.now = { [unowned self] in clock }
    }

    @discardableResult
    func send(_ e: HotkeyEvent) -> HotkeyResult {
        let r = engine.handle(e, state: state)
        for c in r.commands {
            switch c {
            case .begin(let m): state = .recording(m)
            case .switchMode(let m): state = .recording(m)
            case .finish: state = .busy
            case .cancel, .abort: state = .idle
            }
        }
        return r
    }

    func wait(_ s: TimeInterval) { clock += s }
}

@Suite struct HotkeyEngineTests {
    @Test func tapStartsHandsFreeAndSecondTapFinishes() {
        let h = Harness()
        #expect(h.send(.flags([.fn])).commands == [.begin(.dictate)])
        h.wait(0.1)
        #expect(h.send(.flags([])).commands.isEmpty)  // 短く押しただけ → ハンズフリーで録音継続
        h.wait(3)
        #expect(h.send(.flags([.fn])).commands.isEmpty)  // 録音中の押下は離した時点で判定
        #expect(h.send(.flags([])).commands == [.finish])
    }

    @Test func holdIsPushToTalk() {
        let h = Harness()
        h.send(.flags([.fn]))
        h.wait(2)
        #expect(h.send(.flags([])).commands == [.finish])
    }

    @Test func addingShiftSwitchesToTranslate() {
        let h = Harness()
        #expect(h.send(.flags([.fn])).commands == [.begin(.dictate)])
        #expect(h.send(.flags([.fn, .leftShift])).commands == [.switchMode(.translate)])
        h.wait(0.2)
        h.send(.flags([.fn]))
        #expect(h.send(.flags([])).commands.isEmpty)  // 翻訳は押して離すとハンズフリー
        #expect(h.state == .recording(.translate))
        // Fn を押して確定
        h.send(.flags([.fn]))
        #expect(h.send(.flags([])).commands == [.finish])
    }

    @Test func fnSpaceStartsAskAndSwallowsSpace() {
        let h = Harness()
        h.send(.flags([.fn]))
        let down = h.send(.keyDown(KeyNames.space, isRepeat: false))
        #expect(down.commands == [.switchMode(.ask)])
        #expect(down.swallow)
        #expect(h.send(.keyDown(KeyNames.space, isRepeat: true)).swallow)
        #expect(h.send(.keyUp(KeyNames.space)).swallow)
        h.send(.flags([]))
        #expect(h.state == .recording(.ask))
    }

    @Test func fnWithArrowAbortsSilently() {
        let h = Harness()
        h.send(.flags([.fn]))
        let r = h.send(.keyDown(123, isRepeat: false))  // ←
        #expect(r.commands == [.abort])
        #expect(!r.swallow)
        h.send(.keyUp(123))
        #expect(h.send(.flags([])).commands.isEmpty)
    }

    @Test func escapeCancelsWhileRecordingOnly() {
        let h = Harness()
        #expect(!h.send(.keyDown(KeyNames.escape, isRepeat: false)).swallow)
        h.send(.flags([.fn]))
        h.send(.flags([]))
        let r = h.send(.keyDown(KeyNames.escape, isRepeat: false))
        #expect(r.commands == [.cancel])
        #expect(r.swallow)
        #expect(h.send(.keyUp(KeyNames.escape)).swallow)  // keyUp も入力先に届けない
    }

    @Test func pressingTranslateWhileDictatingSwitchesOnRelease() {
        let h = Harness()
        h.send(.flags([.fn]))
        h.send(.flags([]))
        h.wait(2)
        h.send(.flags([.fn]))
        h.send(.flags([.fn, .leftShift]))
        h.send(.flags([.fn]))
        #expect(h.send(.flags([])).commands == [.switchMode(.translate)])
    }

    @Test func ignoresShortcutsWhileBusy() {
        let h = Harness()
        h.state = .busy
        #expect(h.send(.flags([.fn])).commands.isEmpty)
        #expect(h.send(.flags([])).commands.isEmpty)
    }

    @Test func modifierFlagsDecodeLeftAndRight() {
        let flags: UInt64 = 0x0080_0000 | 0x2 | 0x40
        #expect(ModKey.from(flags: flags) == [.fn, .leftShift, .rightOption])
        #expect(Shortcut.fnSpace.display == "Fn + Space")
        #expect(Shortcut.fnLeftShift.display == "Fn + Left ⇧")
    }
}
