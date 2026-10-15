import Foundation

/// Which macros show on the phone while a given app is frontmost, like a
/// Stream Deck profile that switches by itself.
public struct ContextProfile: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var symbol: String
    /// Apps this profile applies to. Ignored for the fallback profile.
    public var bundleIDs: [String]
    /// Buttons, in order, by macro id.
    public var macroIDs: [UUID]
    /// Used when no other profile matches the frontmost app. At most one
    /// profile should have this set; the first one wins.
    public var isFallback: Bool
    public var origin: ItemOrigin

    public init(id: UUID = UUID(), name: String, symbol: String = "square.grid.2x2", bundleIDs: [String],
                macroIDs: [UUID], isFallback: Bool = false, origin: ItemOrigin = .user) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.bundleIDs = bundleIDs
        self.macroIDs = macroIDs
        self.isFallback = isFallback
        self.origin = origin
    }

    enum CodingKeys: String, CodingKey { case id, name, symbol, bundleIDs, macroIDs, isFallback, origin }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? "square.grid.2x2"
        bundleIDs = try c.decodeIfPresent([String].self, forKey: .bundleIDs) ?? []
        macroIDs = try c.decodeIfPresent([UUID].self, forKey: .macroIDs) ?? []
        isFallback = try c.decodeIfPresent(Bool.self, forKey: .isFallback) ?? false
        origin = try c.decodeIfPresent(ItemOrigin.self, forKey: .origin) ?? .user
    }
}

public enum ProfileResolver {
    /// Picks the profile for the frontmost app. A profile the user made beats
    /// a starter for the same app; otherwise list order decides. With no
    /// match, the fallback profile is used.
    public static func resolve(bundleID: String?, in profiles: [ContextProfile]) -> ContextProfile? {
        if let bundleID {
            let matches = profiles.filter { !$0.isFallback && $0.bundleIDs.contains(bundleID) }
            if let mine = matches.first(where: { $0.origin != .starter }) { return mine }
            if let starter = matches.first { return starter }
        }
        return profiles.first(where: \.isFallback)
    }
}

/// `profiles.json`: every profile in one versioned file.
public struct ProfilesFile: Codable, Sendable {
    public static let currentVersion = 1
    public var formatVersion: Int
    public var profiles: [ContextProfile]

    public init(profiles: [ContextProfile]) {
        self.formatVersion = Self.currentVersion
        self.profiles = profiles
    }

    private struct VersionProbe: Decodable { var formatVersion: Int }

    public static func decode(_ data: Data) throws -> [ContextProfile] {
        let version = try JSONDecoder().decode(VersionProbe.self, from: data).formatVersion
        guard version <= currentVersion else {
            throw MacroError.unsupportedFormatVersion(found: version, supported: currentVersion)
        }
        return try JSONDecoder().decode(ProfilesFile.self, from: data).profiles
    }

    public static func encode(_ profiles: [ContextProfile]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(ProfilesFile(profiles: profiles))
    }
}

public final class ProfileStore: @unchecked Sendable {
    public let file: URL
    private let lock = NSLock()

    public static var defaultFile: URL {
        MacroStore.defaultSupportDirectory.appendingPathComponent("profiles.json")
    }

    public init(file: URL = ProfileStore.defaultFile) {
        self.file = file
    }

    /// Returns nil when there is no file yet (first launch).
    public func load() throws -> [ContextProfile]? {
        lock.lock(); defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try ProfilesFile.decode(Data(contentsOf: file))
    }

    public func save(_ profiles: [ContextProfile]) throws {
        lock.lock(); defer { lock.unlock() }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ProfilesFile.encode(profiles).write(to: file, options: .atomic)
    }
}

/// Writes the starter macros and profiles once, and restores them on request.
public enum StarterSeeder {
    static let markerName = ".starters-seeded-v1"

    /// On first launch writes every starter. Afterwards does nothing, so a
    /// starter the user deleted stays deleted.
    @discardableResult
    public static func seedIfNeeded(macros: MacroStore, profiles: ProfileStore) throws -> Bool {
        let marker = macros.directory.deletingLastPathComponent().appendingPathComponent(markerName)
        guard !FileManager.default.fileExists(atPath: marker.path) else { return false }
        try restoreStarters(macros: macros, profiles: profiles)
        try Data().write(to: marker)
        return true
    }

    /// Rewrites every starter macro and starter profile to its shipped state.
    /// The user's own macros and profiles are left alone.
    public static func restoreStarters(macros: MacroStore, profiles: ProfileStore) throws {
        for macro in StarterLibrary.macros { try macros.save(macro) }
        var current = try profiles.load() ?? []
        let starters = StarterLibrary.profiles
        let starterIDs = Set(starters.map(\.id))
        current.removeAll { starterIDs.contains($0.id) }
        try profiles.save(starters + current)
    }
}
