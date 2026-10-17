import Foundation

/// How much a cache folder on the phone may hold: at most `maxFiles` files and `maxBytes`
/// bytes. The newest files are kept; `overflow` names the rest, oldest first.
public struct DiskCacheLimit: Equatable, Sendable {
    public var maxFiles: Int
    public var maxBytes: Int

    public init(maxFiles: Int, maxBytes: Int) {
        self.maxFiles = maxFiles
        self.maxBytes = maxBytes
    }

    public struct File<ID: Sendable>: Sendable {
        public var id: ID
        public var modified: Date
        public var bytes: Int

        public init(id: ID, modified: Date, bytes: Int) {
            self.id = id
            self.modified = modified
            self.bytes = bytes
        }
    }

    /// The files to delete so the rest fit, oldest first. The newest file always stays, even
    /// when it alone is over `maxBytes`.
    public func overflow<ID>(_ files: [File<ID>]) -> [ID] {
        var total = 0
        var kept = 0
        var drop: [ID] = []
        for file in files.sorted(by: { $0.modified > $1.modified }) {
            let fits = kept == 0 || (kept < maxFiles && total + file.bytes <= maxBytes)
            if fits {
                kept += 1
                total += file.bytes
            } else {
                drop.append(file.id)
            }
        }
        return drop.reversed()
    }
}
