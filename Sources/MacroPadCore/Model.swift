import Foundation

// MARK: - Protocol family

/// The two wire protocols used by these keypads.
/// Ported from RSoft.MacroPad `ProtocolType`.
public enum PadProtocol: String, Codable, CaseIterable, Sendable {
    case legacy
    case extended

    public var displayName: String {
        switch self {
        case .legacy: return "Legacy (v0)"
        case .extended: return "Extended (v1)"
        }
    }
}

/// Which physical control on the pad a mapping belongs to.
/// The raw values match the original tool; `wireValue` is what goes on the wire.
public enum InputAction: UInt8, Codable, CaseIterable, Identifiable, Sendable {
    case none = 0
    case key1 = 1, key2, key3, key4, key5, key6, key7, key8, key9, key10, key11, key12
    case knob1Left = 23, knob1Push, knob1Right
    case knob2Left, knob2Push, knob2Right
    case knob3Left, knob3Push, knob3Right

    public var id: UInt8 { rawValue }

    /// Keys map 1:1, knob actions are shifted down by 10.
    public var wireValue: UInt8 {
        switch self {
        case .none: return 0
        case .key1, .key2, .key3, .key4, .key5, .key6,
             .key7, .key8, .key9, .key10, .key11, .key12:
            return rawValue
        default:
            return rawValue - 10
        }
    }

    public static func key(_ index: Int) -> InputAction {
        InputAction(rawValue: UInt8(index)) ?? .none
    }

    public static func knob(_ index: Int, _ part: KnobPart) -> InputAction {
        InputAction(rawValue: UInt8(23 + (index - 1) * 3 + part.offset)) ?? .none
    }

    public var displayName: String {
        switch self {
        case .none: return "—"
        case .knob1Left: return "Knob 1 ↺"
        case .knob1Push: return "Knob 1 ⏺"
        case .knob1Right: return "Knob 1 ↻"
        case .knob2Left: return "Knob 2 ↺"
        case .knob2Push: return "Knob 2 ⏺"
        case .knob2Right: return "Knob 2 ↻"
        case .knob3Left: return "Knob 3 ↺"
        case .knob3Push: return "Knob 3 ⏺"
        case .knob3Right: return "Knob 3 ↻"
        default: return "Key \(rawValue)"
        }
    }
}

public enum KnobPart: Int, Codable, CaseIterable, Sendable {
    case left = 0, push = 1, right = 2
    var offset: Int { rawValue }

    public var symbol: String {
        switch self {
        case .left: return "↺"
        case .push: return "⏺"
        case .right: return "↻"
        }
    }
}

/// Payload kind byte inside a report.
public enum KeyType: UInt8, Sendable {
    case none = 0
    case basic = 1
    case multimedia = 2
    case mouse = 3
    case led = 8
}

/// Standard HID keyboard modifier bitmask (USB HID 1.11, byte 0 of a boot report).
public struct Modifier: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let leftCtrl  = Modifier(rawValue: 1 << 0)
    public static let leftShift = Modifier(rawValue: 1 << 1)
    public static let leftAlt   = Modifier(rawValue: 1 << 2)
    public static let leftGui   = Modifier(rawValue: 1 << 3)
    public static let rightCtrl  = Modifier(rawValue: 1 << 4)
    public static let rightShift = Modifier(rawValue: 1 << 5)
    public static let rightAlt   = Modifier(rawValue: 1 << 6)
    public static let rightGui   = Modifier(rawValue: 1 << 7)

    public static let none: Modifier = []

    /// Short symbolic description, e.g. "⌃⇧".
    public var symbols: String {
        var s = ""
        if contains(.leftCtrl) || contains(.rightCtrl) { s += "⌃" }
        if contains(.leftAlt) || contains(.rightAlt) { s += "⌥" }
        if contains(.leftShift) || contains(.rightShift) { s += "⇧" }
        if contains(.leftGui) || contains(.rightGui) { s += "⌘" }
        return s
    }
}

// MARK: - Mouse

public enum MouseButton: String, Codable, CaseIterable, Identifiable, Sendable {
    case left, middle, right, scrollUp, scrollDown

    public var id: String { rawValue }

    /// Button bitmask byte.
    public var buttons: UInt8 {
        switch self {
        case .left: return 1
        case .right: return 2
        case .middle: return 4
        case .scrollUp, .scrollDown: return 0
        }
    }

    /// Signed scroll delta byte.
    public var scroll: UInt8 {
        switch self {
        case .scrollUp: return 1
        case .scrollDown: return 255
        default: return 0
        }
    }

    public var displayName: String {
        switch self {
        case .left: return "Left click"
        case .middle: return "Middle click"
        case .right: return "Right click"
        case .scrollUp: return "Scroll up"
        case .scrollDown: return "Scroll down"
        }
    }
}

// MARK: - Media

/// A consumer-page ("multimedia") key.
///
/// Firmware revisions disagree on how these are encoded, so each key carries the
/// three known encodings. `v3` is a plain little-endian HID Consumer usage id,
/// which is why arbitrary consumer usages can be expressed there.
public struct MediaKey: Codable, Hashable, Identifiable, Sendable {
    public var name: String
    /// HID Consumer page usage id — the encoding used by report id 3 firmware.
    public var usage: UInt16
    /// Encoding used by report id 0 firmware (bitmask style), if known.
    public var v0: (UInt8, UInt8)?
    /// Encoding used by report id 2 firmware, if known.
    public var v2: (UInt8, UInt8)?

    public var id: String { name }

    public init(name: String, usage: UInt16, v0: (UInt8, UInt8)? = nil, v2: (UInt8, UInt8)? = nil) {
        self.name = name
        self.usage = usage
        self.v0 = v0
        self.v2 = v2
    }

    public func bytes(forReportId reportId: UInt8, encoding: MediaEncoding) -> (UInt8, UInt8) {
        let effective: MediaEncoding
        switch encoding {
        case .auto:
            effective = reportId == 0 ? .legacyBitmask : (reportId == 2 ? .legacyV2 : .consumerUsage)
        default:
            effective = encoding
        }
        switch effective {
        case .legacyBitmask: return v0 ?? (UInt8(usage & 0xFF), UInt8(usage >> 8))
        case .legacyV2: return v2 ?? (UInt8(usage & 0xFF), UInt8(usage >> 8))
        case .consumerUsage, .auto: return (UInt8(usage & 0xFF), UInt8(usage >> 8))
        }
    }

    public static func == (a: MediaKey, b: MediaKey) -> Bool { a.name == b.name && a.usage == b.usage }
    public func hash(into h: inout Hasher) { h.combine(name); h.combine(usage) }

    // Codable: tuples aren't Codable, so persist only the stable identity.
    private enum CodingKeys: String, CodingKey { case name, usage }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let name = try c.decode(String.self, forKey: .name)
        let usage = try c.decode(UInt16.self, forKey: .usage)
        self = MediaKey.all.first { $0.name == name } ?? MediaKey(name: name, usage: usage)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(usage, forKey: .usage)
    }
}

public enum MediaEncoding: String, Codable, CaseIterable, Sendable {
    case auto
    case legacyBitmask   // report id 0 style
    case legacyV2        // report id 2 style
    case consumerUsage   // report id 3 style — raw HID consumer usage

    public var displayName: String {
        switch self {
        case .auto: return "Auto (from report id)"
        case .legacyBitmask: return "Bitmask (id 0)"
        case .legacyV2: return "Bitmask (id 2)"
        case .consumerUsage: return "HID consumer usage (id 3)"
        }
    }
}

public extension MediaKey {
    /// The six keys the original tool supports, with all known encodings, plus
    /// extra consumer usages that only work with the `consumerUsage` encoding.
    static let all: [MediaKey] = [
        MediaKey(name: "Play / Pause",   usage: 0x00CD, v0: (64, 0),  v2: (0, 4)),
        MediaKey(name: "Next track",     usage: 0x00B5, v0: (0, 1),   v2: (0, 10)),
        MediaKey(name: "Previous track", usage: 0x00B6, v0: (128, 0), v2: (0, 11)),
        MediaKey(name: "Mute",           usage: 0x00E2, v0: (4, 0),   v2: (0, 1)),
        MediaKey(name: "Volume up",      usage: 0x00E9, v0: (2, 0),   v2: (64, 0)),
        MediaKey(name: "Volume down",    usage: 0x00EA, v0: (1, 0),   v2: (128, 0)),
        MediaKey(name: "Stop",           usage: 0x00B7),
        MediaKey(name: "Fast forward",   usage: 0x00B3),
        MediaKey(name: "Rewind",         usage: 0x00B4),
        MediaKey(name: "Eject",          usage: 0x00B8),
        MediaKey(name: "Brightness up",  usage: 0x006F),
        MediaKey(name: "Brightness down", usage: 0x0070),
        MediaKey(name: "Media player",   usage: 0x0183),
        MediaKey(name: "Mail",           usage: 0x018A),
        MediaKey(name: "Calculator",     usage: 0x0192),
        MediaKey(name: "File explorer",  usage: 0x0194),
        MediaKey(name: "Browser home",   usage: 0x0223),
        MediaKey(name: "Browser search", usage: 0x0221),
        MediaKey(name: "Browser back",   usage: 0x0224),
        MediaKey(name: "Browser forward", usage: 0x0225),
        MediaKey(name: "Browser refresh", usage: 0x0227),
    ]

    /// Keys that are safe to use with the two legacy bitmask encodings.
    static var legacySafe: [MediaKey] { Array(all.prefix(6)) }
}

// MARK: - LED

public enum LedMode: UInt8, Codable, CaseIterable, Identifiable, Sendable {
    case mode0 = 0, mode1, mode2, mode3, mode4, mode5
    public var id: UInt8 { rawValue }
    public var displayName: String { rawValue == 0 ? "Off / Mode 0" : "Mode \(rawValue)" }
}

public enum LedColor: UInt8, Codable, CaseIterable, Identifiable, Sendable {
    case random = 0x00
    case red = 0x10
    case orange = 0x20
    case yellow = 0x30
    case green = 0x40
    case cyan = 0x50
    case blue = 0x60
    case purple = 0x70

    public var id: UInt8 { rawValue }
    public var displayName: String {
        switch self {
        case .random: return "Random"
        case .red: return "Red"
        case .orange: return "Orange"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .cyan: return "Cyan"
        case .blue: return "Blue"
        case .purple: return "Purple"
        }
    }
}

// MARK: - Bindings

/// One recorded keystroke: a HID keyboard usage plus its modifier byte.
public struct KeyStroke: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var usage: UInt8
    public var modifiers: Modifier

    public init(usage: UInt8, modifiers: Modifier = .none) {
        self.usage = usage
        self.modifiers = modifiers
    }

    public var displayName: String {
        let base = HIDKeyboard.name(for: usage)
        let mods = modifiers.symbols
        if usage == 0 { return mods.isEmpty ? "—" : mods }
        return mods.isEmpty ? base : "\(mods)\(base)"
    }
}

/// What a single control does.
public enum ControlBinding: Codable, Hashable, Sendable {
    case unset
    case keys(sequence: [KeyStroke], delay: UInt16)
    case media(MediaKey)
    case mouse(button: MouseButton, modifiers: Modifier)

    public var summary: String {
        switch self {
        case .unset: return ""
        case .keys(let seq, _):
            if seq.isEmpty { return "(empty)" }
            return seq.map(\.displayName).joined(separator: " ")
        case .media(let m): return m.name
        case .mouse(let b, let mods):
            return mods.isEmpty ? b.displayName : "\(mods.symbols)\(b.displayName)"
        }
    }

    public var isSet: Bool {
        if case .unset = self { return false }
        return true
    }
}
