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
        }
    }

    /// Probe frame used to discover which report id the firmware accepts.
    public static func versionProbe(reportId: UInt8) -> PadReport {
        PadReport(reportId: reportId)
    }
}
