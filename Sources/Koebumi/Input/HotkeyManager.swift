import AppKit
import CoreGraphics

/// 自分で送ったキーイベント（貼り付け用の ⌘V など）に付ける印。タップで無視する。
let syntheticEventMarker: Int64 = 0x5350_4B21

/// CGEventTap でキーボードを監視し、HotkeyEngine の判定結果をコントローラへ渡す。
/// Fn + Space の Space や録音中の Esc は飲み込み、入力先アプリには届けない。
///
/// タップは専用スレッドで動かす。アクティブなタップのコールバックが返るまでシステム全体のキー入力が止まるため、
/// マイクの起動などで重くなるメインスレッドとは切り離し、判定だけをここで行ってコマンドはメインへ送る。
final class HotkeyManager: @unchecked Sendable {
    /// メインスレッドで呼ばれる
    var onCommand: @MainActor (HotkeyCommand) -> Void = { _ in }
    /// コントローラの現在の状態（メインスレッドで読む）
    var stateProvider: @MainActor () -> EngineState = { .idle }
    /// 回答カードなど、待機中の Esc で閉じるものが出ているか（メインスレッドで読む）
    var escapeTargetProvider: @MainActor () -> Bool = { false }
    /// 待機中の Esc で呼ばれる（メインスレッド）
    var onIdleEscape: @MainActor () -> Void = {}

    private let engine = HotkeyEngine()
    private let lock = NSLock()
    // ↓ lock で守る
    private var mirroredState: EngineState = .idle
    private var pendingState: EngineState?
    private var escapeTargetVisible = false
    private var captureHandler: (@MainActor (Shortcut?) -> Void)?
    private var captureMods: Set<ModKey> = []
    private var captureCurrentMods: Set<ModKey> = []
    private var captureKey: UInt16?
    // ↑
    private var tap: CFMachPort?
    private var thread: Thread?
    private(set) var isRunning = false

    @MainActor
    func updateBindings(_ settings: AppSettings) {
        var list: [(Mode, Shortcut)] = []
        for mode in Mode.allCases {
            for s in settings.shortcuts(for: mode) where !s.isEmpty {
                list.append((mode, s))
            }
        }
        let paste = settings.pasteLastShortcuts.filter { !$0.isEmpty }
        lock.withLock {
            engine.bindings = list
            engine.pasteBindings = paste
        }
    }

    /// コントローラの状態が変わったら呼ぶ。タップ側の状態の写しを更新する。
    @MainActor
    func refreshState() {
        let state = stateProvider()
        let escapeTarget = escapeTargetProvider()
        lock.withLock {
            mirroredState = state
            pendingState = nil
            escapeTargetVisible = escapeTarget
        }
    }

    @MainActor
    @discardableResult
    func start() -> Bool {
        if isRunning { return true }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hotkeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "Koebumi.HotkeyTap"
        thread.qualityOfService = .userInteractive
        thread.start()
        self.thread = thread
        isRunning = true
        refreshState()
        return true
    }

    /// 次に押されたキーの組み合わせを記録する。Esc 単独でキャンセル。
    @MainActor
    func captureNextShortcut(_ handler: @escaping @MainActor (Shortcut?) -> Void) {
        lock.withLock {
            captureHandler = handler
            captureMods = []
            captureCurrentMods = []
            captureKey = nil
        }
    }

    // MARK: - タップのスレッド

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            lock.withLock { engine.reset() }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == syntheticEventMarker {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let hotkeyEvent: HotkeyEvent
        switch type {
        case .flagsChanged:
            hotkeyEvent = .flags(ModKey.from(flags: event.flags.rawValue))
        case .keyDown:
            hotkeyEvent = .keyDown(keyCode, isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
        case .keyUp:
            hotkeyEvent = .keyUp(keyCode)
        default:
            return Unmanaged.passUnretained(event)
        }

        lock.lock()
        if captureHandler != nil {
            let finished = handleCapture(hotkeyEvent)
            lock.unlock()
            if let (handler, shortcut) = finished {
                DispatchQueue.main.async { handler(shortcut) }
            }
            return nil
        }

        let state = pendingState ?? mirroredState
        if case .keyDown(KeyNames.escape, _) = hotkeyEvent, state == .idle, escapeTargetVisible {
            escapeTargetVisible = false
            lock.unlock()
            DispatchQueue.main.async { [self] in onIdleEscape() }
            return nil
        }

        let result = engine.handle(hotkeyEvent, state: state)
        // メインで処理されるまでの間に次のキーが来ても正しく判定できるよう、結果の状態を先に反映しておく
        for command in result.commands {
            switch command {
            case .begin(let m), .switchMode(let m): pendingState = .recording(m)
            case .finish: pendingState = .busy
            case .cancel, .abort: pendingState = .idle
            case .pasteLast: break
            }
        }
        lock.unlock()

        if !result.commands.isEmpty {
            DispatchQueue.main.async { [self] in
                for command in result.commands { onCommand(command) }
                refreshState()
            }
        }
        return result.swallow ? nil : Unmanaged.passUnretained(event)
    }

    /// lock を持った状態で呼ぶ。記録が終わったら (handler, shortcut) を返す。
    private func handleCapture(_ event: HotkeyEvent) -> ((@MainActor (Shortcut?) -> Void), Shortcut?)? {
        switch event {
        case .flags(let mods):
            captureCurrentMods = mods
            captureMods.formUnion(mods)
            // すべての修飾キーを離した時点で確定する
            if mods.isEmpty, !captureMods.isEmpty || captureKey != nil {
                return finishCapture()
            }
        case .keyDown(let code, _):
            if code == KeyNames.escape, captureMods.isEmpty {
                let handler = captureHandler
                captureHandler = nil
                return handler.map { ($0, nil) }
            }
            if !ModKey.isModifierKeyCode(code) { captureKey = code }
        case .keyUp(let code):
            if code == captureKey, captureCurrentMods.isEmpty {
                return finishCapture()
            }
        }
        return nil
    }

    private func finishCapture() -> ((@MainActor (Shortcut?) -> Void), Shortcut?)? {
        guard let handler = captureHandler else { return nil }
        let shortcut = Shortcut(mods: captureMods, keyCode: captureKey)
        captureHandler = nil
        return (handler, shortcut.isEmpty ? nil : shortcut)
    }
}

private func hotkeyTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
    return manager.handle(type: type, event: event)
}
