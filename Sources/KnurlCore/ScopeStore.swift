import Foundation

/// Where a set of mappings applies: everywhere, or in one app.
///
/// This is the model the user thinks in — "what does this key do in Figma" —
/// rather than "which saved profile is loaded". Global is always present and
/// is the fallback whenever the front app has no mappings of its own.
public struct MappingScope: Identifiable, Hashable, Codable, Sendable {
    /// `"global"` or an app's bundle identifier.
    public let key: String
    public var name: String

    public var id: String { key }
    public var isGlobal: Bool { key == MappingScope.globalKey }

    public static let globalKey = "global"
    public static let global = MappingScope(key: globalKey, name: "Global")

    public init(key: String, name: String) {
        self.key = key
        self.name = name
    }
}

/// Holds every scope's mappings in one file.
public final class ScopeStore {
    private struct Payload: Codable {
        var scopes: [MappingScope]
        var profiles: [String: Profile]
    }

    private let url: URL
    public private(set) var scopes: [MappingScope]
    private var profiles: [String: Profile]

    public init(directory: URL? = nil) {
        let base = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Knurl", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("scopes.json")

        if let data = try? Data(contentsOf: url),
           let payload = try? JSONDecoder().decode(Payload.self, from: data) {
            scopes = payload.scopes
            profiles = payload.profiles
        } else {
            scopes = [.global]
            profiles = [:]
        }
        if !scopes.contains(where: { $0.isGlobal }) { scopes.insert(.global, at: 0) }
    }

    public func profile(for key: String) -> Profile {
        profiles[key] ?? Profile(name: scopes.first { $0.key == key }?.name ?? key)
    }

    public func setProfile(_ profile: Profile, for key: String) {
        profiles[key] = profile
        save()
    }

    /// True when this scope has anything mapped at all.
    public func hasMappings(_ key: String, layerCount: UInt8) -> Bool {
        !(profiles[key]?.configured(layerCount: layerCount).isEmpty ?? true)
    }

    @discardableResult
    public func addScope(key: String, name: String) -> MappingScope {
        if let existing = scopes.first(where: { $0.key == key }) { return existing }
        let scope = MappingScope(key: key, name: name)
        scopes.append(scope)
        scopes.sort { a, b in
            if a.isGlobal != b.isGlobal { return a.isGlobal }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        save()
        return scope
    }

    public func removeScope(key: String) {
        guard key != MappingScope.globalKey else { return }
        scopes.removeAll { $0.key == key }
        profiles.removeValue(forKey: key)
        save()
    }

    private func save() {
        let payload = Payload(scopes: scopes, profiles: profiles)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(payload).write(to: url, options: .atomic)
    }
}
