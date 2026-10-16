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

/// Writes the starter macros and profiles once, brings them up to date when Glasspad ships
/// better ones, and restores them on request.
public enum StarterSeeder {
    /// Written by the first release: starters version 1 were seeded.
    static let markerName = ".starters-seeded-v1"
    /// Holds the starters version this Mac has, as text ("2").
    static let versionFileName = ".starters-version"

    /// First launch: writes every starter. After an update that ships new starters: upgrades
    /// (see `upgrade`). Otherwise does nothing, so a starter the user deleted stays deleted.
    /// Returns true when anything was written.
    @discardableResult
    public static func seedIfNeeded(macros: MacroStore, profiles: ProfileStore) throws -> Bool {
        let base = macros.directory.deletingLastPathComponent()
        let versionFile = base.appendingPathComponent(versionFileName)
        let stored = (try? String(contentsOf: versionFile, encoding: .utf8))
            .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let seededV1 = FileManager.default.fileExists(atPath: base.appendingPathComponent(markerName).path)
        let have = stored ?? (seededV1 ? 1 : nil)
        if let have, have >= StarterLibrary.version { return false }
        if let have {
            try upgrade(from: have, macros: macros, profiles: profiles)
        } else {
            try restoreStarters(macros: macros, profiles: profiles)
        }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try Data("\(StarterLibrary.version)".utf8).write(to: versionFile, options: .atomic)
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

    /// Moves starters from an older version to this one without losing anything the user did:
    /// - a starter still exactly as shipped is updated (or removed if it was dropped);
    /// - a starter the user edited is kept as they left it;
    /// - a starter the user deleted stays deleted;
    /// - starters new in this version are added, and profiles for new apps appear;
    /// - a starter profile the user changed keeps their changes and gets the new buttons at the end.
    public static func upgrade(from version: Int, macros: MacroStore, profiles: ProfileStore) throws {
        guard let oldDefinitions = StarterLibrary.definitions(version: version) else {
            // Unknown history: only add what is missing.
            return try addMissing(macros: macros, profiles: profiles)
        }
        let oldMacros = Dictionary(uniqueKeysWithValues: StarterLibrary.macros(from: oldDefinitions).map { ($0.id, $0) })
        let oldProfiles = Dictionary(uniqueKeysWithValues: StarterLibrary.profiles(from: oldDefinitions).map { ($0.id, $0) })
        let newMacros = StarterLibrary.macros
        let newIDs = Set(newMacros.map(\.id))
        let onDisk = Dictionary(macros.loadAll().macros.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var current = try profiles.load() ?? []

        // Macros.
        for m in newMacros {
            if let disk = onDisk[m.id] {
                if disk == oldMacros[m.id] { try macros.save(m) }   // untouched: update
            } else if oldMacros[m.id] == nil {
                try macros.save(m)                                  // new in this version
            }                                                       // else the user deleted it
        }
        let usedByUser = Set(current.filter { $0.origin != .starter || oldProfiles[$0.id] == nil }.flatMap(\.macroIDs))
        var removed = Set<UUID>()
        for (id, old) in oldMacros where !newIDs.contains(id) {
            guard let disk = onDisk[id], disk == old, !usedByUser.contains(id) else { continue }
            try macros.delete(id: id)
            removed.insert(id)
        }
        let gone = Set(oldMacros.keys).subtracting(newIDs).union(removed)
            .union(oldMacros.keys.filter { onDisk[$0] == nil })

        // Profiles.
        for p in StarterLibrary.profiles {
            if let i = current.firstIndex(where: { $0.id == p.id }) {
                if current[i] == oldProfiles[p.id] {
                    current[i] = p
                } else {
                    let old = Set(oldProfiles[p.id]?.macroIDs ?? [])
                    var edited = current[i]
                    edited.macroIDs.removeAll { removed.contains($0) }
                    let have = Set(edited.macroIDs)
                    edited.macroIDs += p.macroIDs.filter { !old.contains($0) && !have.contains($0) && !gone.contains($0) }
                    current[i] = edited
                }
            } else if oldProfiles[p.id] == nil {
                current.append(p)
            }
        }
        // Starter profiles that were dropped, if untouched.
        let newProfileIDs = Set(StarterLibrary.profiles.map(\.id))
        current.removeAll { p in !newProfileIDs.contains(p.id) && oldProfiles[p.id] != nil && p == oldProfiles[p.id] }
        try profiles.save(current)
    }

    private static func addMissing(macros: MacroStore, profiles: ProfileStore) throws {
        let have = Set(macros.loadAll().macros.map(\.id))
        for m in StarterLibrary.macros where !have.contains(m.id) { try macros.save(m) }
        var current = try profiles.load() ?? []
        let ids = Set(current.map(\.id))
        current += StarterLibrary.profiles.filter { !ids.contains($0.id) }
        try profiles.save(current)
    }
}
