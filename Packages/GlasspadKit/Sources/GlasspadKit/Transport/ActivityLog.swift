import Foundation

/// A small activity log on disk, so a problem a person saw ("play/pause did nothing for a few
/// minutes") still has a record afterwards. `GPLog` goes to the unified log, which keeps
/// Glasspad's messages only briefly or not at all.
///
/// - One line per event: local time, a category, then `key=value` fields.
///   `2026-10-17T21:04:05.120+02:00 media cmd=playPause route=adapter ok=true np=com.google.Chrome`
/// - Capped: when the file passes `maxBytes`, the oldest lines go and the newest half stays,
///   so it never grows past `maxBytes`.
/// - Private: the folder is 0700 and the file 0600. Callers log states, routes, results and app
///   bundle ids only, never song or video titles, typed text, clipboard content or names.
/// - Off until `start(at:)` is called, so tests and extensions never write to the real file.
///
/// Writes run on a background queue; `record` never blocks the caller.
public final class ActivityLog: @unchecked Sendable {
    public static let shared = ActivityLog()

    /// Mac: ~/Library/Logs/Glasspad/activity.log. iPhone: the same path inside the app's container.
    public static var defaultURL: URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        return library.appendingPathComponent("Logs/Glasspad/activity.log")
    }

    /// The default cap: about two thousand lines.
    public static let defaultMaxBytes = 256 * 1024
    /// Longest value kept per field, so no field can carry a long text.
    static let maxValueLength = 80

    private let queue = DispatchQueue(label: "glasspad.activitylog", qos: .utility)
    private let clock: @Sendable () -> Date
    private let timeZone: TimeZone
    // Everything below is used on `queue` only.
    private var url: URL?
    private var maxBytes = ActivityLog.defaultMaxBytes
    private var handle: FileHandle?
    private var size = 0
    private lazy var formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = timeZone
        return f
    }()

    public init(clock: @escaping @Sendable () -> Date = { Date() }, timeZone: TimeZone = .current) {
        self.clock = clock
        self.timeZone = timeZone
    }

    /// Starts writing to `url` (creating its folder), capped at `maxBytes`.
    public func start(at url: URL = ActivityLog.defaultURL, maxBytes: Int = ActivityLog.defaultMaxBytes) {
        queue.async {
            self.close()
            self.url = url
            self.maxBytes = max(1024, maxBytes)
            self.open()
        }
    }

    /// The file being written, nil before `start`.
    public var fileURL: URL? { queue.sync { url } }

    /// Adds one line. Fields with a nil value are left out; values are cleaned (see `clean`).
    public func record(_ category: String, _ fields: KeyValuePairs<String, String?> = [:]) {
        let at = clock()
        let pairs = fields.compactMap { key, value in value.map { (key, $0) } }
        queue.async {
            guard self.url != nil else { return }
            let line = Self.line(time: self.formatter.string(from: at), category: category, fields: pairs)
            self.append(line)
        }
    }

    /// Waits for every line recorded so far to reach the file.
    public func flush() { queue.sync {} }

    /// The file as text (empty when there is none).
    public func contents() -> String {
        queue.sync {
            guard let url, let data = try? Data(contentsOf: url) else { return "" }
            return String(decoding: data, as: UTF8.self)
        }
    }

    // MARK: Format

    static func line(time: String, category: String, fields: [(String, String)]) -> String {
        var parts = [time, clean(category)]
        for (key, value) in fields { parts.append("\(clean(key))=\(clean(value))") }
        return parts.joined(separator: " ") + "\n"
    }

    /// One token: no spaces or line breaks (they become `_`), no control characters, at most
    /// `maxValueLength` characters (longer ends in `…`). Empty becomes `-`.
    static func clean(_ value: String) -> String {
        var out = ""
        for scalar in value.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                out.unicodeScalars.append("_")
            } else if !CharacterSet.controlCharacters.contains(scalar) {
                out.unicodeScalars.append(scalar)
            }
        }
        if out.isEmpty { return "-" }
        if out.count > maxValueLength { return String(out.prefix(maxValueLength - 1)) + "…" }
        return out
    }

    // MARK: File (on `queue`)

    private func open() {
        guard let url else { return }
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // A folder or file made earlier (or by hand) is tightened too.
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        } else {
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        #if os(iOS)
        // Troubleshooting only: never part of an iCloud or computer backup.
        var folder = dir
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
        #endif
        handle = try? FileHandle(forWritingTo: url)
        size = Int((try? handle?.seekToEnd()) ?? 0)
    }

    private func close() {
        try? handle?.close()
        handle = nil
    }

    private func append(_ line: String) {
        let data = Data(line.utf8)
        // Deleted by hand (to clear it): writes would go to the deleted file, so start a new one.
        if let url, !FileManager.default.fileExists(atPath: url.path) {
            close()
            open()
        }
        if size + data.count > maxBytes { trim(adding: data.count) }
        guard let handle else { return }
        do {
            try handle.write(contentsOf: data)
            size += data.count
        } catch {
            // The file went away (deleted by hand): start a new one next time.
            close()
            open()
        }
    }

    /// Keeps the newest whole lines that fit in half the cap, with room for the next line.
    private func trim(adding incoming: Int) {
        guard let url else { return }
        close()
        let data = (try? Data(contentsOf: url)) ?? Data()
        let budget = max(0, maxBytes / 2 - incoming)
        var start = data.endIndex
        var kept = 0
        // Walk back line by line from the end.
        var cursor = data.endIndex
        while cursor > data.startIndex {
            let lineStart = data[data.startIndex..<data.index(before: cursor)].lastIndex(of: 0x0A).map { data.index(after: $0) }
                ?? data.startIndex
            let length = cursor - lineStart
            if kept + length > budget { break }
            kept += length
            start = lineStart
            cursor = lineStart
        }
        let tail = data[start..<data.endIndex]
        try? Data(tail).write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        open()
    }
}

public extension LinkState {
    /// A short name for the activity log: idle, searching, connecting, connected or failed.
    var logName: String {
        switch self {
        case .idle: "idle"
        case .searching: "searching"
        case .connecting: "connecting"
        case .connected: "connected"
        case .failed: "failed"
        }
    }

    /// Why it failed, nil otherwise.
    var failureReason: String? {
        if case .failed(let why) = self { return why }
        return nil
    }
}
