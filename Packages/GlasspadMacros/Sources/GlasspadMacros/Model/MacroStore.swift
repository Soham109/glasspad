import Foundation

/// On-disk envelope for one macro. `formatVersion` lets later versions change
/// the layout: files from a newer Glasspad are refused with a clear error
/// instead of being half-read and then overwritten.
public struct MacroFile: Codable, Sendable {
    public static let currentVersion = 1
    public var formatVersion: Int
    public var macro: Macro

    public init(macro: Macro) {
        self.formatVersion = Self.currentVersion
        self.macro = macro
    }

    private struct VersionProbe: Decodable { var formatVersion: Int? }

    public static func decode(_ data: Data) throws -> Macro {
        let probe = try JSONDecoder().decode(VersionProbe.self, from: data)
        let version = probe.formatVersion ?? 0
        guard version <= currentVersion else {
            throw MacroError.unsupportedFormatVersion(found: version, supported: currentVersion)
        }
        if version == 0 {
            // Version 0: a bare macro object with no envelope (hand-written files).
            return try JSONDecoder().decode(Macro.self, from: data)
        }
        return try JSONDecoder().decode(MacroFile.self, from: data).macro
    }

    public static func encode(_ macro: Macro) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(MacroFile(macro: macro))
    }
}

/// Stores one JSON file per macro, named `<uuid>.json`.
public final class MacroStore: @unchecked Sendable {
    public struct LoadFailure: Sendable, Equatable {
        public var file: String
        public var message: String
    }

    public let directory: URL
    private let fm = FileManager.default
    private let lock = NSLock()

    /// `~/Library/Application Support/Glasspad`
    public static var defaultSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Glasspad", isDirectory: true)
    }

    public static var defaultDirectory: URL {
        defaultSupportDirectory.appendingPathComponent("macros", isDirectory: true)
    }

    public init(directory: URL = MacroStore.defaultDirectory) {
        self.directory = directory
    }

    private func url(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    /// Loads every macro. A broken file never hides the rest: it is reported
    /// in `failures` and left untouched on disk.
    public func loadAll() -> (macros: [Macro], failures: [LoadFailure]) {
        lock.lock(); defer { lock.unlock() }
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return ([], [])
        }
        var macros: [Macro] = []
        var failures: [LoadFailure] = []
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where file.pathExtension == "json" {
            do {
                macros.append(try MacroFile.decode(Data(contentsOf: file)))
            } catch let e as MacroError {
                failures.append(.init(file: file.lastPathComponent, message: e.description))
            } catch {
                failures.append(.init(file: file.lastPathComponent, message: String(describing: error)))
            }
        }
        return (macros, failures)
    }

    public func save(_ macro: Macro) throws {
        lock.lock(); defer { lock.unlock() }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try MacroFile.encode(macro).write(to: url(for: macro.id), options: .atomic)
    }

    public func delete(id: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        let u = url(for: id)
        if fm.fileExists(atPath: u.path) { try fm.removeItem(at: u) }
    }

    public func load(id: UUID) throws -> Macro {
        lock.lock(); defer { lock.unlock() }
        let u = url(for: id)
        guard fm.fileExists(atPath: u.path) else { throw MacroError.macroNotFound(id) }
        return try MacroFile.decode(Data(contentsOf: u))
    }
}
