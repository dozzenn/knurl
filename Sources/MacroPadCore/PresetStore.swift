import Foundation

/// A named set of mappings the user saved, to drop onto any scope later.
///
/// The same shape as a built-in template — one is shipped, one is yours — so
/// both can live in the same gallery and be applied the same way.
public struct Preset: Codable, Identifiable, Sendable {
    public var name: String
    public var summary: String
    public var profile: Profile
    public var created: Date

    public var id: String { name }

    public init(name: String, summary: String = "", profile: Profile, created: Date = Date()) {
        self.name = name
        self.summary = summary
        self.profile = profile
        self.created = created
    }
}

public final class PresetStore {
    public let directory: URL

    public init(directory: URL? = nil) {
        let base = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("MacroPad/Presets", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.directory = base
    }

    public func all() -> [Preset] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                  includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(Preset.self, from: Data(contentsOf: $0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func url(for name: String) -> URL {
        directory.appendingPathComponent(sanitize(name)).appendingPathExtension("json")
    }

    @discardableResult
    public func save(_ preset: Preset) throws -> Preset {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(preset).write(to: url(for: preset.name), options: .atomic)
        return preset
    }

    public func delete(_ preset: Preset) throws {
        try FileManager.default.removeItem(at: url(for: preset.name))
    }

    private func sanitize(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return cleaned.isEmpty ? "Untitled" : cleaned
    }
}
