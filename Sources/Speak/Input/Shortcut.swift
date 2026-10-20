import Foundation

/// 左右を区別した修飾キー。Fn（🌐）も含む。
enum ModKey: String, Codable, CaseIterable, Comparable {
    case fn, leftControl, rightControl, leftOption, rightOption, leftShift, rightShift, leftCommand, rightCommand

    static func < (a: ModKey, b: ModKey) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }

    var keyCode: UInt16 {
        switch self {
        case .fn: return 63
        case .leftControl: return 59
        case .rightControl: return 62
        case .leftOption: return 58
        case .rightOption: return 61
        case .leftShift: return 56
        case .rightShift: return 60
        case .leftCommand: return 55
        case .rightCommand: return 54
        }
    }

    /// CGEventFlags のデバイス依存ビット（NX_DEVICE*KEYMASK）。Fn は maskSecondaryFn。
    var flagMask: UInt64 {
        switch self {
        case .fn: return 0x0080_0000
        case .leftControl: return 0x0000_0001
        case .rightControl: return 0x0000_2000
        case .leftShift: return 0x0000_0002
        case .rightShift: return 0x0000_0004
        case .leftCommand: return 0x0000_0008
        case .rightCommand: return 0x0000_0010
        case .leftOption: return 0x0000_0020
        case .rightOption: return 0x0000_0040
        }
    }

    var label: String {
        switch self {
        case .fn: return "Fn"
        case .leftControl: return "Left ⌃"
        case .rightControl: return "Right ⌃"
        case .leftOption: return "Left ⌥"
        case .rightOption: return "Right ⌥"
        case .leftShift: return "Left ⇧"
        case .rightShift: return "Right ⇧"
        case .leftCommand: return "Left ⌘"
        case .rightCommand: return "Right ⌘"
        }
    }

    static func from(flags: UInt64) -> Set<ModKey> {
        Set(allCases.filter { flags & $0.flagMask != 0 })
    }

    static func isModifierKeyCode(_ code: UInt16) -> Bool {
        allCases.contains { $0.keyCode == code } || code == 57 /* caps lock */
    }
}

/// 修飾キーのみ（例: Fn, Fn + Left ⇧）または修飾キー + 通常キー（例: Fn + Space）のショートカット。
struct Shortcut: Codable, Hashable, Identifiable {
    var mods: Set<ModKey>
    var keyCode: UInt16?

    var id: String { display }

    var isEmpty: Bool { mods.isEmpty && keyCode == nil }

    var display: String {
        var parts = mods.sorted().map(\.label)
        if let keyCode { parts.append(KeyNames.name(for: keyCode)) }
        return parts.joined(separator: " + ")
    }

    static let fn = Shortcut(mods: [.fn], keyCode: nil)
    static let fnLeftShift = Shortcut(mods: [.fn, .leftShift], keyCode: nil)
    static let fnSpace = Shortcut(mods: [.fn], keyCode: KeyNames.space)
}

enum KeyNames {
    static let space: UInt16 = 49
    static let escape: UInt16 = 53
    static let vKey: UInt16 = 9
    static let cKey: UInt16 = 8

    private static let table: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
        20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
        29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N",
        46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`", 51: "Delete", 53: "Esc",
        64: "F17", 79: "F18", 80: "F19", 90: "F20",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11",
        105: "F13", 106: "F16", 107: "F14", 109: "F10", 111: "F12", 113: "F15",
        114: "Help", 115: "Home", 116: "Page Up", 117: "⌦", 118: "F4", 119: "End",
        120: "F2", 121: "Page Down", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑",
        102: "英数", 104: "かな",
    ]

    static func name(for code: UInt16) -> String {
        table[code] ?? "Key \(code)"
    }
}
