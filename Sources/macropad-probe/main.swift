import Foundation
import MacroPadCore

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
        let known = c.knownProtocol.map { " [known: \($0.rawValue)]" } ?? ""
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
        print("usage: macropad-probe send <legacy|extended> <reportId> <output|feature> <action> <layer> <hexUsage> [modByte]")
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
        print("usage: macropad-probe raw <reportId> <output|feature> <hex bytes...>"); exit(2)
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
    guard let best = transport.bestCandidate else { print("No device."); exit(1) }
    if case .failure(let e) = transport.open(best) {
        print("open failed: \(e.localizedDescription)"); exit(1)
    }
    print("Listening on \(best.displayName) — press keys on the pad. Ctrl-C to stop.")
    RunLoop.current.run()

default:
    print("commands: list | probe | send | raw | listen")
    exit(2)
}

extension Result {
    var isSuccess: Bool { if case .success = self { return true }; return false }
}
