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
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
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
