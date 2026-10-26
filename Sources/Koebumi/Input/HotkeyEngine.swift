import Foundation

enum HotkeyEvent: Equatable {
    case flags(Set<ModKey>)
    case keyDown(UInt16, isRepeat: Bool)
    case keyUp(UInt16)
}

enum EngineState: Equatable {
    case idle
    case recording(Mode)
    case busy  // 認識・整形中
}

enum HotkeyCommand: Equatable {
    case begin(Mode)
    case switchMode(Mode)
    case finish
    case cancel  // Esc
    case abort  // Fn + 矢印など、ショートカット以外のキーと組み合わされた誤操作
    case pasteLast  // 最後の結果を貼り付け
    case revertLast  // 直前に入力した文の AI の整形を元に戻す（もう一度で AI の文に戻す）
}

struct HotkeyResult: Equatable {
    var commands: [HotkeyCommand] = []
    var swallow = false
}

/// ショートカット判定の純粋なステートマシン。CGEventTap から呼ばれ、テストからも直接動かせる。
///
/// - 待機中にショートカットを押した瞬間に録音を開始する（Fn を押した直後から音声を逃さない）。
/// - 同じ押下の途中でキーが足されて別のショートカットになったら、録音を続けたままモードを切り替える
///   （Fn → Fn + Shift で翻訳、Fn → Fn + Space で Ask）。
/// - ディクテーションのキーを長押しして離すとプッシュトゥトーク、短く押すとハンズフリー（もう一度押して確定）。
/// - 録音中の押下は離した時点で判定する（Fn + Shift の途中で Fn だけが一致して確定しないように）。
/// - 最後の結果の貼り付けと、AI の整形の取り消しは、キーをすべて離してから行う（押したままの修飾キーが ⌘V に混ざらないように）。
final class HotkeyEngine {
    var bindings: [(Mode, Shortcut)] = []
    var pasteBindings: [Shortcut] = []
    var revertBindings: [Shortcut] = []
    var holdThreshold: TimeInterval = 0.45
    var comboHoldThreshold: TimeInterval = 1.0
    var now: () -> Date = Date.init

    private var mods: Set<ModKey> = []
    private var keysDown: Set<UInt16> = []
    private var gesture: Gesture?

    private struct Gesture {
        var start: Date
        var startedRecording = false
        var mode: Mode?
        var maxMatch: Mode?
        var maxMatchHasKey = false
        var hadForeignKey = false
        /// キーを離したときに行う、録音以外の操作（貼り付け・取り消し）
        var action: HotkeyCommand?
    }

    func reset() {
        mods = []
        keysDown = []
        gesture = nil
    }

    func handle(_ event: HotkeyEvent, state: EngineState) -> HotkeyResult {
        switch event {
        case .flags(let newMods):
            return handleFlags(newMods, state: state)
        case .keyDown(let code, let isRepeat):
            return handleKeyDown(code, isRepeat: isRepeat, state: state)
        case .keyUp(let code):
            return handleKeyUp(code, state: state)
        }
    }

    private func match(mods: Set<ModKey>, key: UInt16?) -> Mode? {
        bindings.first { $0.1.mods == mods && $0.1.keyCode == key && !$0.1.isEmpty }?.0
    }

    /// 録音以外の操作のショートカット
    private func action(mods: Set<ModKey>, key: UInt16?) -> HotkeyCommand? {
        let matches = { (list: [Shortcut]) in list.contains { $0.mods == mods && $0.keyCode == key && !$0.isEmpty } }
        if matches(pasteBindings) { return .pasteLast }
        if matches(revertBindings) { return .revertLast }
        return nil
    }

    private func handleFlags(_ newMods: Set<ModKey>, state: EngineState) -> HotkeyResult {
        let old = mods
        mods = newMods
        let added = !newMods.subtracting(old).isEmpty

        if added {
            if let command = action(mods: newMods, key: keysDown.first), let result = request(command, state: state) {
                return result
            }
            if gesture == nil { gesture = Gesture(start: now()) }
            guard let m = match(mods: newMods, key: keysDown.first) else { return HotkeyResult() }
            return matched(m, hasKey: false, state: state)
        }

        if newMods.isEmpty && keysDown.isEmpty {
            return HotkeyResult(commands: endGesture(state: state))
        }
        return HotkeyResult()
    }

    private func handleKeyDown(_ code: UInt16, isRepeat: Bool, state: EngineState) -> HotkeyResult {
        if keysDown.contains(code) {
            return HotkeyResult(swallow: true)  // オートリピート
        }

        if code == KeyNames.escape, state != .idle {
            keysDown.insert(code)  // 対になる keyUp も入力先アプリに届けない
            return HotkeyResult(commands: [.cancel], swallow: true)
        }

        if !isRepeat, let command = action(mods: mods, key: code), var result = request(command, state: state) {
            keysDown.insert(code)
            result.swallow = true
            return result
        }

        if !isRepeat, let m = match(mods: mods, key: code) {
            keysDown.insert(code)
            if gesture == nil { gesture = Gesture(start: now()) }
            var result = matched(m, hasKey: true, state: state)
            result.swallow = true
            return result
        }

        // ショートカット以外のキー
        guard var g = gesture else { return HotkeyResult() }
        var commands: [HotkeyCommand] = []
        if g.startedRecording, case .recording = state, !g.hadForeignKey {
            commands.append(.abort)
        }
        g.hadForeignKey = true
        gesture = g
        return HotkeyResult(commands: commands)
    }

    private func handleKeyUp(_ code: UInt16, state: EngineState) -> HotkeyResult {
        guard keysDown.remove(code) != nil else { return HotkeyResult() }
        var result = HotkeyResult(swallow: true)
        if mods.isEmpty && keysDown.isEmpty {
            result.commands = endGesture(state: state)
        }
        return result
    }

    private func matched(_ m: Mode, hasKey: Bool, state: EngineState) -> HotkeyResult {
        guard var g = gesture else { return HotkeyResult() }
        defer { gesture = g }
        if !(g.maxMatchHasKey && !hasKey) {
            g.maxMatch = m
            g.maxMatchHasKey = hasKey
        }
        switch state {
        case .idle:
            g.startedRecording = true
            g.mode = m
            g.start = now()
            return HotkeyResult(commands: [.begin(m)])
        case .recording(let current):
            if g.startedRecording, m != current {
                g.mode = m
                return HotkeyResult(commands: [.switchMode(m)])
            }
            return HotkeyResult()
        case .busy:
            return HotkeyResult()
        }
    }

    /// 貼り付けや取り消しを予約する。待機中か、Fn + V のように同じ押下で録音を始めたときだけ受け付ける
    private func request(_ command: HotkeyCommand, state: EngineState) -> HotkeyResult? {
        var g = gesture ?? Gesture(start: now())
        switch state {
        case .idle:
            g.action = command
            gesture = g
            return HotkeyResult()
        case .recording where g.startedRecording:
            // 押した瞬間に始めた録音は捨てる
            g.action = command
            gesture = g
            return HotkeyResult(commands: [.abort])
        default:
            return nil
        }
    }

    private func endGesture(state: EngineState) -> [HotkeyCommand] {
        guard let g = gesture else { return [] }
        gesture = nil
        if g.hadForeignKey { return [] }
        if let action = g.action { return [action] }
        guard case .recording(let current) = state else { return [] }

        if g.startedRecording {
            // 長押しして離した → プッシュトゥトークとして確定
            let held = now().timeIntervalSince(g.start)
            let threshold = (g.mode ?? current) == .dictate ? holdThreshold : comboHoldThreshold
            return held >= threshold ? [.finish] : []
        }

        guard let m = g.maxMatch else { return [] }
        if m == .dictate || m == current { return [.finish] }
        return [.switchMode(m)]
    }
}
