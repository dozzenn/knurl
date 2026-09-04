import Foundation

/// One HID output report: a report id plus a fixed 64-byte payload.
public struct PadReport: Sendable, Equatable {
    public var reportId: UInt8
    public var data: [UInt8]

    public init(reportId: UInt8, data: [UInt8] = [UInt8](repeating: 0, count: 64)) {
        self.reportId = reportId
        var d = data
        if d.count < 64 { d.append(contentsOf: [UInt8](repeating: 0, count: 64 - d.count)) }
        self.data = Array(d.prefix(64))
    }

    /// Hex dump used by the log panel, e.g. `id 00 | FE 01 00 01 ...`.
    public func hexDump(limit: Int = 64) -> String {
        let body = data.prefix(limit).map { String(format: "%02X", $0) }.joined(separator: " ")
        return String(format: "id %02X | %@", reportId, body)
    }
}

/// Builds the byte sequences the keypad expects.
public protocol ReportComposer {
    var reportId: UInt8 { get }
    var mediaEncoding: MediaEncoding { get }

    func keys(action: InputAction, layer: UInt8, delay: UInt16, sequence: [KeyStroke]) -> [PadReport]
    func media(action: InputAction, layer: UInt8, key: MediaKey) -> [PadReport]
    func mouse(action: InputAction, layer: UInt8, button: MouseButton, modifiers: Modifier) -> [PadReport]
    func led(layer: UInt8, mode: LedMode, color: LedColor) -> [PadReport]
}

public extension ReportComposer {
    func reports(for binding: ControlBinding, action: InputAction, layer: UInt8) -> [PadReport] {
        switch binding {
        case .unset:
            return []
        case .keys(let seq, let delay):
            return keys(action: action, layer: layer, delay: delay, sequence: seq)
        case .media(let key):
            return media(action: action, layer: layer, key: key)
        case .mouse(let button, let mods):
            return mouse(action: action, layer: layer, button: button, modifiers: mods)
        }
    }
}

// MARK: - Extended protocol

/// Single-frame protocol used by most current devices.
/// Frame: `FE <action> <layer> <type> <delayLo> <delayHi> 00 00 00 <count>` then payload at offset 10.
public struct ExtendedComposer: ReportComposer {
    public let reportId: UInt8
    public let mediaEncoding: MediaEncoding

    public init(reportId: UInt8, mediaEncoding: MediaEncoding = .auto) {
        self.reportId = reportId
        self.mediaEncoding = mediaEncoding
    }

    private func frame(action: InputAction, layer: UInt8, delay: UInt16, type: KeyType, payload: [UInt8]) -> PadReport {
        var r = PadReport(reportId: reportId)
        r.data[0] = 0xFE
        r.data[1] = action.wireValue
        r.data[2] = layer
        r.data[3] = type.rawValue
        r.data[4] = UInt8(delay & 0xFF)
        r.data[5] = UInt8((delay >> 8) & 0xFF)
        r.data[6] = 0
        r.data[7] = 0
        r.data[8] = 0

        var count: UInt8 = 0
        for i in 0..<min(payload.count, r.data.count - 10) {
            r.data[10 + i] = payload[i]
            if payload[i] != 0 { count = UInt8((i >> 1) + 1) }
        }
        r.data[9] = count
        return r
    }

    public func keys(action: InputAction, layer: UInt8, delay: UInt16, sequence: [KeyStroke]) -> [PadReport] {
        var payload: [UInt8] = []
        for stroke in sequence {
            payload.append(stroke.modifiers.rawValue)
            payload.append(stroke.usage)
        }
        return [frame(action: action, layer: layer, delay: delay, type: .basic, payload: payload)]
    }

    public func media(action: InputAction, layer: UInt8, key: MediaKey) -> [PadReport] {
        let (b1, b2) = key.bytes(forReportId: reportId, encoding: mediaEncoding)
        return [frame(action: action, layer: layer, delay: 0, type: .multimedia, payload: [0, b1, b2, 0])]
    }

    public func mouse(action: InputAction, layer: UInt8, button: MouseButton, modifiers: Modifier) -> [PadReport] {
        let payload: [UInt8] = [button.buttons, 0, 0, button.scroll, modifiers.rawValue, 0]
        return [frame(action: action, layer: layer, delay: 0, type: .multimedia, payload: payload)]
    }

    public func led(layer: UInt8, mode: LedMode, color: LedColor) -> [PadReport] {
        let payload: [UInt8] = [layer, mode.rawValue | color.rawValue, 0, 0, 0, 0]
        // 176 (0xB0) is the LED opcode; it is not a real InputAction.
        var r = frame(action: .none, layer: layer, delay: 0, type: .led, payload: payload)
        r.data[1] = 176
        return [r]
    }
}

// MARK: - Legacy protocol

/// Multi-frame protocol used by the oldest devices.
/// Every change is bracketed by an optional layer-select frame and a flash-write frame.
public struct LegacyComposer: ReportComposer {
    public let reportId: UInt8
    public let mediaEncoding: MediaEncoding

    public init(reportId: UInt8, mediaEncoding: MediaEncoding = .auto) {
        self.reportId = reportId
        self.mediaEncoding = mediaEncoding
    }

    private func layerSelect(_ layer: UInt8) -> PadReport? {
        // Report id 0 firmware has no layers.
        guard reportId != 0 else { return nil }
        var r = PadReport(reportId: reportId)
        r.data[0] = 161
        r.data[1] = layer
        return r
    }

    private func writeFlash(led: Bool = false) -> PadReport {
        var r = PadReport(reportId: reportId)
        r.data[0] = 170
        r.data[1] = led ? 161 : 170
        return r
    }

    /// Type byte carries the layer in its high nibble on layered firmware.
    private func typeByte(_ type: KeyType, _ layer: UInt8) -> UInt8 {
        reportId == 0 ? type.rawValue : (type.rawValue | ((layer << 4) & 0xF0))
    }

    public func keys(action: InputAction, layer: UInt8, delay: UInt16, sequence: [KeyStroke]) -> [PadReport] {
        let seq = sequence.isEmpty ? [KeyStroke(usage: 0, modifiers: .none)] : sequence
        var out: [PadReport] = []
        if let sel = layerSelect(layer) { out.append(sel) }

        // Frame 0 announces the sequence, frames 1...n carry the strokes.
        for index in 0...seq.count {
            var r = PadReport(reportId: reportId)
            r.data[0] = action.wireValue
            r.data[1] = typeByte(.basic, layer)
            r.data[2] = UInt8(seq.count)
            r.data[3] = UInt8(index)
            if index == 0 {
                r.data[4] = seq[0].modifiers.rawValue
                r.data[5] = 0
            } else {
                r.data[4] = seq[index - 1].modifiers.rawValue
                r.data[5] = seq[index - 1].usage
            }
            out.append(r)
        }
        out.append(writeFlash())
        return out
    }

    public func media(action: InputAction, layer: UInt8, key: MediaKey) -> [PadReport] {
        var out: [PadReport] = []
        if let sel = layerSelect(layer) { out.append(sel) }
        let (b1, b2) = key.bytes(forReportId: reportId, encoding: mediaEncoding)
        var r = PadReport(reportId: reportId)
        r.data[0] = action.wireValue
        r.data[1] = typeByte(.multimedia, layer)
        r.data[2] = b1
        r.data[3] = b2
        out.append(r)
        out.append(writeFlash())
        return out
    }

    public func mouse(action: InputAction, layer: UInt8, button: MouseButton, modifiers: Modifier) -> [PadReport] {
        var out: [PadReport] = []
        if let sel = layerSelect(layer) { out.append(sel) }
        var r = PadReport(reportId: reportId)
        r.data[0] = action.wireValue
        r.data[1] = typeByte(.mouse, layer)
        r.data[2] = button.buttons
        r.data[3] = 0
        r.data[4] = 0
        r.data[5] = button.scroll
        r.data[6] = modifiers.rawValue
        out.append(r)
        out.append(writeFlash())
        return out
    }

    public func led(layer: UInt8, mode: LedMode, color: LedColor) -> [PadReport] {
        // Report id 0 firmware only knows modes 0-2.
        if mode.rawValue > 2 && reportId == 0 { return [] }
        var r = PadReport(reportId: reportId)
        r.data[0] = 176
        r.data[1] = KeyType.led.rawValue
        r.data[2] = mode.rawValue | color.rawValue
        return [r, writeFlash(led: true)]
    }
}

public enum ComposerFactory {
    public static func make(_ proto: PadProtocol, reportId: UInt8, mediaEncoding: MediaEncoding = .auto) -> ReportComposer {
        switch proto {
        case .legacy: return LegacyComposer(reportId: reportId, mediaEncoding: mediaEncoding)
        case .extended: return ExtendedComposer(reportId: reportId, mediaEncoding: mediaEncoding)
        case .webHub: return WebHubComposer(reportId: reportId, mediaEncoding: .consumerUsage)
        }
    }

    /// Probe frame used to discover which report id the firmware accepts.
    public static func versionProbe(reportId: UInt8) -> PadReport {
        PadReport(reportId: reportId)
    }
}

// MARK: - WebHub protocol (SDCX / Huali family)

/// The protocol spoken by the vendor's browser-based configurator at
/// huali-tech.com / sdcx-tech.com, used by SDINNOVATION-built pads.
///
/// Frames are 64 bytes on report id 0. Byte 0 is always 6 ("device data"),
/// byte 1 the sub-command. The key table is a flat array of 4-byte entries
/// `[type, code1, code2, code3]` addressed by a byte offset of `4 * keyIndex`.
///
/// Verified against an SDINNOVATION SIDE-KEYBOARD (6D7B:DCFA): a read of the
/// table returned `[32, 0x01, 0x04, 0]` for its three keys, which is the
/// Ctrl+A the hardware actually types, and a write followed by a read back
/// returned exactly the bytes written.
public struct WebHubComposer: ReportComposer {
    public let reportId: UInt8
    public let mediaEncoding: MediaEncoding

    public init(reportId: UInt8 = 0, mediaEncoding: MediaEncoding = .consumerUsage) {
        self.reportId = 0            // the descriptor declares no report ids
        self.mediaEncoding = mediaEncoding
    }

    /// Sub-commands on the byte-1 slot.
    enum Sub: UInt8 {
        case readConfig = 5
        case readKeys = 8
        case writeKeyBlock = 9
        case factoryReset = 15
        case writeKey = 16
        case selectProfile = 251
    }

    /// Entry types in the key table.
    public enum EntryType: UInt8 {
        case mouseMove = 0x11
        case disabled = 0x13
        case standard = 0x20
        case consumer = 0x30
        case macro = 0x60
        case openWebsite = 0x80
        case customCombination = 0xFF
    }

    /// Where a control lives in the flat key table.
    /// Buttons occupy 0…15; each knob owns three slots from 16 on.
    public static func keyIndex(for action: InputAction) -> Int? {
        switch action {
        case .none: return nil
        case .key1, .key2, .key3, .key4, .key5, .key6,
             .key7, .key8, .key9, .key10, .key11, .key12:
            return Int(action.rawValue) - 1
        default:
            let knob = (Int(action.rawValue) - 23) / 3          // 0-based knob number
            let part = (Int(action.rawValue) - 23) % 3          // 0 = left, 1 = push, 2 = right
            // The firmware orders a knob's slots press, then the two rotations.
            let slot: Int
            switch part {
            case 1: slot = 0        // push
            case 2: slot = 1        // right / clockwise
            default: slot = 2       // left / counter-clockwise
            }
            return 16 + knob * 3 + slot
        }
    }

    private func writeKey(index: Int, layer: UInt8, type: EntryType,
                          _ c1: UInt8, _ c2: UInt8, _ c3: UInt8) -> PadReport {
        let offset = 4 * index
        return PadReport(reportId: reportId, data: [
            6,
            Sub.writeKey.rawValue,
            7,                                  // payload length
            UInt8(offset & 0xFF),
            UInt8((offset >> 8) & 0xFF),
            0,
            layer,
            0,
            type.rawValue, c1, c2, c3,
        ])
    }

    /// The frame that asks the device to describe itself. Read-only.
    public static func deviceInfoRequest() -> PadReport {
        PadReport(reportId: 0, data: [6, Sub.readConfig.rawValue])
    }

    /// The frame that reads one 56-byte block of the key table. Read-only.
    public static func keyTableRequest(blockOffset: Int, layer: UInt8) -> PadReport {
        PadReport(reportId: 0, data: [
            6, Sub.readKeys.rawValue, 58,
            UInt8(blockOffset & 0xFF), UInt8((blockOffset >> 8) & 0xFF),
            0, layer,
        ])
    }

    public func keys(action: InputAction, layer: UInt8, delay: UInt16, sequence: [KeyStroke]) -> [PadReport] {
        guard let index = Self.keyIndex(for: action) else { return [] }
        guard let stroke = sequence.first else {
            return [writeKey(index: index, layer: layer, type: .disabled, 0, 0, 0)]
        }
        // A table entry holds one keystroke; longer sequences need the separate
        // macro table, which this build does not write yet.
        return [writeKey(index: index, layer: layer, type: .standard,
                         stroke.modifiers.rawValue, stroke.usage, 0)]
    }

    public func media(action: InputAction, layer: UInt8, key: MediaKey) -> [PadReport] {
        guard let index = Self.keyIndex(for: action) else { return [] }
        return [writeKey(index: index, layer: layer, type: .consumer,
                         UInt8(key.usage & 0xFF), UInt8(key.usage >> 8), 0)]
    }

    public func mouse(action: InputAction, layer: UInt8, button: MouseButton, modifiers: Modifier) -> [PadReport] {
        // The mouse entry encoding for this family has not been established, and
        // writing a guess would put junk in the key table.
        []
    }

    public func led(layer: UInt8, mode: LedMode, color: LedColor) -> [PadReport] {
        // Backlight uses a separate command set that is not worked out yet.
        []
    }

    /// Clears a control back to "does nothing".
    public func clear(action: InputAction, layer: UInt8) -> [PadReport] {
        guard let index = Self.keyIndex(for: action) else { return [] }
        return [writeKey(index: index, layer: layer, type: .disabled, 0, 0, 0)]
    }

    /// How many keystrokes one table entry can hold.
    public static let maxKeystrokes = 1
}
