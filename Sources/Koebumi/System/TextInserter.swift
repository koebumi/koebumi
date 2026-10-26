import AppKit
import ApplicationServices

struct SelectionInfo {
    var text: String
    var editable: Bool
}

/// カーソル位置への入力と、選択中テキストの取得。
/// 入力はクリップボード経由の ⌘V で行い、終わったら元のクリップボードを戻す。
@MainActor
enum TextInserter {
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    /// 貼り付け後に戻す予定の、ユーザーの元のクリップボード
    private static var savedClipboard: [[NSPasteboard.PasteboardType: Data]]?
    private static var restoreTask: Task<Void, Never>?

    /// テキストを入力先アプリに貼り付ける。keepInClipboard が false なら少し後に元のクリップボードを戻す。
    /// 戻す前に次の貼り付けが来たら、最初に退避した内容を使い回す（ユーザーのクリップボードを失わない）。
    static func paste(_ text: String, keepInClipboard: Bool) async {
        let pb = NSPasteboard.general
        restoreTask?.cancel()
        if keepInClipboard {
            savedClipboard = nil
        } else if savedClipboard == nil {
            savedClipboard = snapshot(pb)
        }
        pb.clearContents()
        pb.setString(text, forType: .string)
        if !keepInClipboard { pb.setData(Data(), forType: transientType) }
        let changeAfterWrite = pb.changeCount

        postKey(KeyNames.vKey, flags: .maskCommand)

        guard !keepInClipboard else { return }
        // Electron 系アプリはクリップボードを非同期に読むので少し待ってから戻す。
        // 呼び出し元のキャンセルで早まらないよう、独立したタスクで待つ。
        restoreTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            if pb.changeCount == changeAfterWrite, let saved = savedClipboard {
                restore(pb, saved)
            }
            savedClipboard = nil
        }
    }

    /// paste と同じく入力するが、入力先がない（Finder のデスクトップなど）ときは貼り付けずにクリップボードに残し、false を返す
    static func insert(_ text: String, keepInClipboard: Bool) async -> Bool {
        guard hasPasteTarget() else {
            copyToClipboard(text)
            return false
        }
        await paste(text, keepInClipboard: keepInClipboard)
        return true
    }

    /// 入力欄でカーソルの直前（選択しているならその範囲）にある old を、new に置き換える。
    /// 入力欄の文字をアクセシビリティ API で読んで old があると確かめられたときだけ置き換え、確かめられなければ何もせずに false を返す
    /// （⌘Z で取り消すと、入力した後にユーザーが打った文まで消してしまうため）
    static func replace(_ old: String, with new: String, keepInClipboard: Bool) async -> Bool {
        guard let element = focusedElement() else { return false }
        guard let value = value(of: element), let range = selectedRange(element) else {
            return await replaceWithMarkers(old, with: new, in: element, keepInClipboard: keepInClipboard)
        }
        let ns = value as NSString
        let target = range.length > 0
            ? NSRange(location: range.location, length: range.length)
            : NSRange(location: range.location - (old as NSString).length, length: (old as NSString).length)
        guard target.location >= 0, NSMaxRange(target) <= ns.length, sameText(ns.substring(with: target), old) else { return false }
        if range.length == 0 {
            var r = CFRange(location: target.location, length: target.length)
            guard let v = AXValueCreate(.cfRange, &r),
                  AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, v) == .success
            else { return false }
            // 選べたかを読み直して確かめる（選択を変えられない入力欄もある）
            try? await Task.sleep(for: .milliseconds(50))
            guard let selected = selectedRange(element), selected.location == r.location, selected.length == r.length else { return false }
        }
        await paste(new, keepInClipboard: keepInClipboard)
        return true
    }

    /// Web 表示の編集欄（Apple Mail の本文）での replace。文字の位置を持たないので、テキストマーカーで直前の文を選ぶ
    private static func replaceWithMarkers(_ old: String, with new: String, in element: AXUIElement, keepInClipboard: Bool) async -> Bool {
        guard let selection = TextMarkers.selection(element),
              let selected = TextMarkers.string(element, from: selection.start, to: selection.end) else { return false }
        if selected.isEmpty {
            guard let caret = TextMarkers.index(element, of: selection.end),
                  let start = TextMarkers.marker(element, at: caret - (old as NSString).length),
                  let text = TextMarkers.string(element, from: start, to: selection.end), sameText(text, old),
                  TextMarkers.select(element, from: start, to: selection.end) else { return false }
            // 選べたかを読み直して確かめる
            try? await Task.sleep(for: .milliseconds(50))
            guard let now = TextMarkers.selection(element),
                  let picked = TextMarkers.string(element, from: now.start, to: now.end), sameText(picked, old) else { return false }
        } else if !sameText(selected, old) {
            return false
        }
        await paste(new, keepInClipboard: keepInClipboard)
        return true
    }

    /// 改行の書き方（\r・\u{2028}）の違いを除いて同じ文か
    static func sameText(_ a: String, _ b: String) -> Bool {
        let lines = { (s: String) in
            s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: #"[\r\u{2028}\u{2029}]"#, with: "\n", options: .regularExpression)
        }
        return lines(a) == lines(b)
    }

    static func selectedRange(_ el: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range), range.location >= 0 else { return nil }
        return range
    }

    /// ⌘V で文字を入力できるか。Finder で入力欄（名前の変更・検索）以外にフォーカスがあると、⌘V はデスクトップやフォルダに貼り付けてしまう。
    /// ほかのアプリは入力欄をアクセシビリティ API で公開しないこと（Electron など）があるので、入力欄が見つからなくても入力できるとみなす
    static func hasPasteTarget() -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier != "com.apple.finder" || hasFocusedTextField()
    }

    /// Enter を押す（端末のエージェントに送信する）。貼り付けた文がエージェントの入力欄に入るのを待ってから押す
    static func pressReturn() async {
        try? await Task.sleep(for: .milliseconds(200))
        postKey(KeyNames.returnKey, flags: [])
    }

    /// 選択肢を上下の矢印で steps だけ動かしてから Enter を押す（Claude Code の許可の確認に答える）。
    /// 数字のキーは、日本語入力がオンだと変換中の文字になって届かないので使わない
    static func choose(moving steps: Int) async {
        for _ in 0..<abs(steps) {
            postKey(steps > 0 ? KeyNames.downArrow : KeyNames.upArrow, flags: [])
            try? await Task.sleep(for: .milliseconds(40))
        }
        postKey(KeyNames.returnKey, flags: [])
    }

    static func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    /// 選択中のテキストを取得する。アクセシビリティ API で取れないアプリでは ⌘C で取得する。
    static func selectedText() async -> SelectionInfo? {
        if let element = focusedElement() {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success {
                // 取得できて空なら「選択なし」。⌘C は使わない（VS Code などは選択なしで行全体をコピーするため）
                guard let text = value as? String, !text.isEmpty else { return nil }
                return SelectionInfo(text: text, editable: isEditable(element))
            }
        }

        let pb = NSPasteboard.general
        let saved = snapshot(pb)
        let before = pb.changeCount
        postKey(KeyNames.cKey, flags: .maskCommand)
        var copied: String?
        for _ in 0..<8 {
            try? await Task.sleep(for: .milliseconds(40))
            if pb.changeCount != before {
                copied = pb.string(forType: .string)
                break
            }
        }
        if pb.changeCount != before { restore(pb, saved) }
        guard let copied, !copied.isEmpty else { return nil }
        let editable = focusedElement().map(isEditable) ?? false
        return SelectionInfo(text: copied, editable: editable)
    }

    static func focusedElement() -> AXUIElement? {
        if let element = focusedElement(of: AXUIElementCreateSystemWide()) { return element }
        // macOS 27 ではシステム全体からの取得が失敗する（-25204）ことがあるので、前面のアプリから取り直す
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        return focusedElement(of: AXUIElementCreateApplication(pid))
    }

    private static func focusedElement(of root: AXUIElement) -> AXUIElement? {
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        return (focused as! AXUIElement)
    }

    static func hasFocusedTextField() -> Bool {
        guard let element = focusedElement() else { return false }
        return isEditable(element)
    }

    static func isEditable(_ element: AXUIElement) -> Bool {
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        let r = role as? String ?? ""
        if ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"].contains(r) { return true }
        var settable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success, settable.boolValue {
            return true
        }
        if AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success, settable.boolValue {
            return true
        }
        return false
    }

    /// Electron アプリ（Slack・Discord など）でアクセシビリティ情報を出してもらう
    static func enableAccessibility(for pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    static func value(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    // MARK: - 内部

    static func postKey(_ key: UInt16, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
            event.post(tap: .cghidEventTap)
        }
    }

    private static func snapshot(_ pb: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pb.pasteboardItems ?? []).map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { dict[type] = data }
            }
            return dict
        }
    }

    private static func restore(_ pb: NSPasteboard, _ items: [[NSPasteboard.PasteboardType: Data]]) {
        pb.clearContents()
        guard !items.isEmpty else { return }
        let objects: [NSPasteboardItem] = items.map { dict in
            let item = NSPasteboardItem()
            for (type, data) in dict { item.setData(data, forType: type) }
            return item
        }
        pb.writeObjects(objects)
    }
}
