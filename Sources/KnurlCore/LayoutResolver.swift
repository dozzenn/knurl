import Carbon.HIToolbox
import Foundation

/// Finds which physical key produces a given character on the keyboard layout
/// the user actually has.
///
/// A keypad sends HID usages, which are positions, not characters. macOS then
/// reads that position through the active layout — so a template written as
/// "the key next to zero" lands on a different character on a Turkish keyboard
/// than on a US one. Templates therefore ask for a character, and this works
/// out the position that produces it here.
public enum LayoutResolver {

    public struct Resolved {
        public let usage: UInt8
        /// True when the character needs shift on this layout.
        public let needsShift: Bool
    }

    private static var cache: [Character: Resolved] = [:]
    private static var cachedLayoutName: String?

    /// The position that types `character` on the current layout, if any.
    public static func resolve(_ character: Character) -> Resolved? {
        rebuildIfLayoutChanged()
        return cache[character]
    }

    private static func rebuildIfLayoutChanged() {
        let name = currentLayoutName()
        guard name != cachedLayoutName else { return }
        cachedLayoutName = name
        cache = buildMap()
    }

    private static func currentLayoutName() -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    /// Walks every virtual key code and asks the layout what it types, plain
    /// and shifted, then keeps the first key that produces each character.
    private static func buildMap() -> [Character: Resolved] {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let rawData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return [:]
        }
        let data = Unmanaged<CFData>.fromOpaque(rawData).takeUnretainedValue() as Data

        var map: [Character: Resolved] = [:]
        for code in UInt16(0)...UInt16(127) {
            guard let usage = HIDKeyboard.virtualKeyToUsage[code] else { continue }
            for shifted in [false, true] {
                guard let text = translate(code: code, shifted: shifted, layout: data),
                      text.count == 1, let character = text.first,
                      !character.isWhitespace else { continue }
                if map[character] == nil {
                    map[character] = Resolved(usage: usage, needsShift: shifted)
                }
            }
        }
        return map
    }

    private static func translate(code: UInt16, shifted: Bool, layout: Data) -> String? {
        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let modifiers: UInt32 = shifted ? UInt32(shiftKey >> 8) : 0

        let status = layout.withUnsafeBytes { buffer -> OSStatus in
            guard let base = buffer.baseAddress else { return -1 }
            return UCKeyTranslate(
                base.assumingMemoryBound(to: UCKeyboardLayout.self),
                code,
                UInt16(kUCKeyActionDown),
                modifiers,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}
