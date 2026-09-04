import Foundation

/// The full set of mappings for one device, across all its layers.
public struct Profile: Codable, Sendable {
    public var name: String
    public var layoutName: String
    public var bindings: [String: ControlBinding]   // "layer:actionRawValue" → binding
    public var ledMode: LedMode
    public var ledColor: LedColor

    public init(name: String = "Untitled",
                layoutName: String = LayoutLibrary.default.name,
                bindings: [String: ControlBinding] = [:],
                ledMode: LedMode = .mode0,
                ledColor: LedColor = .random) {
        self.name = name
        self.layoutName = layoutName
        self.bindings = bindings
        self.ledMode = ledMode
        self.ledColor = ledColor
    }

    public static func key(layer: UInt8, action: InputAction) -> String {
        "\(layer):\(action.rawValue)"
    }

    public subscript(layer: UInt8, action: InputAction) -> ControlBinding {
        get { bindings[Profile.key(layer: layer, action: action)] ?? .unset }
        set {
            let k = Profile.key(layer: layer, action: action)
            if newValue.isSet { bindings[k] = newValue } else { bindings.removeValue(forKey: k) }
        }
    }

    /// Every configured mapping, in a stable upload order.
    public func configured(layerCount: UInt8) -> [(layer: UInt8, action: InputAction, binding: ControlBinding)] {
        var out: [(UInt8, InputAction, ControlBinding)] = []
        for layer in 0..<max(layerCount, 1) {
            for action in InputAction.allCases where action != .none {
                let b = self[layer, action]
                if b.isSet { out.append((layer, action, b)) }
            }
        }
        return out.map { (layer: $0.0, action: $0.1, binding: $0.2) }
    }
}
