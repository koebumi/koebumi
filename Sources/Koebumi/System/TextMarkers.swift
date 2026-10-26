import ApplicationServices
import Foundation

/// Web 表示の編集欄（Apple Mail の本文など）は文字の位置（AXSelectedTextRange）を持たないので、テキストマーカーで位置を扱う
enum TextMarkers {
    /// 選択範囲の始まりと終わり（カーソルだけなら同じ位置）
    static func selection(_ el: AXUIElement) -> (start: AXTextMarker, end: AXTextMarker)? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, "AXSelectedTextMarkerRange" as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXTextMarkerRangeGetTypeID() else { return nil }
        let range = value as! AXTextMarkerRange
        return (AXTextMarkerRangeCopyStartMarker(range), AXTextMarkerRangeCopyEndMarker(range))
    }

    /// 文書の最初と最後
    static func document(_ el: AXUIElement) -> (start: AXTextMarker, end: AXTextMarker)? {
        guard let start = marker(attribute(el, "AXStartTextMarker")), let end = marker(attribute(el, "AXEndTextMarker")) else { return nil }
        return (start, end)
    }

    /// 文書の先頭からの文字数
    static func index(_ el: AXUIElement, of marker: AXTextMarker) -> Int? {
        (parameterized(el, "AXIndexForTextMarker", marker) as? NSNumber)?.intValue
    }

    static func marker(_ el: AXUIElement, at index: Int) -> AXTextMarker? {
        guard index >= 0 else { return nil }
        return marker(parameterized(el, "AXTextMarkerForIndex", NSNumber(value: index)))
    }

    static func string(_ el: AXUIElement, from start: AXTextMarker, to end: AXTextMarker) -> String? {
        parameterized(el, "AXStringForTextMarkerRange", AXTextMarkerRangeCreate(nil, start, end)) as? String
    }

    static func select(_ el: AXUIElement, from start: AXTextMarker, to end: AXTextMarker) -> Bool {
        AXUIElementSetAttributeValue(el, "AXSelectedTextMarkerRange" as CFString, AXTextMarkerRangeCreate(nil, start, end)) == .success
    }

    private static func attribute(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success ? value : nil
    }

    private static func parameterized(_ el: AXUIElement, _ name: String, _ param: CFTypeRef) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyParameterizedAttributeValue(el, name as CFString, param, &value) == .success ? value : nil
    }

    private static func marker(_ value: CFTypeRef?) -> AXTextMarker? {
        guard let value, CFGetTypeID(value) == AXTextMarkerGetTypeID() else { return nil }
        return (value as! AXTextMarker)
    }
}
