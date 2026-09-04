import Foundation

/// USB HID Usage Table, page 0x07 (Keyboard/Keypad).
///
/// The keypad firmware speaks these usage ids directly, so recording a key is a
/// matter of turning a macOS virtual key code into the right usage id.
public enum HIDKeyboard {

    /// macOS virtual key code (`NSEvent.keyCode`) → HID keyboard usage id.
    ///
    /// Deliberately keyed on the *physical* key position rather than the
    /// character it produces, so a non-US layout records the key the user
    /// actually pressed — the same problem the original tool solves on Windows
    /// by translating through the en-US layout.
    public static let virtualKeyToUsage: [UInt16: UInt8] = [
        0x00: 0x04, // A
        0x0B: 0x05, // B
        0x08: 0x06, // C
        0x02: 0x07, // D
        0x0E: 0x08, // E
        0x03: 0x09, // F
        0x05: 0x0A, // G
        0x04: 0x0B, // H
        0x22: 0x0C, // I
        0x26: 0x0D, // J
        0x28: 0x0E, // K
        0x25: 0x0F, // L
        0x2E: 0x10, // M
        0x2D: 0x11, // N
        0x1F: 0x12, // O
        0x23: 0x13, // P
        0x0C: 0x14, // Q
        0x0F: 0x15, // R
        0x01: 0x16, // S
        0x11: 0x17, // T
        0x20: 0x18, // U
        0x09: 0x19, // V
        0x0D: 0x1A, // W
        0x07: 0x1B, // X
        0x10: 0x1C, // Y
        0x06: 0x1D, // Z

        0x12: 0x1E, // 1
        0x13: 0x1F, // 2
        0x14: 0x20, // 3
        0x15: 0x21, // 4
        0x17: 0x22, // 5
        0x16: 0x23, // 6
        0x1A: 0x24, // 7
        0x1C: 0x25, // 8
        0x19: 0x26, // 9
        0x1D: 0x27, // 0

        0x24: 0x28, // Return
        0x35: 0x29, // Escape
        0x33: 0x2A, // Backspace (Delete)
        0x30: 0x2B, // Tab
        0x31: 0x2C, // Space
        0x1B: 0x2D, // -
        0x18: 0x2E, // =
        0x21: 0x2F, // [
        0x1E: 0x30, // ]
        0x2A: 0x31, // backslash
        0x29: 0x33, // ;
        0x27: 0x34, // '
        0x32: 0x35, // ` (grave)
        0x2B: 0x36, // ,
        0x2F: 0x37, // .
        0x2C: 0x38, // /
        0x39: 0x39, // Caps Lock

        0x7A: 0x3A, // F1
        0x78: 0x3B, // F2
        0x63: 0x3C, // F3
        0x76: 0x3D, // F4
        0x60: 0x3E, // F5
        0x61: 0x3F, // F6
        0x62: 0x40, // F7
        0x64: 0x41, // F8
        0x65: 0x42, // F9
        0x6D: 0x43, // F10
        0x67: 0x44, // F11
        0x6F: 0x45, // F12

        0x72: 0x49, // Help → Insert
        0x73: 0x4A, // Home
        0x74: 0x4B, // Page Up
        0x75: 0x4C, // Forward Delete
        0x77: 0x4D, // End
        0x79: 0x4E, // Page Down
        0x7C: 0x4F, // Right
        0x7B: 0x50, // Left
        0x7D: 0x51, // Down
        0x7E: 0x52, // Up

        0x47: 0x53, // Keypad Clear → Num Lock
        0x4B: 0x54, // Keypad /
        0x43: 0x55, // Keypad *
        0x4E: 0x56, // Keypad -
        0x45: 0x57, // Keypad +
        0x4C: 0x58, // Keypad Enter
        0x53: 0x59, // Keypad 1
        0x54: 0x5A, // Keypad 2
        0x55: 0x5B, // Keypad 3
        0x56: 0x5C, // Keypad 4
        0x57: 0x5D, // Keypad 5
        0x58: 0x5E, // Keypad 6
        0x59: 0x5F, // Keypad 7
        0x5B: 0x60, // Keypad 8
        0x5C: 0x61, // Keypad 9
        0x52: 0x62, // Keypad 0
        0x41: 0x63, // Keypad .
        0x0A: 0x64, // ISO section / non-US backslash
        0x51: 0x67, // Keypad =

        0x69: 0x68, // F13
        0x6B: 0x69, // F14
        0x71: 0x6A, // F15
        0x6A: 0x6B, // F16
        0x40: 0x6C, // F17
        0x4F: 0x6D, // F18
        0x50: 0x6E, // F19
        0x5A: 0x6F, // F20
    ]

    private static let names: [UInt8: String] = {
        var m: [UInt8: String] = [:]
        for (i, c) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated() {
            m[UInt8(0x04 + i)] = String(c)
        }
        for (i, c) in "1234567890".enumerated() {
            m[UInt8(0x1E + i)] = String(c)
        }
        m[0x00] = "—"
        m[0x28] = "Return"
        m[0x29] = "Esc"
        m[0x2A] = "Backspace"
        m[0x2B] = "Tab"
        m[0x2C] = "Space"
        m[0x2D] = "-"
        m[0x2E] = "="
        m[0x2F] = "["
        m[0x30] = "]"
        m[0x31] = "\\"
        m[0x32] = "#"
        m[0x33] = ";"
        m[0x34] = "'"
        m[0x35] = "`"
        m[0x36] = ","
        m[0x37] = "."
        m[0x38] = "/"
        m[0x39] = "CapsLock"
        for i in 0..<12 { m[UInt8(0x3A + i)] = "F\(i + 1)" }
        m[0x46] = "PrtSc"
        m[0x47] = "ScrLk"
        m[0x48] = "Pause"
        m[0x49] = "Insert"
        m[0x4A] = "Home"
        m[0x4B] = "PgUp"
        m[0x4C] = "Delete"
        m[0x4D] = "End"
        m[0x4E] = "PgDn"
        m[0x4F] = "→"
        m[0x50] = "←"
        m[0x51] = "↓"
        m[0x52] = "↑"
        m[0x53] = "NumLock"
        m[0x54] = "KP /"
        m[0x55] = "KP *"
        m[0x56] = "KP -"
        m[0x57] = "KP +"
        m[0x58] = "KP Enter"
        for i in 0..<9 { m[UInt8(0x59 + i)] = "KP \(i + 1)" }
        m[0x62] = "KP 0"
        m[0x63] = "KP ."
        m[0x64] = "ISO \\"
        m[0x65] = "Menu"
        m[0x67] = "KP ="
        for i in 0..<12 { m[UInt8(0x68 + i)] = "F\(i + 13)" }
        return m
    }()

    public static func name(for usage: UInt8) -> String {
        names[usage] ?? String(format: "0x%02X", usage)
    }

    /// Every usage the picker offers, in a sensible order.
    public static let selectable: [UInt8] = {
        var out: [UInt8] = []
        out.append(contentsOf: (0x04...0x1D).map(UInt8.init))   // A–Z
        out.append(contentsOf: (0x1E...0x27).map(UInt8.init))   // 1–0
        out.append(contentsOf: [0x28, 0x29, 0x2A, 0x2B, 0x2C])  // Return … Space
        out.append(contentsOf: (0x2D...0x38).map(UInt8.init))   // punctuation
        out.append(0x39)
        out.append(contentsOf: (0x3A...0x45).map(UInt8.init))   // F1–F12
        out.append(contentsOf: (0x68...0x73).map(UInt8.init))   // F13–F24
        out.append(contentsOf: (0x46...0x52).map(UInt8.init))   // PrtSc … arrows
        out.append(contentsOf: (0x53...0x63).map(UInt8.init))   // keypad
        out.append(contentsOf: [0x64, 0x65, 0x67])
        return out
    }()

    /// macOS modifier flags → HID modifier byte.
    /// macOS reports left/right separately through device-dependent flag bits.
    public static func modifiers(from flags: UInt) -> Modifier {
        // Device-dependent bits, from IOKit's `NX_DEVICELCTLKEYMASK` family.
        let lShift: UInt = 0x0002, rShift: UInt = 0x0004
        let lCtrl: UInt  = 0x0001, rCtrl: UInt  = 0x2000
        let lAlt: UInt   = 0x0020, rAlt: UInt   = 0x0040
        let lCmd: UInt   = 0x0008, rCmd: UInt   = 0x0010

        var m: Modifier = .none
        if flags & lShift != 0 { m.insert(.leftShift) }
        if flags & rShift != 0 { m.insert(.rightShift) }
        if flags & lCtrl != 0 { m.insert(.leftCtrl) }
        if flags & rCtrl != 0 { m.insert(.rightCtrl) }
        if flags & lAlt != 0 { m.insert(.leftAlt) }
        if flags & rAlt != 0 { m.insert(.rightAlt) }
        if flags & lCmd != 0 { m.insert(.leftGui) }
        if flags & rCmd != 0 { m.insert(.rightGui) }
        return m
    }
}
