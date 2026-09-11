import Foundation

public struct ControlPosition: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double = 20, height: Double = 20) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

public enum ControlKind: Hashable, Sendable {
    case button(index: Int)
    case knob(index: Int)
}

public struct PhysicalControl: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public var kind: ControlKind
    public var position: ControlPosition

    public var label: String {
        switch kind {
        case .button(let i): return "\(i)"
        case .knob(let i): return "K\(i)"
        }
    }

    /// Every action this control can be bound to.
    public var actions: [InputAction] {
        switch kind {
        case .button(let i): return [.key(i)]
        case .knob(let i): return KnobPart.allCases.map { InputAction.knob(i, $0) }
        }
    }
}

public struct KeyboardLayout: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public var name: String
    public var products: [(vendorId: UInt16, productId: UInt16)]
    public var layerCount: UInt8
    public var maxCharacters: Int
    public var supportsDelay: Bool
    public var supportsColor: Bool
    public var ledModeCount: Int
    public var controls: [PhysicalControl]

    public static func == (a: KeyboardLayout, b: KeyboardLayout) -> Bool { a.name == b.name }
    public func hash(into h: inout Hasher) { h.combine(name) }

    public func matches(vendorId: UInt16, productId: UInt16) -> Bool {
        products.contains { $0.vendorId == vendorId && $0.productId == productId }
    }

    public var contentSize: (width: Double, height: Double) {
        let w = controls.map { $0.position.x + $0.position.width }.max() ?? 100
        let h = controls.map { $0.position.y + $0.position.height }.max() ?? 100
        return (w + 5, h + 5)
    }
}

public enum LayoutLibrary {

    private static func buttons(_ specs: [(Int, Double, Double)]) -> [PhysicalControl] {
        specs.map { PhysicalControl(kind: .button(index: $0.0),
                                    position: ControlPosition(x: $0.1, y: $0.2)) }
    }

    private static func knob(_ i: Int, _ x: Double, _ y: Double, _ w: Double = 20, _ h: Double = 20) -> PhysicalControl {
        PhysicalControl(kind: .knob(index: i), position: ControlPosition(x: x, y: y, width: w, height: h))
    }

    /// Ported from the original `layouts.txt`, with the vendor id typo (4498)
    /// corrected to 4489 = 0x1189.
    public static let all: [KeyboardLayout] = [
        KeyboardLayout(
            name: "3 buttons, 1 knob",
            products: [(0x1189, 0x8890)],
            layerCount: 1, maxCharacters: 5, supportsDelay: false, supportsColor: false, ledModeCount: 3,
            controls: buttons([(1, 5, 5), (2, 25, 5), (3, 45, 5)]) + [knob(1, 70, 5)]
        ),
        KeyboardLayout(
            name: "6 buttons, 1 knob",
            products: [(0x1189, 0x8831)],
            layerCount: 3, maxCharacters: 18, supportsDelay: true, supportsColor: true, ledModeCount: 6,
            controls: buttons([(1, 5, 5), (2, 25, 5), (3, 45, 5), (4, 5, 25), (5, 25, 25), (6, 45, 25)])
                + [knob(1, 70, 15)]
        ),
        KeyboardLayout(
            name: "6 buttons, 2 knobs",
            products: [(0x1189, 0x8831)],
            layerCount: 3, maxCharacters: 18, supportsDelay: true, supportsColor: true, ledModeCount: 6,
            controls: buttons([(1, 5, 5), (2, 25, 5), (3, 45, 5), (4, 5, 25), (5, 25, 25), (6, 45, 25)])
                + [knob(1, 70, 5), knob(2, 70, 25)]
        ),
        KeyboardLayout(
            name: "9 buttons, 2 knobs",
            products: [(0x1189, 0x8830)],
            layerCount: 3, maxCharacters: 18, supportsDelay: true, supportsColor: true, ledModeCount: 6,
            controls: buttons([(1, 5, 30), (2, 25, 30), (3, 45, 30),
                               (4, 5, 50), (5, 25, 50), (6, 45, 50),
                               (7, 5, 70), (8, 25, 70), (9, 45, 70)])
                + [knob(1, 12, 5), knob(2, 37, 5)]
        ),
        KeyboardLayout(
            name: "12 buttons, 3 knobs (v1)",
            products: [(0x1189, 0x8832)],
            layerCount: 3, maxCharacters: 18, supportsDelay: true, supportsColor: true, ledModeCount: 6,
            controls: buttons([(1, 5, 5), (2, 25, 5), (3, 45, 5), (4, 65, 5),
                               (5, 5, 25), (6, 25, 25), (7, 45, 25), (8, 65, 25),
                               (9, 5, 45), (10, 25, 45), (11, 45, 45), (12, 65, 45)])
                + [knob(1, 95, 12), knob(2, 95, 38), knob(3, 90, 65, 30, 30)]
        ),
        KeyboardLayout(
            name: "12 buttons, 3 knobs (v2)",
            products: [(0x1189, 0x8832)],
            layerCount: 3, maxCharacters: 18, supportsDelay: true, supportsColor: true, ledModeCount: 6,
            controls: buttons([(1, 5, 5), (2, 25, 5), (3, 45, 5), (4, 65, 5),
                               (5, 5, 25), (6, 25, 25), (7, 45, 25), (8, 65, 25),
                               (9, 5, 45), (10, 25, 45), (11, 45, 45), (12, 65, 45)])
                + [knob(1, 93, 5), knob(2, 117, 5), knob(3, 95, 25, 40, 40)]
        ),
        KeyboardLayout(
            name: "Mini typewriter (6 buttons, 2 knobs)",
            products: [(0x1189, 0x8840)],
            layerCount: 3, maxCharacters: 18, supportsDelay: true, supportsColor: true, ledModeCount: 6,
            controls: buttons([(1, 5, 30), (2, 25, 30), (3, 45, 30),
                               (4, 5, 50), (5, 25, 50), (6, 45, 50)])
                + [knob(1, 5, 5), knob(2, 45, 5)]
        ),
        KeyboardLayout(
            // SDINNOVATION SIDE-KEYBOARD. Layout taken from the vendor's own
            // definition file (6d7b_dcfa.json, "keyboard3n1"): three keys in a
            // row plus one knob, one layer, six stored profiles.
            //
            // A key entry holds one keystroke. It can point at a macro
            // instead, but macros do not run on this firmware, so one is what
            // a key can actually hold.
            name: "3 keys, 1 knob (SIDE-KEYBOARD)",
            products: [(0x6D7B, 0xDCFA)],
            layerCount: 1, maxCharacters: 1, supportsDelay: false, supportsColor: false, ledModeCount: 6,
            controls: buttons([(1, 5, 22), (2, 27, 22), (3, 49, 22)]) + [knob(1, 74, 8, 42, 42)]
        ),
        KeyboardLayout(
            name: "4 buttons, 1 knob",
            products: [],
            layerCount: 3, maxCharacters: 18, supportsDelay: true, supportsColor: true, ledModeCount: 6,
            controls: buttons([(1, 5, 5), (2, 25, 5), (3, 5, 25), (4, 25, 25)]) + [knob(1, 50, 15)]
        ),
        KeyboardLayout(
            name: "Generic — 12 buttons, 3 knobs",
            products: [],
            layerCount: 3, maxCharacters: 18, supportsDelay: true, supportsColor: true, ledModeCount: 6,
            controls: buttons([(1, 5, 5), (2, 25, 5), (3, 45, 5), (4, 65, 5),
                               (5, 5, 25), (6, 25, 25), (7, 45, 25), (8, 65, 25),
                               (9, 5, 45), (10, 25, 45), (11, 45, 45), (12, 65, 45)])
                + [knob(1, 95, 5), knob(2, 95, 25), knob(3, 95, 45)]
        ),
    ]

    public static func best(forVendorId vid: UInt16, productId pid: UInt16) -> KeyboardLayout? {
        all.first { $0.matches(vendorId: vid, productId: pid) }
    }

    public static var `default`: KeyboardLayout { all.first { $0.name.hasPrefix("6 buttons, 2") } ?? all[0] }
}
