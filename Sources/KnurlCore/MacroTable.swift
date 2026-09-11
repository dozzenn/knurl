import Foundation

/// One instruction inside a macro: press or release a code, after a delay.
public struct MacroStep: Equatable, Sendable {
    /// Which namespace `code` belongs to, carried in the low six bits of the
    /// flags byte.
    ///
    /// Keyboard is 3, not 1. The vendor's reader treats anything that is not
    /// 2, 4 or 5 as a keyboard step, so a wrong value still decodes as one and
    /// reads back looking correct — while the firmware, which switches on the
    /// value, does nothing with it.
    public enum Kind: UInt8, Sendable {
        case keyboard = 3
        case mouse = 2
        case scrollVertical = 4
        case scrollHorizontal = 5
    }

    public enum Action: Sendable { case down, up }

    /// Milliseconds to wait before the step runs.
    public var delay: UInt16
    public var kind: Kind
    public var action: Action
    public var code: UInt8

    public init(delay: UInt16 = 8, kind: Kind = .keyboard, action: Action, code: UInt8) {
        self.delay = delay
        self.kind = kind
        self.action = action
        self.code = code
    }
}

/// The keypad's macro storage.
///
/// 4096 bytes: sixteen 16-bit pointers, then the steps they point at. Each step
/// is four bytes — `delayLo delayHi flags code` — where the flags byte carries
/// the kind in its low six bits, the press/release in bit 6, and the end of the
/// macro in bit 7.
///
/// Read out of the vendor's own configurator; its decoder is what this mirrors.
public enum MacroTable {
    public static let slotCount = 16
    public static let size = 4096
    /// 64 bytes, not two per slot: the vendor's encoder reserves the whole
    /// first block and starts step data after it.
    private static let headerSize = 64
    /// Written into the pointer of a slot that holds nothing. The firmware's
    /// reader treats anything past the table as "no macro".
    private static let emptySlot: UInt16 = 0xFFFF

    /// HID usages of the modifier keys, which a macro presses like any other.
    static func modifierUsages(_ modifiers: Modifier) -> [UInt8] {
        var out: [UInt8] = []
        if modifiers.contains(.leftCtrl) { out.append(0xE0) }
        if modifiers.contains(.leftShift) { out.append(0xE1) }
        if modifiers.contains(.leftAlt) { out.append(0xE2) }
        if modifiers.contains(.leftGui) { out.append(0xE3) }
        if modifiers.contains(.rightCtrl) { out.append(0xE4) }
        if modifiers.contains(.rightShift) { out.append(0xE5) }
        if modifiers.contains(.rightAlt) { out.append(0xE6) }
        if modifiers.contains(.rightGui) { out.append(0xE7) }
        return out
    }

    /// Turns a recorded shortcut into the presses and releases that produce it.
    /// Modifiers go down before the key and come up after it, in reverse, which
    /// is what a keyboard does and what applications expect.
    public static func steps(for stroke: KeyStroke, gap: UInt16 = 8) -> [MacroStep] {
        let modifiers = modifierUsages(stroke.modifiers)
        var out: [MacroStep] = modifiers.map { MacroStep(delay: gap, action: .down, code: $0) }
        if stroke.usage != 0 {
            out.append(MacroStep(delay: gap, action: .down, code: stroke.usage))
            out.append(MacroStep(delay: gap, action: .up, code: stroke.usage))
        }
        out.append(contentsOf: modifiers.reversed().map {
            MacroStep(delay: gap, action: .up, code: $0)
        })
        return out
    }

    public static func steps(for sequence: [KeyStroke], gap: UInt16 = 8) -> [MacroStep] {
        sequence.flatMap { steps(for: $0, gap: gap) }
    }

    /// How many steps the table can hold in total.
    public static var stepCapacity: Int { (size - headerSize) / 4 }

    /// Packs macros into the 4096-byte blob the device stores.
    ///
    /// Returns nil if the macros do not fit, rather than writing a truncated
    /// table that would leave a key running off the end of another macro.
    public static func encode(_ macros: [Int: [MacroStep]]) -> [UInt8]? {
        var blob = [UInt8](repeating: 0, count: size)
        var cursor = headerSize

        for slot in 0..<slotCount {
            let pointer: UInt16
            if let steps = macros[slot], !steps.isEmpty {
                // A pointer whose low byte is zero reads as "no macro", so step
                // over such an offset rather than writing one.
                if cursor & 0xFF == 0 { cursor += 4 }
                guard cursor + steps.count * 4 <= size else { return nil }
                pointer = UInt16(cursor)
                for (index, step) in steps.enumerated() {
                    var flags = step.kind.rawValue
                    if step.action == .down { flags |= 0x40 }
                    if index == steps.count - 1 { flags |= 0x80 }
                    blob[cursor] = UInt8(step.delay & 0xFF)
                    blob[cursor + 1] = UInt8((step.delay >> 8) & 0xFF)
                    blob[cursor + 2] = flags
                    blob[cursor + 3] = step.code
                    cursor += 4
                }
            } else {
                pointer = emptySlot
            }
            blob[slot * 2] = UInt8(pointer & 0xFF)
            blob[slot * 2 + 1] = UInt8((pointer >> 8) & 0xFF)
        }
        return blob
    }

    /// Reads a blob back, for checking what the device is actually holding.
    public static func decode(_ blob: [UInt8]) -> [Int: [MacroStep]] {
        guard blob.count >= headerSize else { return [:] }
        var out: [Int: [MacroStep]] = [:]

        for slot in 0..<slotCount {
            let pointer = Int(blob[slot * 2]) | (Int(blob[slot * 2 + 1]) << 8)
            guard pointer >= headerSize, pointer + 4 <= blob.count else { continue }

            var cursor = pointer
            var steps: [MacroStep] = []
            while cursor + 4 <= blob.count && steps.count <= stepCapacity {
                let delay = UInt16(blob[cursor]) | (UInt16(blob[cursor + 1]) << 8)
                let flags = blob[cursor + 2]
                // Mirrors the vendor's reader: only 2, 4 and 5 mean anything
                // else; everything remaining is a keyboard step.
                let kind = MacroStep.Kind(rawValue: flags & 0x3F) ?? .keyboard
                let action: MacroStep.Action = (flags >> 6) & 1 == 1 ? .down : .up
                steps.append(MacroStep(delay: delay, kind: kind, action: action,
                                       code: blob[cursor + 3]))
                cursor += 4
                if (flags >> 7) & 1 == 1 || flags == 0 { break }
            }
            if !steps.isEmpty { out[slot] = steps }
        }
        return out
    }
}
