import Foundation
import IOKit
import IOKit.hid

/// A HID interface that could be a keypad configuration channel.
public struct PadCandidate: Identifiable, Hashable {
    public let id: String
    public let vendorId: UInt16
    public let productId: UInt16
    public let product: String
    public let manufacturer: String
    public let interfaceNumber: Int?
    public let usagePage: UInt32
    public let usage: UInt32
    public let maxOutputReportSize: Int
    public let maxFeatureReportSize: Int
    public let maxInputReportSize: Int
    /// True when this looks like the vendor-defined configuration interface
    /// rather than the plain keyboard/mouse interfaces the pad also exposes.
    public let isVendorInterface: Bool
    /// Set when the interface matches an entry in the known-device table.
    public let knownProtocol: PadProtocol?
    /// True when the same physical device also exposes a plain keyboard interface,
    /// which is what a macro pad looks like and a trackpad or display does not.
    public var hasKeyboardSibling: Bool = false

    /// How likely this interface is to be a macro pad's configuration channel.
    public var score: Int {
        var s = 0
        if knownProtocol != nil { s += 100 }
        if isVendorInterface { s += 20 }
        if maxOutputReportSize >= 64 { s += 20 }
        if hasKeyboardSibling { s += 30 }
        if PadCandidate.ignoredVendors.contains(vendorId) { s -= 200 }
        return s
    }

    /// Vendors whose vendor-defined interfaces are never macro pads, so they do
    /// not clutter the picker (Apple's own keyboards, trackpads and displays).
    public static let ignoredVendors: Set<UInt16> = [0x004C, 0x05AC]

    public var isLikelyPad: Bool { score >= 60 }

    public var displayName: String {
        let name = product.isEmpty ? "HID device" : product
        let iface = interfaceNumber.map { " · iface \($0)" } ?? ""
        return String(format: "%@ (%04X:%04X)%@", name, vendorId, productId, iface)
    }

    public var detail: String {
        String(format: "usage %04X:%04X · out %d B · feature %d B",
               usagePage, usage, maxOutputReportSize, maxFeatureReportSize)
    }
}

/// How a report is pushed to the device.
public enum ReportChannel: String, CaseIterable, Codable, Sendable {
    case output
    case feature

    public var displayName: String { self == .output ? "Output report" : "Feature report" }

    var iokitType: IOHIDReportType { self == .output ? kIOHIDReportTypeOutput : kIOHIDReportTypeFeature }
}

public struct HIDLogEntry: Identifiable {
    public let id = UUID()
    public let date = Date()
    public let outgoing: Bool
    public let text: String
    public let ok: Bool
}

/// Discovers keypads, opens the configuration interface and writes reports to it.
public final class PadTransport {

    public private(set) var candidates: [PadCandidate] = []
    public private(set) var openedCandidate: PadCandidate?

    /// Called on the main run loop whenever the device list changes.
    public var onDeviceListChanged: (() -> Void)?
    /// Called on the main run loop for every report written or received.
    public var onLog: ((HIDLogEntry) -> Void)?

    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var deviceMap: [String: IOHIDDevice] = [:]
    private var inputBuffer: UnsafeMutablePointer<UInt8>?
    private var inputBufferSize = 0

    public init() {}

    public var isOpen: Bool { device != nil }

    // MARK: - Known devices

    /// VID:PID → protocol, from the original project's `config.txt`, plus the
    /// interface the configuration channel lives on (`mi_00` / `mi_01`).
    public struct KnownDevice {
        public let vendorId: UInt16
        public let productId: UInt16
        public let interfaceNumber: Int
        public let proto: PadProtocol
        public init(_ vid: UInt16, _ pid: UInt16, _ iface: Int, _ proto: PadProtocol) {
            vendorId = vid; productId = pid; interfaceNumber = iface; self.proto = proto
        }
    }

    public static let knownDevices: [KnownDevice] = [
        KnownDevice(0x1189, 0x8840, 1, .extended),
        KnownDevice(0x1189, 0x8890, 1, .legacy),
        KnownDevice(0x1189, 0x8830, 0, .extended),
        KnownDevice(0x1189, 0x8831, 0, .extended),
        KnownDevice(0x1189, 0x8832, 0, .extended),
        KnownDevice(0x1189, 0x8833, 0, .extended),
        KnownDevice(0x1189, 0x8810, 0, .extended),
        // SDINNOVATION "SIDE-KEYBOARD" and relatives: report id 0, 64-byte reports.
        KnownDevice(0x6D7B, 0xDCFA, 2, .extended),
    ]

    // MARK: - Discovery

    public func startMonitoring() {
        guard manager == nil else { return }
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(mgr, nil)

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        let cb: IOHIDDeviceCallback = { context, _, _, _ in
            guard let context else { return }
            let me = Unmanaged<PadTransport>.fromOpaque(context).takeUnretainedValue()
            me.refresh()
        }
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, cb, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, cb, ctx)
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = mgr
        refresh()
    }

    public func refresh() {
        guard let manager else { return }
        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return }

        var all: [(PadCandidate, IOHIDDevice)] = []
        // Physical devices that expose a keyboard interface, keyed by vid/pid/location.
        var keyboardOwners = Set<String>()

        for dev in set {
            guard let c = Self.describe(dev) else { continue }
            if c.usagePage == 0x01 && (c.usage == 0x06 || c.usage == 0x07) {
                keyboardOwners.insert(Self.physicalKey(c))
            }
            all.append((c, dev))
        }

        var found: [PadCandidate] = []
        var map: [String: IOHIDDevice] = [:]
        for (var c, dev) in all {
            c.hasKeyboardSibling = keyboardOwners.contains(Self.physicalKey(c))
            // Only interfaces that could carry a 64-byte configuration frame.
            guard c.maxOutputReportSize >= 64 || c.maxFeatureReportSize >= 64 else { continue }
            guard c.isVendorInterface || c.knownProtocol != nil else { continue }
            found.append(c)
            map[c.id] = dev
        }

        found.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.displayName < rhs.displayName
        }

        candidates = found
        deviceMap = map

        // Drop a stale handle if the open device disappeared.
        if let opened = openedCandidate, map[opened.id] == nil {
            close()
        }
        onDeviceListChanged?()
    }

    /// Identifies the physical USB device an interface belongs to.
    private static func physicalKey(_ c: PadCandidate) -> String {
        "\(c.vendorId)-\(c.productId)-\(c.id.split(separator: "-").dropFirst(2).first ?? "")"
    }

    private static func intProp(_ dev: IOHIDDevice, _ key: String) -> Int? {
        (IOHIDDeviceGetProperty(dev, key as CFString) as? NSNumber)?.intValue
    }

    private static func stringProp(_ dev: IOHIDDevice, _ key: String) -> String {
        (IOHIDDeviceGetProperty(dev, key as CFString) as? String) ?? ""
    }

    static func describe(_ dev: IOHIDDevice) -> PadCandidate? {
        guard let vid = intProp(dev, kIOHIDVendorIDKey), let pid = intProp(dev, kIOHIDProductIDKey) else {
            return nil
        }
        let usagePage = UInt32(intProp(dev, kIOHIDPrimaryUsagePageKey) ?? 0)
        let usage = UInt32(intProp(dev, kIOHIDPrimaryUsageKey) ?? 0)
        let iface = interfaceNumber(dev)
        let location = intProp(dev, kIOHIDLocationIDKey) ?? 0

        let known = knownDevices.first {
            $0.vendorId == UInt16(vid) && $0.productId == UInt16(pid)
                && (iface == nil || $0.interfaceNumber == iface)
        }

        return PadCandidate(
            id: "\(vid)-\(pid)-\(location)-\(iface.map(String.init) ?? "x")-\(usagePage)-\(usage)",
            vendorId: UInt16(vid),
            productId: UInt16(pid),
            product: stringProp(dev, kIOHIDProductKey),
            manufacturer: stringProp(dev, kIOHIDManufacturerKey),
            interfaceNumber: iface,
            usagePage: usagePage,
            usage: usage,
            maxOutputReportSize: intProp(dev, kIOHIDMaxOutputReportSizeKey) ?? 0,
            maxFeatureReportSize: intProp(dev, kIOHIDMaxFeatureReportSizeKey) ?? 0,
            maxInputReportSize: intProp(dev, kIOHIDMaxInputReportSizeKey) ?? 0,
            isVendorInterface: usagePage >= 0xFF00,
            knownProtocol: known?.proto
        )
    }

    /// The USB `bInterfaceNumber` this HID device hangs off, if it is a USB device.
    /// This is the macOS equivalent of the `mi_00` / `mi_01` path fragment the
    /// original tool matches on Windows.
    private static func interfaceNumber(_ dev: IOHIDDevice) -> Int? {
        let service = IOHIDDeviceGetService(dev)
        guard service != IO_OBJECT_NULL else { return nil }

        var depth = 0
        var current = service
        IOObjectRetain(current)
        defer { IOObjectRelease(current) }

        while depth < 8 {
            if let n = IORegistryEntryCreateCFProperty(current, "bInterfaceNumber" as CFString,
                                                       kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? NSNumber {
                return n.intValue
            }
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS,
                  parent != IO_OBJECT_NULL else { break }
            IOObjectRelease(current)
            current = parent
            depth += 1
        }
        return nil
    }

    /// Interfaces that actually look like a macro pad, best first.
    public var likelyCandidates: [PadCandidate] { candidates.filter(\.isLikelyPad) }

    /// The interface most likely to be the configuration channel.
    public var bestCandidate: PadCandidate? { likelyCandidates.first }

    // MARK: - Open / close

    @discardableResult
    public func open(_ candidate: PadCandidate) -> Result<Void, PadError> {
        close()
        guard let dev = deviceMap[candidate.id] else { return .failure(.deviceGone) }
        let status = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        guard status == kIOReturnSuccess else {
            return .failure(.openFailed(status))
        }

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        inputBufferSize = max(64, candidate.maxInputReportSize)
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: inputBufferSize)
        buffer.initialize(repeating: 0, count: inputBufferSize)
        inputBuffer = buffer

        IOHIDDeviceRegisterInputReportCallback(dev, buffer, inputBufferSize, { context, _, _, _, reportId, report, length in
            guard let context else { return }
            let me = Unmanaged<PadTransport>.fromOpaque(context).takeUnretainedValue()
            let bytes = Array(UnsafeBufferPointer(start: report, count: length))
            let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
            me.onLog?(HIDLogEntry(outgoing: false,
                                  text: String(format: "id %02X | %@", reportId, hex),
                                  ok: true))
        }, ctx)
        IOHIDDeviceScheduleWithRunLoop(dev, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        device = dev
        openedCandidate = candidate
        return .success(())
    }

    public func close() {
        if let dev = device {
            IOHIDDeviceRegisterInputReportCallback(dev, inputBuffer ?? UnsafeMutablePointer<UInt8>.allocate(capacity: 1),
                                                   inputBufferSize, nil, nil)
            IOHIDDeviceUnscheduleFromRunLoop(dev, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        inputBuffer?.deallocate()
        inputBuffer = nil
        inputBufferSize = 0
        device = nil
        openedCandidate = nil
    }

    // MARK: - Writing

    @discardableResult
    public func write(_ report: PadReport, channel: ReportChannel) -> Result<Void, PadError> {
        guard let dev = device else { return .failure(.notOpen) }
        let status = report.data.withUnsafeBufferPointer { buf in
            IOHIDDeviceSetReport(dev, channel.iokitType, CFIndex(report.reportId), buf.baseAddress!, buf.count)
        }
        let ok = status == kIOReturnSuccess
        onLog?(HIDLogEntry(outgoing: true,
                           text: report.hexDump() + (ok ? "" : String(format: "   ✗ 0x%08X", UInt32(bitPattern: status))),
                           ok: ok))
        return ok ? .success(()) : .failure(.writeFailed(status))
    }

    /// Writes a report, retrying on the other channel once if the first fails.
    @discardableResult
    public func writeWithFallback(_ report: PadReport, preferred: ReportChannel) -> Result<ReportChannel, PadError> {
        if case .success = write(report, channel: preferred) { return .success(preferred) }
        let other: ReportChannel = preferred == .output ? .feature : .output
        if case .success = write(report, channel: other) { return .success(other) }
        return .failure(.writeFailed(kIOReturnError))
    }

    /// Finds the report id the firmware accepts, mirroring the original tool's
    /// probe order (0, then 2, then 3).
    public func probeReportId(channel: ReportChannel) -> UInt8 {
        for id: UInt8 in [0, 2, 3] {
            if case .success = write(ComposerFactory.versionProbe(reportId: id), channel: channel) {
                return id
            }
        }
        return 3
    }
}

public enum PadError: Error, LocalizedError {
    case notOpen
    case deviceGone
    case openFailed(IOReturn)
    case writeFailed(IOReturn)

    public var errorDescription: String? {
        switch self {
        case .notOpen: return "No device is open."
        case .deviceGone: return "The device was disconnected."
        case .openFailed(let s):
            if s == kIOReturnNotPermitted || s == kIOReturnNotPrivileged {
                return "macOS refused access to this interface. Grant the app Input Monitoring in System Settings › Privacy & Security."
            }
            return String(format: "Could not open the device (IOReturn 0x%08X).", UInt32(bitPattern: s))
        case .writeFailed(let s):
            return String(format: "Writing the report failed (IOReturn 0x%08X).", UInt32(bitPattern: s))
        }
    }
}
