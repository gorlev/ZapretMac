import Foundation

/// A key combination that works in any app, like ⌃⌥B.
/// The key is a Mac virtual key code (the same number as NSEvent.keyCode and
/// Carbon's kVK_* constants); the modifiers are plain bits, so the value
/// needs neither AppKit nor Carbon.
public struct GlobalShortcut: Codable, Hashable, Sendable {
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static let command = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let control = Modifiers(rawValue: 1 << 2)
        public static let shift = Modifiers(rawValue: 1 << 3)
    }

    public var keyCode: UInt16
    public var modifiers: Modifiers

    public init(keyCode: UInt16, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// A shortcut that works in other apps needs Command, Option, or Control.
    /// Shift alone would take a capital letter away from every app.
    public var isValid: Bool {
        !modifiers.isDisjoint(with: [.command, .option, .control])
    }

    /// The combination in Mac notation, modifiers in the menu order: ⌃⌥⇧⌘B.
    public var displayString: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + Self.keyName(keyCode)
    }

    /// The modifier bits RegisterEventHotKey takes (cmdKey, shiftKey, optionKey, controlKey).
    public var carbonModifiers: UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains(.command) { flags |= 1 << 8 }
        if modifiers.contains(.shift) { flags |= 1 << 9 }
        if modifiers.contains(.option) { flags |= 1 << 11 }
        if modifiers.contains(.control) { flags |= 1 << 12 }
        return flags
    }

    /// The Escape key, which cancels recording a shortcut.
    public static let escapeKeyCode: UInt16 = 53

    /// The name of a key on a US keyboard, as menus show it.
    public static func keyName(_ keyCode: UInt16) -> String {
        if let name = names[keyCode] { return name }
        switch keyCode {
        case 49: return String(localized: "Space", bundle: .main)
        case 114: return String(localized: "Help", bundle: .main)
        default: return "#\(keyCode)"
        }
    }

    private static let names: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
        27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        36: "↩", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 48: "⇥", 50: "`", 51: "⌫", 53: "⎋",
        // Keypad
        65: ".", 67: "*", 69: "+", 71: "⌧", 75: "/", 76: "⌤", 78: "-", 81: "=",
        82: "0", 83: "1", 84: "2", 85: "3", 86: "4", 87: "5", 88: "6", 89: "7", 91: "8", 92: "9",
        // Function keys
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
        // Navigation
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
}
