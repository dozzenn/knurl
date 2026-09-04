import Foundation

/// Named profiles kept on disk so the pad can be reconfigured for a different
/// app or task in one action.
public final class ProfileStore {

    public struct Entry: Identifiable, Hashable, Sendable {
        public let id: String       // file name without extension
        public var name: String
        public var url: URL
        public var modified: Date
    }

    public let directory: URL

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directory = base.appendingPathComponent("MacroPad/Profiles", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    public func list() -> [Entry] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                  includingPropertiesForKeys: keys)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .map { url in
                let modified = (try? url.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
                let id = url.deletingPathExtension().lastPathComponent
                return Entry(id: id, name: id, url: url, modified: modified)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func url(for name: String) -> URL {
        directory.appendingPathComponent(sanitize(name)).appendingPathExtension("json")
    }

    @discardableResult
    public func save(_ profile: Profile, as name: String) throws -> Entry {
        var p = profile
        p.name = name
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let target = url(for: name)
        try encoder.encode(p).write(to: target, options: .atomic)
        return Entry(id: target.deletingPathExtension().lastPathComponent, name: name, url: target, modified: Date())
    }

    public func load(_ entry: Entry) throws -> Profile {
        try JSONDecoder().decode(Profile.self, from: Data(contentsOf: entry.url))
    }

    public func delete(_ entry: Entry) throws {
        try FileManager.default.removeItem(at: entry.url)
    }

    public func rename(_ entry: Entry, to name: String) throws {
        var profile = try load(entry)
        profile.name = name
        try save(profile, as: name)
        if url(for: name) != entry.url { try? FileManager.default.removeItem(at: entry.url) }
    }

    private func sanitize(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return cleaned.isEmpty ? "Untitled" : cleaned
    }
}
