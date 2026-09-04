import Foundation
import KnurlCore
import IOKit.hid

// Small diagnostic CLI: lists candidate configuration interfaces and can send
// a single frame so the wire protocol can be verified against real hardware.

let args = Array(CommandLine.arguments.dropFirst())
let transport = PadTransport()
transport.onLog = { entry in
    print("  \(entry.outgoing ? "→" : "←") \(entry.text)")
}
transport.startMonitoring()
// Give the HID manager a moment to enumerate.
RunLoop.current.run(until: Date().addingTimeInterval(0.4))
transport.refresh()

func printCandidates() {
    print("HID configuration-interface candidates:")
    for c in transport.candidates {
        let mark = c.id == transport.bestCandidate?.id ? "*" : " "
        let known = c.knownProtocol.map { " [protocol: \($0.rawValue)]" }
            ?? (c.isKnownHardware ? " [known hardware, protocol unverified]" : "")
        print(" \(mark) \(c.displayName)\(known)")
        print("     \(c.detail) · mfr \"\(c.manufacturer)\"")
        print("     id \(c.id)")
    }
    if transport.candidates.isEmpty { print("  (none)") }
}

guard let command = args.first else {
    printCandidates()
    exit(0)
}

switch command {
case "list":
    printCandidates()

case "probe":
    printCandidates()
    guard let best = transport.bestCandidate else {
        print("No candidate device found."); exit(1)
    }
    print("\nOpening \(best.displayName) …")
    if case .failure(let e) = transport.open(best) {
        print("open failed: \(e.localizedDescription)"); exit(1)
    }
    for channel in ReportChannel.allCases {
        print("\n\(channel.displayName):")
        for id: UInt8 in [0, 2, 3] {
            let r = ComposerFactory.versionProbe(reportId: id)
            let res = transport.write(r, channel: channel)
            print("   report id \(id): \(res.isSuccess ? "accepted" : "rejected")")
        }
    }
    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    transport.close()

case "send":
    // send <proto:legacy|extended> <reportId> <channel:output|feature> <action> <layer> <hidUsage> [modifiers]
    guard args.count >= 7,
          let proto = PadProtocol(rawValue: args[1]),
          let reportId = UInt8(args[2]),
          let channel = ReportChannel(rawValue: args[3]),
          let actionRaw = UInt8(args[4]), let action = InputAction(rawValue: actionRaw),
          let layer = UInt8(args[5]),
          let usage = UInt8(args[6], radix: 16) else {
        print("usage: knurl-probe send <legacy|extended> <reportId> <output|feature> <action> <layer> <hexUsage> [modByte]")
        exit(2)
    }
    let mods = Modifier(rawValue: args.count > 7 ? (UInt8(args[7]) ?? 0) : 0)

    guard let best = transport.bestCandidate else { print("No device."); exit(1) }
    if case .failure(let e) = transport.open(best) {
        print("open failed: \(e.localizedDescription)"); exit(1)
    }
    let composer = ComposerFactory.make(proto, reportId: reportId)
    let reports = composer.keys(action: action, layer: layer, delay: 0,
                                sequence: [KeyStroke(usage: usage, modifiers: mods)])
    print("Sending \(reports.count) report(s) to \(best.displayName) via \(channel.displayName)")
    for r in reports {
        _ = transport.write(r, channel: channel)
        usleep(20_000)
    }
    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    transport.close()

case "raw":
    // raw <reportId> <channel> <hex bytes...>
    guard args.count >= 4, let reportId = UInt8(args[1]),
          let channel = ReportChannel(rawValue: args[2]) else {
        print("usage: knurl-probe raw <reportId> <output|feature> <hex bytes...>"); exit(2)
    }
    let bytes = args.dropFirst(3).compactMap { UInt8($0, radix: 16) }
    guard let best = transport.bestCandidate else { print("No device."); exit(1) }
    if case .failure(let e) = transport.open(best) {
        print("open failed: \(e.localizedDescription)"); exit(1)
    }
    _ = transport.write(PadReport(reportId: reportId, data: bytes), channel: channel)
    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    transport.close()

case "listen":
    let seconds = args.count > 1 ? (Double(args[1]) ?? 30) : 30
    guard let best = transport.bestCandidate else { print("No device."); exit(1) }
    if case .failure(let e) = transport.open(best) {
        print("open failed: \(e.localizedDescription)"); exit(1)
    }
    print("Listening on \(best.displayName) for \(Int(seconds))s — press keys on the pad.")
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    transport.close()
    print("done")

case "interfaces":
    // Every HID interface, so a pad's keyboard endpoints can be found too.
    for c in transport.allInterfaces {
        print(" \(c.displayName)")
        print("     \(c.detail) · in \(c.maxInputReportSize) B · mfr \"\(c.manufacturer)\"")
        print("     id \(c.id)")
    }

case "info":
    // Pure read: ask the device to describe itself. Frame is [6, 5] — the
    // "device data" command followed by the get-config sub-command.
    guard let best = transport.bestCandidate else { print("No device."); exit(1) }
    var reply: [UInt8]? = nil
    transport.onLog = { entry in
        print("  \(entry.outgoing ? "→" : "←") \(entry.text)")
        if !entry.outgoing, reply == nil {
            reply = entry.text.split(separator: "|").last?
                .split(separator: " ").compactMap { UInt8($0, radix: 16) }
        }
    }
    if case .failure(let e) = transport.open(best) {
        print("open failed: \(e.localizedDescription)"); exit(1)
    }
    _ = transport.write(PadReport(reportId: 0, data: [6, 5]), channel: .output)
    RunLoop.current.run(until: Date().addingTimeInterval(1.5))
    transport.close()

    if let r = reply, r.count >= 43 {
        func u16(_ a: UInt8, _ b: UInt8) -> Int { Int(a) | (Int(b) << 8) }
        let l = Array(r[5..<43])
        print("")
        print("  length      \(r[2])")
        print("  version     \(String(format: "%04X", u16(l[0], l[1])))")
        print("  pid         \(String(format: "%04X", u16(l[2], l[3])))")
        print("  firmware    \(String(format: "%04X", u16(l[4], l[5])))")
        print("  workMode    \(l[6])   linkStatus \(l[7])")
        print("  battery     \(l[8])   charging \(l[9])")
        print("  profiles    \(l[10])  current \(l[11])")
        print("  layers      \(l[12])  current \(l[13])")
        let serial = r[21..<43].compactMap { $0 == 0 ? nil : Character(UnicodeScalar($0)) }
        print("  serial      \(String(serial))")
    } else {
        print("\n  no usable reply")
    }

case "readkeys":
    // Pure read of the key table: [6, 8, 58, offLo, offHi, 0, layer].
    // The reply carries 4-byte entries [type, code1, code2, code3] from index 8.
    let layer = args.count > 1 ? (UInt8(args[1]) ?? 0) : 0
    guard let best = transport.bestCandidate else { print("No device."); exit(1) }
    var replies: [[UInt8]] = []
    transport.onLog = { entry in
        guard !entry.outgoing else { return }
        let bytes = entry.text.split(separator: "|").last?
            .split(separator: " ").compactMap { UInt8($0, radix: 16) } ?? []
        replies.append(bytes)
    }
    if case .failure(let e) = transport.open(best) {
        print("open failed: \(e.localizedDescription)"); exit(1)
    }
    print("layer \(layer)")
    for block in 0..<3 {
        let off = block * 56
        let frame: [UInt8] = [6, 8, 58, UInt8(off & 0xFF), UInt8((off >> 8) & 0xFF), 0, layer]
        _ = transport.write(PadReport(reportId: 0, data: frame), channel: .output)
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
    }
    transport.close()

    var table: [UInt8] = []
    for r in replies where r.count > 8 { table.append(contentsOf: r[8...]) }
    print("")
    for i in 0..<min(24, table.count / 4) {
        let e = Array(table[(i * 4)..<(i * 4 + 4)])
        guard e != [0, 0, 0, 0] else { continue }
        let typeName: String
        switch e[0] {
        case 17: typeName = "MouseMove"
        case 19: typeName = "Disabled"
        case 32: typeName = "Standard"
        case 96: typeName = "Macro"
        case 128: typeName = "OpenWebsite"
        case 255: typeName = "CustomCombination"
        default: typeName = "type \(e[0])"
        }
        print(String(format: "  index %2d  type %-18@  code1 %02X  code2 %02X  code3 %02X",
                     i, typeName as NSString, e[1], e[2], e[3]))
    }

case "setkey":
    // setkey <index> <layer> <typeDec> <c1Hex> <c2Hex> <c3Hex>
    // Frame: [6, 16, 7, offLo, offHi, 0, layer, 0, type, c1, c2, c3], off = 4*index.
    guard args.count >= 7,
          let index = Int(args[1]), let layer = UInt8(args[2]),
          let type = UInt8(args[3]),
          let c1 = UInt8(args[4], radix: 16),
          let c2 = UInt8(args[5], radix: 16),
          let c3 = UInt8(args[6], radix: 16) else {
        print("usage: knurl-probe setkey <index> <layer> <type> <c1hex> <c2hex> <c3hex>")
        exit(2)
    }
    guard let best = transport.bestCandidate else { print("No device."); exit(1) }
    if case .failure(let e) = transport.open(best) {
        print("open failed: \(e.localizedDescription)"); exit(1)
    }
    let off = 4 * index
    let frame: [UInt8] = [6, 16, 7,
                          UInt8(off & 0xFF), UInt8((off >> 8) & 0xFF),
                          0, layer, 0, type, c1, c2, c3]
    _ = transport.write(PadReport(reportId: 0, data: frame), channel: .output)
    RunLoop.current.run(until: Date().addingTimeInterval(0.6))
    transport.close()

case "light":
    // Pure read of the backlight state: [6, 10]; the reply carries 11 bytes
    // from index 5.
    guard let best = transport.bestCandidate else { print("No device."); exit(1) }
    var reply: [UInt8]? = nil
    transport.onLog = { entry in
        print("  \(entry.outgoing ? "→" : "←") \(entry.text)")
        if !entry.outgoing, reply == nil {
            reply = entry.text.split(separator: "|").last?
                .split(separator: " ").compactMap { UInt8($0, radix: 16) }
        }
    }
    if case .failure(let e) = transport.open(best) {
        print("open failed: \(e.localizedDescription)"); exit(1)
    }
    _ = transport.write(PadReport(reportId: 0, data: [6, 10]), channel: .output)
    RunLoop.current.run(until: Date().addingTimeInterval(1.2))
    transport.close()

    if let r = reply, r.count >= 16 {
        let e = Array(r[5..<16])
        print("")
        print("  type              \(e[0])")
        print("  mode              \(e[2])")
        print("  brightness        \(e[3])")
        print("  speed             \(e[4])")
        print("  direction         \(e[5])")
        print("  color             \(e[6])")
        print("  singleColorIndex  \(e[7])")
        print("  h/s/v (raw)       \(e[8]) / \(e[9]) / \(e[10])")
    } else {
        print("\n  no usable reply")
    }

case "setlight":
    // setlight <type> <mode> <brightness> <speed> <direction> <color> <h> <s> <v>
    guard args.count >= 10, let vals = try? args[1...9].map({ (a: String) -> UInt8 in
        guard let v = UInt8(a) else { throw NSError(domain: "", code: 0) }; return v
    }) else {
        print("usage: setlight <type> <mode> <brightness> <speed> <direction> <color> <h> <s> <v>")
        exit(2)
    }
    guard let best = transport.bestCandidate else { print("No device."); exit(1) }
    if case .failure(let e) = transport.open(best) {
        print("open failed: \(e.localizedDescription)"); exit(1)
    }
    let a: [UInt8] = [vals[0], 0, vals[1], vals[2], vals[3], vals[4], vals[5], 0,
                      vals[6], vals[7], vals[8]]
    _ = transport.write(PadReport(reportId: 0, data: [6, 11, UInt8(a.count), 0, 0] + a),
                        channel: .output)
    RunLoop.current.run(until: Date().addingTimeInterval(0.6))
    transport.close()

case "layout":
    // Which physical key types a given character on the layout in use.
    let wanted = args.count > 1 ? Array(args[1]) : Array("+-=0123456789zZ")
    for character in wanted {
        if let r = LayoutResolver.resolve(character) {
            print(String(format: "  '%@' → HID 0x%02X  %@%@",
                         String(character), r.usage,
                         HIDKeyboard.name(for: r.usage),
                         r.needsShift ? "  (needs shift)" : ""))
        } else {
            print("  '\(character)' → not on this layout")
        }
    }

case "access":
    // macOS gates input reports from keyboard-usage devices behind Input
    // Monitoring. Ask the system rather than guessing from silence.
    let state = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
    switch state {
    case kIOHIDAccessTypeGranted: print("Input Monitoring: GRANTED")
    case kIOHIDAccessTypeDenied:  print("Input Monitoring: DENIED")
    default:                      print("Input Monitoring: NOT DETERMINED")
    }
    if args.count > 1 && args[1] == "request" {
        print("requesting… (a system prompt may appear)")
        let ok = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        print("request returned \(ok)")
    }

case "sniff":
    // sniff <vidHex> <pidHex> [seconds] — opens EVERY interface of that device
    // and prints input reports, so we can see exactly what a pad key emits.
    guard args.count >= 3,
          let vid = UInt16(args[1], radix: 16), let pid = UInt16(args[2], radix: 16) else {
        print("usage: knurl-probe sniff <vidHex> <pidHex> [seconds]"); exit(2)
    }
    let seconds = args.count > 3 ? (Double(args[3]) ?? 30) : 30
    let targets = transport.allInterfaces.filter { $0.vendorId == vid && $0.productId == pid }
    guard !targets.isEmpty else { print("No interface for \(args[1]):\(args[2])"); exit(1) }

    // One transport per interface: each holds a single open device.
    var sniffers: [PadTransport] = []
    for target in targets {
        let t = PadTransport()
        t.startMonitoring()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        guard let match = t.allInterfaces.first(where: { $0.id == target.id }) else { continue }
        t.onLog = { entry in
            guard !entry.outgoing else { return }
            print("  iface \(target.interfaceNumber.map(String.init) ?? "?") (usage \(String(format: "%04X:%04X", target.usagePage, target.usage)))  \(entry.text)")
        }
        switch t.open(match) {
        case .success:
            print("opened iface \(target.interfaceNumber.map(String.init) ?? "?") — usage \(String(format: "%04X:%04X", target.usagePage, target.usage))")
            sniffers.append(t)
        case .failure(let e):
            print("iface \(target.interfaceNumber.map(String.init) ?? "?"): \(e.localizedDescription)")
        }
    }
    guard !sniffers.isEmpty else { print("Nothing opened."); exit(1) }
    print("\nPress keys on the pad — listening \(Int(seconds))s…")
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    for t in sniffers { t.close() }
    print("done")

default:
    print("commands: list | interfaces | probe | send | raw | listen | sniff")
    exit(2)
}

extension Result {
    var isSuccess: Bool { if case .success = self { return true }; return false }
}
